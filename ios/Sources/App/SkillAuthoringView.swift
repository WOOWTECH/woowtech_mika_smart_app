import AssistantSkills
import SwiftUI

/// Manual host consumer of the typed bridge. User input is captured here; neither
/// source Markdown nor model/MCP output can produce an approval or write a skill.
@MainActor
struct SkillAuthoringView: View {
    @ObservedObject var store: LearningStore
    let catalog: BundledSkillCatalog
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?
    @State private var step: Step = .request
    @State private var requestText = ""
    @State private var capturedRequest = ""
    @State private var session: SkillAuthoringBridge?
    @State private var query = ""
    @State private var matches: [SkillAuthoringMatch] = []
    @State private var read: SkillAuthoringRead?
    @State private var replacing: SkillAuthoringRead?
    @State private var markdown = ""
    @State private var review: SkillAuthoringSaveReview?
    @State private var receipt: SkillAuthoringSaveReceipt?
    @State private var failure: String?
    @Environment(\.appLocalizer) private var localizer

    private enum Step { case request, lookup, reading, editing, review, saved }
    private enum Field: Hashable { case request, search, markdown }

    var body: some View {
        Form {
            if let failure {
                Section { Text(verbatim: localizer.stored(failure)).foregroundStyle(.red).accessibilityIdentifier("authoring.error") }
            }
            switch step {
            case .request: requestSection
            case .lookup: lookupSection
            case .reading: readSection
            case .editing: editorSection
            case .review: reviewSection
            case .saved: savedSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) { actions }
                .buttonStyle(.borderedProminent)
                .padding().frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .navigationTitle(localizer.text(.authoringTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localizer.text(step == .saved ? .commonDone : .commonCancel)) {
                    session?.cancel(); focused = nil; dismiss()
                }
                .accessibilityIdentifier("authoring.close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                if focused == .markdown {
                    Button(localizer.text(.authoringClearFullText)) { markdown = "" }.accessibilityIdentifier("authoring.keyboard.clear")
                }
                Spacer()
                Button(localizer.text(.commonDoneTyping)) { focused = nil }.accessibilityIdentifier("authoring.keyboard.done")
            }
        }
        .onDisappear { session?.cancel() }
    }

    private var requestSection: some View {
        Section(localizer.text(.authoringRequestSection)) {
            Text(localizer.text(.authoringIntro))
                .accessibilityIdentifier("authoring.intro")
            TextEditor(text: $requestText).frame(minHeight: 110)
                .focused($focused, equals: .request).autocorrectionDisabled()
                .accessibilityLabel(localizer.text(.authoringRequestLabel)).accessibilityIdentifier("authoring.request")
            Text(localizer.text(.authoringScope))
                .font(.footnote).accessibilityIdentifier("authoring.scope")
        }
    }

