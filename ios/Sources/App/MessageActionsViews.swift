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
    @State private var failed = false

    var body: some View {
        if let snapshot = MessageActions.capture(entry: entry, in: session) {
            Menu {
                MessageActionItems(snapshot: snapshot, session: session, localizer: localizer, failed: $failed)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(localizer.text(.messageActions))
            .accessibilityIdentifier("chat.message.actions.\(entry.id.uuidString)")
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
    @Binding var failed: Bool

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
        if snapshot.canBranch(in: session) {
            Button {
                if !snapshot.branch(in: session, suffix: localizer.text(.messageBranchSuffix)) { failed = true }
            } label: { Label(localizer.text(.messageBranch), systemImage: "arrow.triangle.branch") }
            .accessibilityIdentifier("chat.message.branch.\(snapshot.entry.id.uuidString)")
        }
    }
}

private struct MessageActionsContextMenu: ViewModifier {
    let entry: ChatEntry
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    @State private var failed = false

    func body(content: Content) -> some View {
        let snapshot = MessageActions.capture(entry: entry, in: session)
        content.contextMenu {
            if let snapshot {
                MessageActionItems(snapshot: snapshot, session: session, localizer: localizer, failed: $failed)
            }
        }
        .alert(localizer.text(.messageActionFailed), isPresented: $failed) {
            Button(localizer.text(.archiveClose), role: .cancel) { }
        }
    }
}

extension View {
    func messageActionsContextMenu(entry: ChatEntry, session: ChatSession, localizer: AppLocalizer) -> some View {
        modifier(MessageActionsContextMenu(entry: entry, session: session, localizer: localizer))
    }
}

/// A preview of the same pendingQuote ChatSession will send. Removing it must
/// call ChatSession.clearQuote(), leaving the typed draft untouched.
struct MessageQuoteChip: View {
    let quote: ConversationQuote.Quote
    let localizer: AppLocalizer
    let disabled: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.text(quote.source == .assistant ? .messageQuoteAssistant : .messageQuoteUser))
                    .font(.caption.weight(.semibold))
                Text(ConversationQuote.clip(quote.text)).font(.subheadline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: remove) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .disabled(disabled)
            .accessibilityLabel(localizer.text(.messageQuoteRemove))
            .accessibilityIdentifier("chat.quote.remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("chat.quote.preview")
    }
}
