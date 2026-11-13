import AssistantMemory
import SwiftUI

@MainActor
struct UserProfileView: View {
    @ObservedObject var store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ProfileEditorDestination?
    @State private var historyExpanded = false
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        List {
            Section {
                Text(localizer.text(.profileScope))
                    .accessibilityIdentifier("profile.scope")
                Text(localizer.text(.profileCount(count: store.profile.snapshot().entries.count)))
                    .accessibilityIdentifier("profile.count")
                if !store.memory.preferences.useMemory {
                    Text(localizer.text(.profileMemoryOff))
                        .accessibilityIdentifier("profile.disabled")
                }
            }
            if !store.available {
                Section {
                    Text(localizer.text(.profileUnavailable))
                        .accessibilityIdentifier("profile.unavailable")
                    Button(localizer.text(.commonReload)) { store.reload() }
                        .accessibilityIdentifier("profile.reload")
                }
            }
            if let error = store.error {
                Text(verbatim: localizer.stored(error)).foregroundStyle(.red)
                    .accessibilityIdentifier("profile.error")
            }
            if store.available {
                Section(localizer.text(.profileActiveSection)) {
                    if store.profile.snapshot().entries.isEmpty {
                        Text(localizer.text(.profileEmpty))
                            .accessibilityIdentifier("profile.empty")
                    }
                    ForEach(store.profile.snapshot().entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: entry.text)
                                .accessibilityIdentifier("profile.item.\(entry.id.uuidString)")
                            HStack(spacing: 24) {
                                Button(localizer.text(.commonEdit)) { store.dismissNotice(); editor = .init(entry: entry) }
                                    .accessibilityIdentifier("profile.edit.\(entry.id.uuidString)")
                                Button(localizer.text(.commonDelete), role: .destructive) {
                                    _ = store.deleteProfileReference(segment: entry.text)
                                }
                                .accessibilityIdentifier("profile.delete.\(entry.id.uuidString)")
                            }
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                        }
                    }
                    Button(localizer.text(.profileAdd)) { store.dismissNotice(); editor = .init(entry: nil) }
                        .accessibilityIdentifier("profile.add")
                }
                if let notice = store.notice {
                    Text(verbatim: localizer.stored(notice)).accessibilityIdentifier("profile.notice")
                }
                let history = store.profile.entries.filter { $0.status == .superseded }
                if !history.isEmpty {
                    Section {
                        // A DisclosureGroup identifier propagates to its rows
                        // on iOS 18/26, replacing their individual AX identifiers.
                        // Keep the disclosure control and history rows siblings.
                        Button {
                            historyExpanded.toggle()
                        } label: {
                            HStack {
                                Text(localizer.text(.profileHistoryCount(count: history.count)))
                                Spacer()
                                Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                            }
                        }
                        .accessibilityIdentifier("profile.history")
                        .accessibilityValue(localizer.text(historyExpanded ? .commonExpanded : .commonCollapsed))
                        if historyExpanded {
                            ForEach(history.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: entry.text)
                                        .accessibilityIdentifier("profile.history.item.\(entry.id.uuidString)")
                                    Text(localizer.text(.profileHistoryItem(value: entry.supersededAt!.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                         locale: Locale(identifier: localizer.language.rawValue))))))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(localizer.text(.profileHistoryNote))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(localizer.text(.profileTitle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profile.list")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localizer.text(.commonBack)) { dismiss() }.accessibilityIdentifier("profile.close")
            }
        }
        .sheet(item: $editor) { destination in
            NavigationStack { UserProfileEditor(store: store, entry: destination.entry) }
        }
    }
}

private struct ProfileEditorDestination: Identifiable {
    let id = UUID()
    let entry: UserProfileEntry?
}

@MainActor
private struct UserProfileEditor: View {
    @ObservedObject var store: LearningStore
    let entry: UserProfileEntry?
    @State private var baseRevision: UUID
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer

    init(store: LearningStore, entry: UserProfileEntry?) {
        self.store = store; self.entry = entry
        _baseRevision = State(initialValue: store.profile.revision)
        _text = State(initialValue: entry?.text ?? "")
    }

    var body: some View {
        Form {
            Section(localizer.text(.profileEditorSection)) {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(localizer.text(.profileEditorLabel))
                    .accessibilityIdentifier("profile.editor.text")
                Text(localizer.text(.profileEditorCount(count: text.utf16.count)))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile.editor.count")
                Text(localizer.text(.profileEditorRule))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = store.error {
                Text(verbatim: localizer.stored(error)).foregroundStyle(.red)
                    .accessibilityIdentifier("profile.editor.error")
            }
        }
        .navigationTitle(localizer.text(entry == nil ? .profileEditorAddTitle : .profileEditorEditTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localizer.text(.commonCancel)) { dismiss() }.accessibilityIdentifier("profile.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.commonSave)) {
                    let saved: Bool
                    if let entry {
                        saved = store.replaceProfileReference(segment: entry.text, replacement: text,
                                                              expectedRevision: baseRevision)
                    } else {
                        saved = store.mutateProfile { state in
                            guard state.revision == baseRevision else { throw MemoryError.stalePlan }
                            try state.add(text: text)
                        }
                    }
                    if saved { dismiss() }
                }
                .disabled(!store.available)
                .accessibilityIdentifier("profile.editor.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button(localizer.text(.commonClearText)) { text = "" }.accessibilityIdentifier("profile.editor.clear")
                Spacer()
                Button(localizer.text(.commonHideKeyboard)) { focused = false }.accessibilityIdentifier("profile.editor.done")
            }
        }
    }
}