    @ViewBuilder private var lookupSection: some View {
        Section(localizer.text(.authoringLookupSection)) {
            TextField(localizer.text(.authoringSearchPlaceholder), text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focused, equals: .search).submitLabel(.search)
                .onSubmit { search() }.accessibilityIdentifier("authoring.search")
            Button(localizer.text(.authoringSearch)) { search() }.accessibilityIdentifier("authoring.search.submit")
            Text(localizer.text(.authoringLookupHelp))
                .font(.footnote)
            ForEach(matches, id: \.reference) { match in
                Button {
                    perform {
                        read = try requireSession().read(match.reference)
                        focused = nil; step = .reading
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: match.name)
                        Text(verbatim: match.description).font(.caption)
                        Text(match.status.map(statusTitle) ?? localizer.text(.authoringBundledReadOnly)).font(.caption)
                        if match.hasPendingDraft { Text(localizer.text(.authoringHasDraft)).font(.caption) }
                    }
                }
                .accessibilityIdentifier("authoring.match." + referenceID(match.reference))
            }
            if matches.isEmpty { Text(localizer.text(.authoringNoMatches)).accessibilityIdentifier("authoring.empty") }
        }
    }

    @ViewBuilder private var readSection: some View {
        if let read {
            Section(localizer.text(.authoringFullTextSection)) {
                Text(localizer.text(.authoringReadHelp))
                fullText(read.markdown, identifier: "authoring.read.full")
            }
            Section {
                DisclosureGroup(localizer.text(.authoringSourceVersion)) {
                    Text(verbatim: referenceID(read.reference) + "\n" + read.version + "\nSHA-256: " + read.fingerprint)
                        .font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier("authoring.read.source")
                }
            }
        }
    }

    private var editorSection: some View {
        Section(localizer.text(replacing == nil ? .authoringNewSection : .authoringEditSection)) {
            Text(localizer.text(.authoringEditorHelp))
                .font(.footnote)
            TextEditor(text: $markdown).frame(minHeight: 260)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focused, equals: .markdown)
                .accessibilityLabel(localizer.text(.authoringMarkdownLabel)).accessibilityIdentifier("authoring.markdown")
            Text(localizer.text(.authoringEditorRule))
                .font(.footnote)
        }
    }

    @ViewBuilder private var reviewSection: some View {
        if let review {
            Section(localizer.text(.authoringRequestLabel)) {
                Text(verbatim: review.requestQuote).accessibilityIdentifier("authoring.review.request")
            }
            Section(localizer.text(review.isUpdate ? .authoringWillReplace : .authoringWillAdd)) {
                Text(verbatim: review.name).accessibilityIdentifier("authoring.review.name")
                Text(localizer.text(.authoringReviewState))
                    .accessibilityIdentifier("authoring.review.state")
                fullText(review.markdown, identifier: "authoring.review.full")
            }
            Section {
                DisclosureGroup(localizer.text(.authoringSourceVersion)) {
                    Text(verbatim: review.original.path + "\n" + review.original.revision
                        + "\n" + localizer.text(.authoringOriginalHash(value: review.original.sha256))
                        + "\n" + localizer.text(.authoringDraftHash(value: review.draftFingerprint))
                        + (review.replacesFingerprint.map { "\n" + localizer.text(.authoringReplacedHash(value: $0)) } ?? ""))
                        .font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier("authoring.review.source")
                }
            }
        }
    }

    @ViewBuilder private var savedSection: some View {
        if let receipt {
            Section(localizer.text(.authoringSavedSection)) {
                Text(verbatim: receipt.name).accessibilityIdentifier("authoring.saved.name")
                Text(localizer.text(receipt.updated ? .authoringSavedUpdated : .authoringSavedAdded))
                    .accessibilityIdentifier("authoring.saved.status")
                Text(localizer.text(.authoringSavedHelp))
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch step {
        case .request:
            Button(localizer.text(.authoringBegin)) { begin() }
                .disabled(!store.available || requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("authoring.begin")
        case .lookup:
            Button(localizer.text(.authoringNew)) {
                replacing = nil; markdown = Self.template; failure = nil; focused = nil; step = .editing
            }.accessibilityIdentifier("authoring.new")
        case .reading:
            if let read, case .personal = read.reference, read.status != .suspended {
                Button(localizer.text(.authoringEditRead)) {
                    replacing = read; markdown = read.markdown; failure = nil; step = .editing
                }.accessibilityIdentifier("authoring.edit.read")
            }
            Button(localizer.text(.authoringBackToLookup)) { failure = nil; step = .lookup }.accessibilityIdentifier("authoring.lookup")
        case .editing:
            Button(localizer.text(.authoringPrepare)) { prepare() }.accessibilityIdentifier("authoring.prepare")
            Button(localizer.text(.authoringBackToLookup)) { focused = nil; failure = nil; search(); step = .lookup }
                .accessibilityIdentifier("authoring.lookup")
        case .review:
            Button(localizer.text(.authoringApprove)) { save() }
                .disabled(!store.available).accessibilityIdentifier("authoring.approve")
            Button(localizer.text(.authoringRevise)) { review = nil; failure = nil; step = .editing }
                .accessibilityIdentifier("authoring.revise")
        case .saved: EmptyView()
        }
    }

    private func begin() {
        perform {
            let request = try SkillAuthoringUserRequest(quote: requestText)
            capturedRequest = request.quote
            session = SkillAuthoringBridge(request: request, store: store, catalog: catalog)
            matches = try requireSession().search(query: "")
            focused = nil; step = .lookup
        }
    }

    private func search() {
        focused = nil
        perform { matches = try requireSession().search(query: query) }
    }

    private func prepare() {
        focused = nil
        perform {
            review = try requireSession().prepareSave(markdown: markdown, quote: capturedRequest, replacing: replacing)
            step = .review
        }
    }

    private func save() {
        // This button is the sole grant issuer. Both operations are synchronous
        // on MainActor; receipt appears only after the encrypted store returns.
        perform {
            guard let review else { throw SkillAuthoringError.reviewChanged }
            let bridge = try requireSession()
            do {
                let approval = try bridge.approve(reviewID: review.id, draftFingerprint: review.draftFingerprint)
                receipt = try bridge.commitReviewedSave(reviewID: review.id,
                    draftFingerprint: review.draftFingerprint, approval: approval)
                self.review = nil; step = .saved
            } catch {
                self.review = nil; step = .editing
                throw error
            }
        }
    }

    private func requireSession() throws -> SkillAuthoringBridge {
        guard let session else { throw SkillAuthoringError.cancelled }
        return session
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); failure = nil }
        catch { failure = LearningStore.message(error) }
    }

    private func fullText(_ value: String, identifier: String) -> some View {
        Text(verbatim: value).font(.system(.body, design: .monospaced))
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }

    private func statusTitle(_ status: SkillStatus) -> String {
        localizer.text(.skillStatus(status))
    }

    private func referenceID(_ reference: SkillAuthoringReference) -> String {
        switch reference {
        case .personal(let name): return "personal." + name
        case .bundled(let name): return "bundled." + name
        }
    }

    private static let template = """
    ---
    name:
    display:
    description:
    aliases: []
    ---
    ## 入口

    ## 步驟

    ## 容易出錯的地方

    ## 怎樣算辦成

    ## 什麼時候停下交給使用者

    """
}
