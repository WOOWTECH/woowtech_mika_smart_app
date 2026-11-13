import AssistantBrowser
import SwiftUI

@MainActor
struct WebsiteDataView: View {
    @ObservedObject var store: LearningStore
    @ObservedObject var browser: BrowserSession
    let modelAccess: () throws -> ModelAccess
    let onOpenBrowser: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var edit: WebsiteLesson?
    @State private var replay: WebRoute?
    @State private var query = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        List {
            if let error = store.error { Text(localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("website.error") }
            Section(localizer.text(.websiteSaveSection)) {
                if let page = browser.current {
                    Text(page.url.host ?? "").font(.caption)
                    TextField(localizer.text(.websiteNotePlaceholder), text: $note)
                        .focused($noteFocused).submitLabel(.done).onSubmit { noteFocused = false }
                        .accessibilityIdentifier("website.note")
                    Button(localizer.text(.websiteSaveNote)) { saveNote(page) }
                        .disabled(note.isEmpty || !store.available).accessibilityIdentifier("website.save")
                    Text(localizer.text(.websiteSaveHelp))
                        .font(.caption)
                } else { Text(localizer.text(.websiteOpenFirst)) }
            }
            Section(localizer.text(.websiteNotesSection)) {
                TextField(localizer.text(.websiteSearch), text: $query).accessibilityIdentifier("website.search")
                let lessons = (try? store.websites.search(query)) ?? []
                if lessons.isEmpty { Text(localizer.text(.websiteEmpty)).accessibilityIdentifier("website.empty") }
                ForEach(lessons) { lesson in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.text).accessibilityIdentifier("website.lesson.\(lesson.id)")
                        Text(lesson.origin.url.host ?? "").font(.caption)
                        Text(localizer.text(.websiteSource(value: lesson.evidence.quote))).font(.caption).foregroundStyle(.secondary)
                        Text(localizer.text(lesson.status == .approved ? .websiteApproved : .websitePending))
                        HStack {
                            if lesson.status == .pending {
                                Button(localizer.text(.websiteApprove)) { store.mutateWeb { web, _ in try web.approve(id: lesson.id) } }
                                    .accessibilityIdentifier("website.approve.\(lesson.id)")
                            }
                            Button(localizer.text(.commonEdit)) { edit = lesson }.accessibilityIdentifier("website.edit.\(lesson.id)")
                            Button(localizer.text(.commonDelete), role: .destructive) { store.mutateWeb { web, _ in try web.delete(id: lesson.id) } }
                                .accessibilityIdentifier("website.delete.\(lesson.id)")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section(localizer.text(.websiteRoutesSection)) {
                if store.routes.routes.isEmpty { Text(localizer.text(.websiteRoutesEmpty)).accessibilityIdentifier("website.routes.empty") }
                ForEach(store.routes.routes) { route in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(route.originalGoal).accessibilityIdentifier("website.route.\(route.id)")
                        Text(localizer.text(.websiteRouteSummary(count: route.steps.count, host: route.origin.url.host ?? "")))
                        if route.disabled { Text(localizer.text(.websiteRouteDisabled)) }
                        HStack {
                            Button(localizer.text(.websiteReplay)) { replay = route }.disabled(route.disabled || browser.isRunning)
                                .accessibilityIdentifier("website.replay.\(route.id)")
                            Button(localizer.text(.commonDelete), role: .destructive) { store.mutateWeb { _, routes in try routes.delete(id: route.id) } }
                                .accessibilityIdentifier("website.route.delete.\(route.id)")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section(localizer.text(.websiteRevisionsSection)) {
                ForEach(store.websites.revisions.reversed()) { revision in
                    let hash = store.websites.contentHash
                    VStack(alignment: .leading) {
                        Text(revision.lesson.text).font(.caption)
                        Button(localizer.text(.websiteRestore)) { store.mutateWeb { web, _ in
                            _ = try web.restore(revisionID: revision.id, expectedCurrentHash: hash)
                        }}.accessibilityIdentifier("website.restore.\(revision.id)")
                    }
                }
            }
        }
        .navigationTitle(localizer.text(.websiteTitle))
        .accessibilityIdentifier("website.manager")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localizer.text(.commonDone)) { dismiss() }.accessibilityIdentifier("website.close") } }
        .sheet(item: $edit) { item in
            NavigationStack { WebsiteLessonEditor(store: store, item: item) }
        }
        .alert(localizer.text(.websiteReplayTitle), isPresented: Binding(get: { replay != nil }, set: { if !$0 { replay = nil } })) {
            Button(localizer.text(.commonCancel), role: .cancel) { replay = nil }
            Button(localizer.text(.websiteReplayConfirm)) {
                guard let route = replay else { return }
                browser.replay(route: route, store: store, modelAccess: modelAccess)
                replay = nil; dismiss(); onOpenBrowser()
            }
        } message: {
            Text(localizer.text(.websiteReplayMessage(host: replay?.origin.url.host ?? "", count: replay?.steps.count ?? 0)))
        }
    }

    private func saveNote(_ page: WebObservation) {
        let quote = String(page.text.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = PageSnapshot(url: page.url, title: page.title, visibleText: page.text, capturedAt: page.capturedAt)
        if store.mutateWeb({ web, _ in
            let evidence = try WebsiteLessonEvidence(snapshot: snapshot, quote: quote)
            _ = try web.addManual(text: note, evidence: evidence)
        }) { note = "" }
    }
}

@MainActor
private struct WebsiteLessonEditor: View {
    @ObservedObject var store: LearningStore
    let item: WebsiteLesson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer
    @State private var text: String
    init(store: LearningStore, item: WebsiteLesson) { self.store = store; self.item = item; _text = State(initialValue: item.text) }
    var body: some View {
        Form {
            TextEditor(text: $text).frame(minHeight: 180).accessibilityIdentifier("website.editor.text")
            Text(localizer.text(.websiteEditorSource(value: item.evidence.quote))).font(.caption)
            if let error = store.error { Text(localizer.stored(error)).foregroundStyle(.red) }
        }
        .navigationTitle(localizer.text(.websiteEditorTitle))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(localizer.text(.commonCancel)) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.commonSave)) {
                    if store.mutateWeb({ web, _ in try web.edit(id: item.id, text: text, evidence: item.evidence) }) { dismiss() }
                }.accessibilityIdentifier("website.editor.save")
            }
        }
    }
}
