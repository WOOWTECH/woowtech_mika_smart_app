import AssistantPersistence
import Foundation

/// A drawer shortcut may resume only a saved, same-destination conversation.
/// The archive detail stays readable for records that cannot be resumed.
enum RecentConversationBlock: Equatable {
    case unavailable
    case activeTask
    case unsentDraft
    case unsavedReply
    case differentDestination

    var message: AppText {
        switch self {
        case .unavailable: return .drawerRecentUnavailable
        case .activeTask: return .drawerRecentActiveTask
        case .unsentDraft: return .drawerRecentUnsentDraft
        case .unsavedReply: return .drawerRecentUnsavedReply
        case .differentDestination: return .drawerRecentDifferentDestination
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
        guard session.canOpenConversation(record) else { return .differentDestination }
        return nil
    }

    @discardableResult static func open(_ record: ArchivedConversation, in session: ChatSession) -> Bool {
        guard block(record, in: session) == nil else { return false }
        // ChatSession rechecks the currently stored row and model identity.
        return session.openConversation(id: record.id)
    }
}
