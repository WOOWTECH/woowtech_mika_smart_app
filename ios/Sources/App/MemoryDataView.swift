import AssistantMemory
import AssistantSkills
import Combine
import SwiftUI

@MainActor
struct MemoryDataView: View {
    @ObservedObject var store: LearningStore
    @ObservedObject var browser: BrowserSession
    #if os(iOS)
    let browserWorkspace: BrowserWorkspace
    @State private var showWebsiteData = false
    #endif
    let modelAccess: () throws -> ModelAccess
    let modelChanges: AnyPublisher<Void, Never>
    let onOpenBrowser: () -> Void
    @State private var segment: LearningSegment = .memories
    @State private var query = ""
    @State private var sheet: LearningSheet?
    @State private var deletionReview: SkillDeletionReview?
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.appLocalizer) private var appLocalizer
    private var copy: MemoryDataCopy { MemoryDataCopy(language: appLocalizer.language) }
    #else
    private var copy: MemoryDataCopy { MemoryDataCopy(language: .traditionalChinese) }
    #endif

    private var palette: MemoryPalette { MemoryPalette(dark: colorScheme == .dark) }

    // Approval stores guidance; it does not start a task or grant capabilities.
    // Browser references are usable only in the explicitly started research mode.
    private let toolNames = BrowserSession.toolNames

    private var pendingCount: Int {
        store.memory.memories.filter { $0.status == .pending }.count + store.skills.pending.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            contentList
        }
        .background(palette.background)
        // The root tab and the chat drawer both supply a NavigationStack.
        // Keep its title and the centered principal item on the same resolved language.
        .navigationTitle(copy.text(.title))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(copy.text(.title))
                    .font(.headline)
                    .accessibilityIdentifier("memory.status")
            }
        }
        .memoryNavigationBackground(palette.background)
        .tint(palette.accent)
        .sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
                case .memory(let item):
                    MemoryEditor(store: store, item: item)
                case .importSkill:
                    SkillEditor(store: store, draft: nil, toolNames: toolNames) { segment = .pending }
                case .editSkill(let draft):
                    SkillEditor(store: store, draft: draft, toolNames: toolNames) { segment = .skills }
                case .fullText(let title, let markdown):
                    SkillTextView(title: title, markdown: markdown)
                case .clear:
                    LearningClearView(store: store)
                case .websites:
                    WebsiteDataView(store: store, browser: browser, modelAccess: modelAccess, onOpenBrowser: onOpenBrowser)
                case .catalog:
                    SkillCatalogView(store: store, modelAccess: modelAccess, modelChanges: modelChanges)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showWebsiteData) {
            BrowserLibraryView(workspace: browserWorkspace, sitesOnly: true)
        }
        #endif
        .alert(copy.text(.skillDeleteTitle), isPresented: Binding(
            get: { deletionReview != nil }, set: { if !$0 { deletionReview = nil } }
        ), presenting: deletionReview) { review in
            Button(copy.text(.cancel), role: .cancel) { deletionReview = nil }
                .accessibilityIdentifier("skills.delete.cancel")
            Button(copy.text(.confirmSkillDelete), role: .destructive) {
                store.mutateSkills { skills in try review.apply(to: &skills) }
                deletionReview = nil
            }
            .accessibilityIdentifier("skills.delete.confirm")
        } message: { review in
            Text(copy.text(.skillDeleteMessage, skillTitle(review.skill.document)))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(LearningSegment.allCases) { item in
                    Button {
                        segment = item
                    } label: {
                        Text(item == .pending && pendingCount > 0
                             ? copy.text(.tabPendingCount, Int64(pendingCount)) : copy.text(item.textKey))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(segment == item ? palette.ink : palette.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(segment == item ? palette.selectedSegment : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(copy.text(segment == item ? .selected : .unselected))
                    .accessibilityAddTraits(segment == item ? .isSelected : [])
                    .accessibilityIdentifier("memory.segment.\(item.rawValue)")
                }
            }
            .padding(4)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: 16))
            if segment != .skills {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.ink3)
                        .accessibilityHidden(true)
                    TextField(copy.text(.search), text: $query)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { searchFocused = false }
                        .accessibilityIdentifier("memory.search")
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var contentList: some View {
        List {
            if !store.available {
                Section {
                    card {
                        Text(copy.text(.unavailable))
                            .accessibilityIdentifier("memory.unavailable")
                        Button(copy.text(.reload)) { store.reload() }
                            .accessibilityIdentifier("memory.reload")
                    }
                }
            }
            if let error = store.error {
                Section {
                    card {
                        Text(verbatim: error).foregroundStyle(palette.bad)
                            .accessibilityIdentifier("memory.error")
                        Button(copy.text(.dismissNotice)) { store.dismissNotice() }
                    }
                }
            }
            if let notice = store.notice {
                Section {
                    card {
                        Text(verbatim: notice).accessibilityIdentifier("memory.notice")
                        Button(copy.text(.dismissNotice)) { store.dismissNotice() }
                    }
                }
            }
            if store.available {
                switch segment {
                case .memories: memorySections
                case .skills:
                    skillsSections
                    builtInSkillsSection
                case .pending: pendingSections
                }
            }
            preferencesSection
            Section {
                card {
                    VStack(spacing: 0) {
                        NavigationLink {
                            UserProfileView(store: store)
                        } label: {
                            dataRow(copy.text(.profile), systemImage: "person.crop.circle")
                        }
                        .disabled(!store.available)
                        .accessibilityIdentifier("memory.profile.open")
                        cardDivider
                        Button { sheet = .websites } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .font(.body)
                                    .frame(width: 38, height: 38)
                                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 11))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(copy.text(.routeTitle))
                                    Text(copy.text(.websiteKnowledgeCount, Int64(store.websites.lessons.count)))
                                        .font(.caption).foregroundStyle(palette.ink3)
                                }
                                Spacer(minLength: 0)
                                Text(copy.text(.routeCount, Int64(store.routes.routes.count)))
                                    .foregroundStyle(palette.ink3)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.ink3)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                            .accessibilityLabel(copy.text(.websitesAndRoutes,
                                                          Int64(store.websites.lessons.count), Int64(store.routes.routes.count)))
                            .accessibilityIdentifier("memory.websites")
                        Text(copy.text(.routesHelp))
                            .font(.caption).foregroundStyle(palette.ink3)
                            .accessibilityIdentifier("memory.routesPending")
                        cardDivider
                        Button {
                            #if os(iOS)
                            showWebsiteData = true
                            #else
                            onOpenBrowser()
                            #endif
                        } label: {
                            dataRow(copy.text(.webLogins), systemImage: "globe")
                        }
                        .accessibilityIdentifier("memory.manageWebsites")
                        Text(copy.text(.webLoginsHelp))
                            .font(.caption).foregroundStyle(palette.ink3)
                            .accessibilityIdentifier("memory.browserPending")
                    }
                }
            } header: { sectionTitle(copy.text(.storedData)) }
            Section {
                card {
                    Button(role: .destructive) {
                        store.dismissNotice()
                        sheet = .clear
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 38, height: 38)
                                .background(palette.bad.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy.text(.clearAll)).font(.body.weight(.semibold))
                                Text(copy.text(.clearSubtitle))
                                    .font(.caption).foregroundStyle(palette.ink3)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(palette.bad)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                    .accessibilityIdentifier("memory.clear")
                    Text(copy.text(.clearDetails))
                        .font(.caption).foregroundStyle(palette.ink3)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .scrollDismissesKeyboard(.interactively)
        .id(segment)
    }

    @ViewBuilder private var memorySections: some View {
        let items = matchingMemories(status: .active)
        if items.isEmpty {
            Section {
                Text(copy.text(query.isEmpty ? .emptyMemory : .memoryNotFound))
                    .font(.body)
                    .foregroundStyle(palette.ink3)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("memory.empty")
            }
        }
        ForEach(memoryKinds, id: \.rawValue) { kind in
            let rows = items.filter { $0.kind == kind }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { item in card { memoryRow(item, pending: false) } }
                } header: { sectionTitle(copy.text(memoryKindKey(kind))) }
            }
        }
        Section {
            card {
                Button {
                    store.dismissNotice()
                    sheet = .memory(nil)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .frame(width: 38, height: 38)
                            .background(palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
                        Text(copy.text(.addMemory)).font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .accessibilityIdentifier("memory.add")
            }
        }
    }

    @ViewBuilder private var pendingSections: some View {
        let items = matchingMemories(status: .pending)
        if items.isEmpty && store.skills.pending.isEmpty {
            Section {
                Text(copy.text(query.isEmpty ? .emptyPending : .pendingNotFound))
                    .foregroundStyle(palette.ink3)
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("memory.pending.empty")
            }
        }
        if !items.isEmpty {
            Section {
                ForEach(items) { item in card { memoryRow(item, pending: true) } }
            } header: { sectionTitle(copy.text(.pendingProcedure)) }
        }
        if !store.skills.pending.isEmpty {
            Section {
                ForEach(store.skills.pending) { draft in card { draftRow(draft) } }
                Text(copy.text(.pendingSearchHint))
                    .font(.caption)
                    .foregroundStyle(palette.ink3)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: { sectionTitle(copy.text(.pendingSkills)) }
        }
    }

    private func memoryRow(_ item: MemoryItem, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.content)
                .accessibilityIdentifier("memory.item.\(item.id.uuidString)")
            Text(item.source.type == "manual" ? copy.text(.manualSource)
                 : copy.text(.conversationSource,
                             item.source.at.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
                                 .locale(Locale(identifier: copy.language.rawValue)))))
                .font(.caption).foregroundStyle(palette.ink3)
            if item.pinned {
                Text(copy.text(.pinned)).font(.caption)
                    .accessibilityIdentifier("memory.pinned.\(item.id.uuidString)")
            }
            if let previous = item.replaces {
                Text(copy.text(.originalContent, previous)).font(.caption).foregroundStyle(palette.ink3)
            }
            if !item.keywords.isEmpty {
                Text(item.keywords.joined(separator: " · "))
                    .font(.caption).foregroundStyle(palette.ink3)
            }
            HStack(spacing: 8) {
                if pending {
                    Button(copy.text(.accept)) { store.mutateMemory { try $0.approve(id: item.id) } }
                        .accessibilityIdentifier("memory.approve.\(item.id.uuidString)")
                        .memoryActionPill(palette, primary: true)
                    Button(copy.text(.reject), role: .destructive) { store.mutateMemory { _ = try $0.delete(id: item.id) } }
                        .accessibilityIdentifier("memory.reject.\(item.id.uuidString)")
                        .memoryActionPill(palette)
                } else {
                    Button(copy.text(.edit)) { store.dismissNotice(); sheet = .memory(item) }
                        .accessibilityIdentifier("memory.edit.\(item.id.uuidString)")
                        .memoryActionPill(palette)
                    Button(copy.text(item.pinned ? .unpin : .pin)) {
                        store.mutateMemory { try $0.setPinned(id: item.id, pinned: !item.pinned) }
                    }
                    .accessibilityIdentifier("memory.pin.\(item.id.uuidString)")
                    .memoryActionPill(palette)
                    Button(copy.text(.delete), role: .destructive) { store.mutateMemory { _ = try $0.delete(id: item.id) } }
                        .accessibilityIdentifier("memory.delete.\(item.id.uuidString)")
                        .memoryActionPill(palette)
                }
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var skillsSections: some View {
        Section {
            if store.skills.installed.isEmpty {
                card {
                    Text(copy.text(.emptySkills))
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .accessibilityIdentifier("skills.empty")
                }
            }
            ForEach(store.skills.installed.sorted { $0.name < $1.name }) { skill in
                card { installedSkillRow(skill) }
            }
            Text(copy.text(.skillsScope))
                .font(.caption).foregroundStyle(palette.ink3)
                .accessibilityIdentifier("skills.scope")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: { sectionTitle(copy.text(.mineSkills)) }
        Section {
            card {
                Button {
                    store.dismissNotice()
                    sheet = .importSkill
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        dataRow(copy.text(.importSkill), systemImage: "square.and.arrow.down")
                        Text(copy.text(.importHint))
                            .font(.caption).foregroundStyle(palette.ink3)
                    }
                }
                .accessibilityIdentifier("skills.import")
            }
            Text(copy.text(.importSafety))
                .font(.caption).foregroundStyle(palette.ink3)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: { sectionTitle(copy.text(.getSkills)) }
    }

    private var builtInSkillsSection: some View {
        Section {
            card {
                Button { sheet = .catalog } label: {
                    Text(copy.text(.catalog))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .accessibilityIdentifier("skills.catalog.open")
            }
            // Each destination needs its own List row. Multiple NavigationLinks
            // inside one row share its tap routing on iOS 18 and can open the
            // last destination even when the PDF link itself was tapped.
            card {
                NavigationLink { SkillExecutionView(learning: store, modelAccess: modelAccess, modelChanges: modelChanges) } label: {
                    Text(copy.text(.pdfRead))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .accessibilityIdentifier("skills.documents.execute")
            }
            card {
                NavigationLink {
                    SkillAgentView(store: store, modelAccess: modelAccess)
                } label: {
                    Text(copy.text(.agentWrite))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .disabled(!store.available)
                    .accessibilityIdentifier("skills.agent.open")
            }
            card {
                NavigationLink {
                    TranscriptView(learning: store, modelAccess: modelAccess, modelChanges: modelChanges)
                } label: {
                    Text(copy.text(.transcript))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .accessibilityIdentifier("skills.transcript.open")
            }
            Text(copy.text(.builtInHelp))
                .font(.caption).foregroundStyle(palette.ink3)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: { sectionTitle(copy.text(.builtInTools)) }
    }

    private func draftRow(_ draft: SkillDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: skillTitle(draft.document)).font(.headline)
                .accessibilityIdentifier("skills.draft.\(draft.name)")
            Text(verbatim: draft.document.description)
                .foregroundStyle(palette.ink2)
            Text(copy.text(draft.source == .imported ? .draftImported : .draftPending))
                .font(.caption).foregroundStyle(palette.ink3)
            if let previous = store.skills.installed.first(where: { $0.name == draft.replacesName }) {
                Text(copy.text(.draftUpdate))
                    .font(.caption)
                    .accessibilityIdentifier("skills.update.\(draft.name)")
                Text(copy.text(.changedLines))
                    .font(.caption).foregroundStyle(palette.ink3)
                ForEach(Array(changedLines(from: previous.markdown, to: draft.markdown)
                    .components(separatedBy: "\n").prefix(6).enumerated()), id: \.offset) { entry in
                    Text(verbatim: entry.element)
                        .font(.caption)
                        .foregroundStyle(entry.element.hasPrefix("+") ? palette.ok : palette.bad)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(DraftAction.allCases) { action in draftAction(action, for: draft) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        draftAction(.approve, for: draft)
                        draftAction(.edit, for: draft)
                    }
                    HStack(spacing: 8) {
                        draftAction(.fullText, for: draft)
                        draftAction(.reject, for: draft)
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private func draftAction(_ action: DraftAction, for draft: SkillDraft) -> some View {
        switch action {
        case .approve:
            Button(copy.text(.acceptTrial)) {
                store.mutateSkills { _ = try $0.approveDraft(id: draft.id, availableToolNames: toolNames) }
            }
            .accessibilityIdentifier("skills.approve.\(draft.name)")
            .memoryActionPill(palette, primary: true)
        case .edit:
            Button(copy.text(.editDraft)) { store.dismissNotice(); sheet = .editSkill(draft) }
                .accessibilityIdentifier("skills.edit.\(draft.name)")
                .memoryActionPill(palette)
        case .fullText:
            Button(copy.text(.fullText)) { sheet = .fullText(skillTitle(draft.document), draft.markdown) }
                .accessibilityIdentifier("skills.draftFullText.\(draft.name)")
                .memoryActionPill(palette)
        case .reject:
            Button(copy.text(.reject), role: .destructive) { store.mutateSkills { try $0.rejectDraft(id: draft.id) } }
                .accessibilityIdentifier("skills.reject.\(draft.name)")
                .memoryActionPill(palette)
        }
    }

    private func installedSkillRow(_ skill: PersonalSkill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: skillTitle(skill.document)).font(.headline)
                        .accessibilityIdentifier("skills.item.\(skill.name)")
                    Text(verbatim: skill.document.description)
                        .foregroundStyle(palette.ink2)
                    Text(copy.text(skill.status == .suspended ? .skillSuspended
                                   : skill.status == .trial ? .skillTrial : .skillEnabled))
                        .font(.caption).foregroundStyle(palette.ink3)
                        .accessibilityIdentifier("skills.state.\(skill.name)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(copy.text(.enableReference), isOn: Binding(get: { skill.isEnabled }, set: { enabled in
                    store.mutateSkills {
                        if enabled { try $0.resume(name: skill.name) }
                        else { try $0.suspend(name: skill.name) }
                    }
                }))
                .labelsHidden()
                .accessibilityLabel(copy.text(.enableReference))
                .accessibilityIdentifier("skills.enabled.\(skill.name)")
                .tint(palette.accent)
            }
            HStack(spacing: 8) {
                Button(copy.text(.viewFullText)) { sheet = .fullText(skillTitle(skill.document), skill.markdown) }
                    .accessibilityIdentifier("skills.fullText.\(skill.name)")
                    .memoryActionPill(palette)
                if let shared = try? store.skills.exportMarkdown(name: skill.name) {
                    ShareLink(item: shared, subject: Text(skillTitle(skill.document))) { Text(copy.text(.share)) }
                        .accessibilityIdentifier("skills.share.\(skill.name)")
                        .memoryActionPill(palette)
                }
                Button(copy.text(.delete), role: .destructive) {
                    store.dismissNotice()
                    deletionReview = SkillDeletionReview(skill: skill)
                }
                    .accessibilityIdentifier("skills.delete.\(skill.name)")
                    .memoryActionPill(palette)
            }
            if let previous = store.skills.revisions.reversed().first(where: { $0.name == skill.name && $0.canRestore }) {
                Button(copy.text(.restorePrevious)) {
                    store.mutateSkills {
                        _ = try $0.restoreRevision(id: previous.id, expectedCurrentHash: skill.fingerprint, availableToolNames: toolNames)
                    }
                }
                .accessibilityIdentifier("skills.rollback.\(skill.name)")
                .memoryActionPill(palette)
            }
        }
        .buttonStyle(.borderless)
    }

    private var preferencesSection: some View {
        Section {
            card {
                VStack(spacing: 0) {
                    Toggle(isOn: preference(\.useMemory)) {
                        preferenceLabel(copy.text(.useMemory), subtitle: copy.text(.useMemorySub))
                    }
                    .accessibilityIdentifier("memory.toggle.useMemory")
                    cardDivider
                    Toggle(isOn: preference(\.autoRemember)) {
                        preferenceLabel(copy.text(.autoRemember), subtitle: copy.text(.autoRememberSub))
                    }
                    .accessibilityIdentifier("memory.toggle.autoRemember")
                    cardDivider
                    Toggle(isOn: preference(\.learnSkills)) {
                        preferenceLabel(copy.text(.learnSkills), subtitle: copy.text(.learnSkillsSub))
                    }
                    .accessibilityIdentifier("memory.toggle.learnSkills")
                }
                .tint(palette.accent)
            }
            Text(copy.text(.preferenceScope))
                .font(.caption).foregroundStyle(palette.ink3)
                .accessibilityIdentifier("memory.preferenceScope")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Text(copy.text(.learningLimit))
                .font(.caption).foregroundStyle(palette.ink3)
                .accessibilityIdentifier("skills.learningLimit")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if store.isLearning { ProgressView(copy.text(.learningProgress)) }
        } header: { sectionTitle(copy.text(.switches)) }
        .disabled(!store.available)
    }

    private func preference(_ keyPath: WritableKeyPath<MemoryPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.memory.preferences[keyPath: keyPath] }, set: { value in
            store.updatePreferences { $0[keyPath: keyPath] = value }
        })
    }

    private func matchingMemories(status: MemoryStatus) -> [MemoryItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.memory.search(text, limit: 500, includePending: true)
            .filter { $0.status == status }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .buttonStyle(.borderless)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.edge, lineWidth: 1))
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink3)
            .textCase(nil)
            .padding(.leading, 4)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(palette.hair)
            .frame(height: 1)
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }

    private func dataRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 38, height: 38)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            Text(title).font(.body)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.ink3)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func preferenceLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(palette.ink)
            Text(subtitle).font(.caption).foregroundStyle(palette.ink3)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

