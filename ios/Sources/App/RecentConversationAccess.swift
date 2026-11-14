import AssistantPersistence
import Foundation

/// A drawer shortcut resumes a saved conversation, whatever model it used.
enum RecentConversationBlock: Equatable {
    case unavailable
    case activeTask
    case unsentDraft
    case unsavedReply

    var message: AppText {
        switch self {
        case .unavailable: return .drawerRecentUnavailable
        case .activeTask: return .drawerRecentActiveTask
        case .unsentDraft: return .drawerRecentUnsentDraft
        case .unsavedReply: return .drawerRecentUnsavedReply
        }
    }
}

@MainActor enum RecentConversationAccess {
    static func isCurrent(_ record: ArchivedConversation, in session: ChatSession) -> Bool {
        session.entries.first?.id == record.turns.first?.userID
    }

    static func block(_ record: ArchivedConversation, in session: ChatSession) -> RecentConversationBlock? {
        guard session.archive?.available == true,
              session.archive?.state.conversations.contains(where: { $0.id == record.id }) == true
        else { return .unavailable }
        guard !session.isSubmitting else { return .activeTask }
        // Waiting attachments, like a draft, are never discarded by opening another chat.
        guard session.draft.isEmpty, session.pendingAttachments.isEmpty else { return .unsentDraft }
        guard session.archiveNotice == nil, session.replyPreview == nil else { return .unsavedReply }
        // Like the Play build a conversation opens whatever model it was saved
        // with and continues with the current main model.
        return nil
    }

    @discardableResult static func open(_ record: ArchivedConversation, in session: ChatSession) -> Bool {
        guard block(record, in: session) == nil else { return false }
        // ChatSession rechecks the currently stored row and model identity.
        return session.openConversation(id: record.id)
    }
}
