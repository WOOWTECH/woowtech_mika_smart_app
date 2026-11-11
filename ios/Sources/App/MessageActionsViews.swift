import SwiftUI
import UIKit
import AssistantPersistence

/// Place alongside a selectable message. The separate 44-point menu avoids
/// taking over the long press used by native text selection; the same actions
/// can also be attached to a bubble with messageActionsContextMenu.
struct MessageActionsControl: View {
    let entry: ChatEntry
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let accessibilityID: String?
    let branchAllowed: () -> Bool
    @State private var failed = false
    @State private var pendingBranch: MessageActions?

    init(entry: ChatEntry, session: ChatSession, localizer: AppLocalizer,
         accessibilityID: String? = nil, branchAllowed: @escaping () -> Bool = { true }) {
        self.entry = entry; self.session = session; self.localizer = localizer
        self.accessibilityID = accessibilityID; self.branchAllowed = branchAllowed
    }

    var body: some View {
        if let snapshot = MessageActions.capture(entry: entry, in: session) {
            Menu {
                MessageActionItems(snapshot: snapshot, session: session, localizer: localizer, branchAllowed: branchAllowed, failed: $failed,
                                   pendingBranch: $pendingBranch)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(localizer.text(.messageActions))
            .accessibilityIdentifier(accessibilityID ?? "chat.message.actions.\(entry.id.uuidString)")
            .modifier(BranchUpgradeAlert(pending: $pendingBranch, failed: $failed, session: session,
                                         localizer: localizer, branchAllowed: branchAllowed))
            .alert(localizer.text(.messageActionFailed), isPresented: $failed) {
                Button(localizer.text(.archiveClose), role: .cancel) { }
            }
        }
    }
}

private struct MessageActionItems: View {
    let snapshot: MessageActions
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let branchAllowed: () -> Bool
    @Binding var failed: Bool
    @Binding var pendingBranch: MessageActions?

    var body: some View {
        Button {
            if !snapshot.copy(in: session, assistantPlainText: { ChatReplyMarkdown.parse($0).visibleText },
                              write: { UIPasteboard.general.string = $0 }) { failed = true }
        } label: { Label(localizer.text(.messageCopy), systemImage: "doc.on.doc") }
        .accessibilityIdentifier("chat.message.copy.\(snapshot.entry.id.uuidString)")

        if snapshot.canQuote {
            Button {
                if !snapshot.quote(in: session) { failed = true }
            } label: { Label(localizer.text(.messageQuote), systemImage: "text.quote") }
            .accessibilityIdentifier("chat.message.quote.\(snapshot.entry.id.uuidString)")
        }
        if branchAllowed() && snapshot.canBranch(in: session) {
            Button {
                guard branchAllowed(), snapshot.canBranch(in: session) else { failed = true; return }
                session.archive?.reload()
                guard session.archive?.available == true else { failed = true; return }
                if (session.archive?.state.formatVersion ?? 0) < 5 { pendingBranch = snapshot }
                else if !snapshot.branch(in: session, suffix: localizer.text(.messageBranchSuffix)) { failed = true }
            } label: { Label(localizer.text(.messageBranch), systemImage: "arrow.triangle.branch") }
            .accessibilityIdentifier("chat.message.branch.\(snapshot.entry.id.uuidString)")
        }
    }
}

private struct MessageActionsContextMenu: ViewModifier {
    let entry: ChatEntry
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let branchAllowed: () -> Bool
    @State private var failed = false
    @State private var pendingBranch: MessageActions?