private struct MemoryPalette {
    let background: Color
    let surface: Color
    let fill: Color
    let selectedSegment: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let hair: Color
    let edge: Color
    let accent: Color
    let ok: Color
    let bad: Color

    init(dark: Bool) {
        background = Color(hex: dark ? 0x0E0E10 : 0xF7F7F8)
        surface = Color(hex: dark ? 0x1A1A1D : 0xFFFFFF)
        fill = Color(hex: dark ? 0x222225 : 0xECECF0)
        selectedSegment = Color(hex: dark ? 0x29292D : 0xFFFFFF)
        ink = Color(hex: dark ? 0xF2F2F4 : 0x1C1C1E)
        ink2 = Color(hex: dark ? 0xA4A5AD : 0x5F6068)
        ink3 = Color(hex: dark ? 0x8F9099 : 0x73747D)
        hair = Color(hex: dark ? 0x303034 : 0xE8E8EC)
        edge = Color(hex: dark ? 0x2B2B30 : 0xE9E9ED)
        accent = Color(hex: dark ? 0x5D80FF : 0x0A7CFF)
        ok = Color(hex: dark ? 0x3CCF7A : 0x1F9D55)
        bad = Color(hex: dark ? 0xFF6961 : 0xE5483D)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private extension View {
    @ViewBuilder func memoryNavigationBackground(_ color: Color) -> some View {
        #if os(iOS)
        self.toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    func memoryActionPill(_ palette: MemoryPalette, primary: Bool = false) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primary ? Color.white : palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(primary ? palette.accent : palette.fill, in: Capsule())
    }
}

private enum DraftAction: CaseIterable, Identifiable {
    case approve, edit, fullText, reject
    var id: Self { self }
}

private enum LearningSegment: String, CaseIterable, Identifiable {
    case memories, skills, pending
    var id: String { rawValue }
    var textKey: MemoryDataKey {
        switch self { case .memories: return .tabMemory; case .skills: return .tabSkills; case .pending: return .tabPending }
    }
}

private enum LearningSheet: Identifiable {
    case memory(MemoryItem?), importSkill, editSkill(SkillDraft), fullText(String, String), clear, websites, catalog
    var id: String {
        switch self {
        case .memory(let item): return "memory-" + (item?.id.uuidString ?? "new")
        case .importSkill: return "import"
        case .editSkill(let draft): return "edit-" + draft.id.uuidString
        case .fullText: return "fulltext"
        case .clear: return "clear"
        case .websites: return "websites"
        case .catalog: return "catalog"
        }
    }
}

private let memoryKinds: [MemoryKind] = [.fact, .preference, .procedure]
private func memoryKindKey(_ kind: MemoryKind) -> MemoryDataKey {
    switch kind { case .fact: return .kindAbout; case .preference: return .kindPreferences; case .procedure: return .kindProcedures }
}
private func skillTitle(_ document: SkillDocument) -> String {
    document.frontMatter["display"]?.stringValue ?? document.name
}
private func changedLines(from old: String, to new: String) -> String {
    let before = old.components(separatedBy: .newlines).filter { !$0.isEmpty }
    let after = new.components(separatedBy: .newlines).filter { !$0.isEmpty }
    return (after.filter { !before.contains($0) }.map { "+ \($0)" }
        + before.filter { !after.contains($0) }.map { "− \($0)" }).joined(separator: "\n")
}

@MainActor
private struct MemoryEditor: View {
    @ObservedObject var store: LearningStore
    let item: MemoryItem?
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.appLocalizer) private var appLocalizer
    private var copy: MemoryDataCopy { MemoryDataCopy(language: appLocalizer.language) }
    #else
    private var copy: MemoryDataCopy { MemoryDataCopy(language: .traditionalChinese) }
    #endif
    @FocusState private var contentFocused: Bool
    @State private var kind: MemoryKind
    @State private var content: String
    @State private var keywords: String

    init(store: LearningStore, item: MemoryItem?) {
        self.store = store; self.item = item
        _kind = State(initialValue: item?.kind ?? .fact)
        _content = State(initialValue: item?.content ?? "")
        _keywords = State(initialValue: item?.keywords.joined(separator: " ") ?? "")
    }

    var body: some View {
        Form {
            if item == nil {
                Picker(copy.text(.memoryEditorKind), selection: $kind) {
                    ForEach(memoryKinds, id: \.rawValue) { value in
                        Text(copy.text(memoryKindKey(value))).tag(value)
                            .accessibilityIdentifier("memory.kind.\(value.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(copy.text(.memoryEditorContent)) {
                TextEditor(text: $content).frame(minHeight: 100)
                    .focused($contentFocused).autocorrectionDisabled()
                    .accessibilityIdentifier("memory.editor.content")
                TextField(copy.text(.memoryEditorKeywords), text: $keywords)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("memory.editor.keywords")
            }
            if kind == .procedure {
                Text(copy.text(.memoryEditorProcedureHelp))
            }
            if let error = store.error {
                Text(verbatim: error).foregroundStyle(.red)
                    .accessibilityIdentifier("memory.editor.error")
            }
        }
        .navigationTitle(copy.text(item == nil ? .memoryEditorAddTitle : .memoryEditorEditTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(copy.text(.cancel)) { dismiss() }.accessibilityIdentifier("memory.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(copy.text(.save)) { save() }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.available)
                    .accessibilityIdentifier("memory.editor.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button(copy.text(.clearContent)) { content = "" }
                    .accessibilityIdentifier("memory.editor.clear")
                Spacer()
                Button(copy.text(.doneTyping)) { contentFocused = false }
                    .accessibilityIdentifier("memory.editor.done")
            }
        }
        .interactiveDismissDisabled(!content.isEmpty)
    }

    private func save() {
        let words = keywords.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let succeeded = store.mutateMemory { memory in
            if let item { _ = try memory.edit(id: item.id, content: content, keywords: words) }
            else { _ = try memory.add(kind: kind, content: content, keywords: words) }
        }
        if succeeded { dismiss() }
    }
}

@MainActor
private struct SkillEditor: View {
    @ObservedObject var store: LearningStore
    let draft: SkillDraft?
    let toolNames: Set<String>
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.appLocalizer) private var appLocalizer
    private var copy: MemoryDataCopy { MemoryDataCopy(language: appLocalizer.language) }
    #else
    private var copy: MemoryDataCopy { MemoryDataCopy(language: .traditionalChinese) }
    #endif
    @FocusState private var editing: Bool
    @State private var markdown: String

    init(store: LearningStore, draft: SkillDraft?, toolNames: Set<String>, onSaved: @escaping () -> Void) {
        self.store = store; self.draft = draft; self.toolNames = toolNames; self.onSaved = onSaved
        _markdown = State(initialValue: draft?.markdown ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.text(draft == nil ? .skillEditorImportHelp : .skillEditorEditHelp))
                .font(.callout)
            TextEditor(text: $markdown)
                .focused($editing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("skills.editor.markdown")
            if let error = store.error {
                Text(verbatim: error).foregroundStyle(.red)
                    .accessibilityIdentifier("skills.editor.error")
            }
        }
        .padding()
        .navigationTitle(copy.text(draft == nil ? .skillEditorImportTitle : .skillEditorEditTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(copy.text(.cancel)) { dismiss() }.accessibilityIdentifier("skills.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(copy.text(draft == nil ? .importAction : .approveAction)) {
                    let succeeded = store.mutateSkills { skills in
                        if let draft { _ = try skills.approveDraft(id: draft.id, editedMarkdown: markdown, availableToolNames: toolNames) }
                        else { _ = try skills.importMarkdown(markdown, availableToolNames: toolNames) }
                    }
                    if succeeded { onSaved(); dismiss() }
                }
                .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.available)
                .accessibilityIdentifier("skills.editor.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button(copy.text(.clearFullText)) { markdown = "" }.accessibilityIdentifier("skills.editor.clear")
                Spacer()
                Button(copy.text(.doneTyping)) { editing = false }.accessibilityIdentifier("skills.editor.done")
            }
        }
        .interactiveDismissDisabled(!markdown.isEmpty)
    }
}

private struct SkillTextView: View {
    let title: String
    let markdown: String
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.appLocalizer) private var appLocalizer
    private var copy: MemoryDataCopy { MemoryDataCopy(language: appLocalizer.language) }
    #else
    private var copy: MemoryDataCopy { MemoryDataCopy(language: .traditionalChinese) }
    #endif

    var body: some View {
        ScrollView {
            Text(verbatim: markdown).font(.body.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .accessibilityIdentifier("skills.document")
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(copy.text(.done)) { dismiss() }.accessibilityIdentifier("skills.document.close")
            }
        }
    }
}

@MainActor
private struct LearningClearView: View {
    @ObservedObject var store: LearningStore
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.appLocalizer) private var appLocalizer
    private var copy: MemoryDataCopy { MemoryDataCopy(language: appLocalizer.language) }
    #else
    private var copy: MemoryDataCopy { MemoryDataCopy(language: .traditionalChinese) }
    #endif
    @State private var stage = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(copy.text(stage == 1 ? .clearStageOne : .clearStageTwo))
                    .font(.headline).accessibilityIdentifier("memory.clear.stage")
                Text(copy.text(.clearWarning))
                if stage == 1 {
                    Button(copy.text(.continueClear)) { stage = 2 }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("memory.clear.continue")
                } else {
                    Button(copy.text(.confirmClear), role: .destructive) {
                        if store.clearAll() { dismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("memory.clear.confirm")
                }
                if let error = store.error {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("memory.clear.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle(copy.text(.clearTitle)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(copy.text(.cancel)) { dismiss() }.accessibilityIdentifier("memory.clear.cancel")
            }
        }
    }
}
