import AssistantPersistence
import SwiftUI

/// Rows for the existing Mika drawer. Only the encrypted archive supplies data;
/// there is no separate drawer store or synthetic unfinished-conversation row.
@MainActor struct MikaRecentConversationsSection: View {
    @ObservedObject var store: ConversationArchiveStore
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let ink: Color
    let secondaryInk: Color
    let hair: Color
    let onOpen: (ArchivedConversation) -> Void
    @State private var renaming: ArchivedConversation?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.text(.drawerRecentTitle))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(secondaryInk)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("drawer.recent.title")
            Text(localizer.text(.drawerRecentBoundary))
                .font(.caption2).foregroundStyle(secondaryInk)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("drawer.recent.boundary")

            if !store.available {
                Text(localizer.text(.drawerRecentUnavailable))
                    .font(.caption).foregroundStyle(secondaryInk)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("drawer.recent.error")
                Button(localizer.text(.drawerRecentReload)) { store.reload() }
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("drawer.recent.reload")
            } else if store.conversations.isEmpty {
                Text(localizer.text(.drawerRecentEmpty))
                    .font(.caption).foregroundStyle(secondaryInk)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("drawer.recent.empty")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.conversations) { record in
                        row(record)
                        Rectangle().fill(hair).frame(height: 0.5)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(.top, 18).padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.recent.section")
        .sheet(item: $renaming) { record in
            RenameArchivedConversationSheet(record: record, localizer: localizer) { title in
                try store.rename(id: record.id, expectedTitle: record.customTitle, to: title)
            }
        }
    }

    private func row(_ record: ArchivedConversation) -> some View {
        let current = RecentConversationAccess.isCurrent(record, in: session)
        let block = RecentConversationAccess.block(record, in: session)
        return HStack(spacing: 0) {
            Button { onOpen(record) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: record.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if current {
                            Text(localizer.text(.drawerRecentCurrent))
                                .font(.caption2).foregroundStyle(secondaryInk)
                        }
                    }
                    Text(verbatim: localizer.text(.drawerRecentTurns(count: record.turns.count))
                         + " · " + formattedDate(record.updatedAt))
                        .font(.caption).foregroundStyle(secondaryInk)
                    if !current, let block {
                        Text(localizer.text(block.message))
                            .font(.caption).foregroundStyle(secondaryInk)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!current && block != nil)
            .accessibilityIdentifier("drawer.recent.row." + record.id.uuidString)
            .accessibilityLabel(record.title)
            .accessibilityValue(current ? localizer.text(.drawerRecentCurrent)
                                : block.map { localizer.text($0.message) } ?? "")
        }
        // Renaming is independent of whether switching away is currently safe.
        .contextMenu {
            Button(localizer.text(.drawerRecentRename)) { renaming = record }
                .accessibilityIdentifier("drawer.recent.rename." + record.id.uuidString)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localizer.language.rawValue)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor private struct RenameArchivedConversationSheet: View {
    let record: ArchivedConversation
    let localizer: AppLocalizer
    let save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var saveFailed = false
    @FocusState private var titleFocused: Bool

    init(record: ArchivedConversation, localizer: AppLocalizer, save: @escaping (String) throws -> Void) {
        self.record = record; self.localizer = localizer; self.save = save
        _draft = State(initialValue: record.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(localizer.text(.drawerRecentRenameTitle), text: $draft)
                    .focused($titleFocused)
                    .accessibilityIdentifier("drawer.rename.field")
                    .onChange(of: draft) { _ in saveFailed = false }
                if !draft.isEmpty && ConversationArchive.normalizedTitle(draft) == nil {
                    Text(localizer.text(.drawerRecentRenameInvalid))
                        .foregroundStyle(.red).accessibilityIdentifier("drawer.rename.invalid")
                }
                if saveFailed {
                    Text(localizer.text(.drawerRecentRenameFailed))
                        .foregroundStyle(.red).accessibilityIdentifier("drawer.rename.error")
                }
            }
            .navigationTitle(localizer.text(.drawerRecentRenameTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.commonCancel)) { dismiss() }
                        .accessibilityIdentifier("drawer.rename.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonSave)) {
                        do { try save(draft); dismiss() }
                        catch { saveFailed = true }
                    }
                    .disabled(ConversationArchive.normalizedTitle(draft) == nil)
                    .accessibilityIdentifier("drawer.rename.save")
                }
            }
        }
        .onAppear { titleFocused = true }
    }
}