    func body(content: Content) -> some View {
        let snapshot = MessageActions.capture(entry: entry, in: session)
        content.contextMenu {
            if let snapshot {
                MessageActionItems(snapshot: snapshot, session: session, localizer: localizer, branchAllowed: branchAllowed, failed: $failed,
                                   pendingBranch: $pendingBranch)
            }
        }
        .modifier(BranchUpgradeAlert(pending: $pendingBranch, failed: $failed, session: session,
                                     localizer: localizer, branchAllowed: branchAllowed))
        .alert(localizer.text(.messageActionFailed), isPresented: $failed) {
            Button(localizer.text(.archiveClose), role: .cancel) { }
        }
    }
}

private struct BranchUpgradeAlert: ViewModifier {
    @Binding var pending: MessageActions?
    @Binding var failed: Bool
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let branchAllowed: () -> Bool

    func body(content: Content) -> some View {
        content.alert(localizer.text(.archiveUpgradeTitle), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { snapshot in
            Button(localizer.text(.archiveUpgradeContinue)) {
                pending = nil
                if !branchAllowed() || !snapshot.branch(in: session, suffix: localizer.text(.messageBranchSuffix)) {
                    failed = true
                }
            }.accessibilityIdentifier("chat.branch.upgrade.confirm")
            Button(localizer.text(.commonCancel), role: .cancel) { pending = nil }
                .accessibilityIdentifier("chat.branch.upgrade.cancel")
        } message: { _ in Text(localizer.text(.archiveUpgradeMessage)) }
    }
}

extension View {
    func messageActionsContextMenu(entry: ChatEntry, session: ChatSession, localizer: AppLocalizer,
                                   branchAllowed: @escaping () -> Bool = { true }) -> some View {
        modifier(MessageActionsContextMenu(entry: entry, session: session, localizer: localizer, branchAllowed: branchAllowed))
    }
}

/// A preview of the same pendingQuote ChatSession will send. Removing it must
/// call ChatSession.clearQuote(), leaving the typed draft untouched.
struct MessageQuoteChip: View {
    let quote: ConversationQuote.Quote
    let localizer: AppLocalizer
    let disabled: Bool
    let remove: () -> Void
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.text(quote.source == .assistant ? .messageQuoteAssistant : .messageQuoteUser))
                    .font(.caption.weight(.semibold))
                if expanded {
                    ScrollView { Text(verbatim: quote.text).font(.subheadline).textSelection(.enabled)
                        .accessibilityIdentifier("chat.quote.preview.text")
                        .frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 180)
                } else {
                    Text(verbatim: quote.text).font(.subheadline).lineLimit(2).textSelection(.enabled)
                        .accessibilityIdentifier("chat.quote.preview.text")
                }
                Button(localizer.text(expanded ? .messageQuoteCollapse : .messageQuoteExpand)) { expanded.toggle() }
                    .accessibilityIdentifier("chat.quote.expand")
                if ConversationQuote.clip(quote.text) != quote.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(localizer.text(.messageQuoteTruncated)).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .disabled(disabled)
            .accessibilityLabel(localizer.text(.messageQuoteRemove))
            .accessibilityIdentifier("chat.quote.remove")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("chat.quote.preview")
    }
}

/// Read-only quote shown above a previously sent user's own words. The host
/// keeps the words in its existing selectable message bubble and keeps the
/// original serialized ChatEntry unchanged for history and archive checks.
struct MessageSentQuote: View {
    let quote: ConversationQuote.Quote
    let localizer: AppLocalizer
    var identifier = "chat.quote.sent"
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.text(quote.source == .assistant ? .messageQuoteAssistant : .messageQuoteUser))
                    .font(.caption.weight(.semibold))
                if expanded {
                    ScrollView { Text(verbatim: quote.text).font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier(identifier + ".text")
                        .frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 180)
                } else {
                    Text(verbatim: quote.text).font(.caption).lineLimit(2).textSelection(.enabled)
                        .accessibilityIdentifier(identifier + ".text")
                }
                Button(localizer.text(expanded ? .messageQuoteCollapse : .messageQuoteExpand)) { expanded.toggle() }
                    .accessibilityIdentifier(identifier + ".expand")
                if ConversationQuote.clip(quote.text) != quote.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(localizer.text(.messageQuoteTruncated)).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier(identifier)
    }
}
