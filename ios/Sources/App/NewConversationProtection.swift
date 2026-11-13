import Foundation
import AssistantPersistence

/// Captures the particular unsent attachment or unsaved result the user saw
/// when confirming a new conversation. A changed result needs a fresh review.
@MainActor struct NewConversationProtection: Equatable {
    let previewID: UUID?
    let unsavedAnswerID: UUID?
    let hasUnsavedAnswer: Bool
    let archiveNotice: String?

    static func current(in session: ChatSession) -> Self? {
        let unsaved = session.canRetryArchiveSave || session.archiveNotice != nil
        let previewID = session.replyPreview?.id
        guard previewID != nil || unsaved else { return nil }
        return Self(previewID: previewID,
                    unsavedAnswerID: unsaved ? session.entries.last?.id : nil,
                    hasUnsavedAnswer: unsaved,
                    archiveNotice: unsaved ? session.archiveNotice : nil)
    }

    var warningKeys: [AppText] {
        var keys: [AppText] = []
        if hasUnsavedAnswer { keys.append(.newConversationUnsavedWarning) }
        if previewID != nil { keys.append(.newConversationPreviewWarning) }
        keys.append(.newConversationDraftRetained)
        return keys
    }
}

@MainActor enum NewConversationAction {
    /// A nil approval starts only when there is nothing protected to discard.
    /// A non-nil approval must still describe the exact current attachment/result.
    static func canStart(in session: ChatSession, approved: NewConversationProtection?) -> Bool {
        !session.isSubmitting
            && session.pendingProfileReview == nil && session.pendingMemoryReview == nil
            && session.pendingQuote == nil
            && NewConversationProtection.current(in: session) == approved
    }

    @discardableResult static func start(in session: ChatSession,
                                         approved: NewConversationProtection?) -> Bool {
        guard canStart(in: session, approved: approved) else { return false }
        session.newConversation()
        return true
    }
}

/// Deleting the currently displayed archived row also starts a new conversation.
/// Capture that consequence with the same attachment/result review as the toolbar.
@MainActor struct ArchiveDeletionApproval: Equatable {
    let record: ArchivedConversation
    let wasCurrent: Bool
    let newConversation: NewConversationProtection?

    static func capture(id: UUID, in session: ChatSession) -> Self? {
        guard session.archive?.available == true,
              let record = session.archive?.state.conversations.first(where: { $0.id == id }) else { return nil }
        let wasCurrent = session.isCurrentConversation(id: id)
        return Self(record: record, wasCurrent: wasCurrent,
                    newConversation: wasCurrent ? NewConversationProtection.current(in: session) : nil)
    }
}

@MainActor enum ArchiveDeletionAction {
    @discardableResult static func delete(approved: ArchiveDeletionApproval, in session: ChatSession) -> Bool {
        guard ArchiveDeletionApproval.capture(id: approved.record.id, in: session) == approved else { return false }
        if approved.wasCurrent,
           !NewConversationAction.canStart(in: session, approved: approved.newConversation) { return false }
        return session.deleteConversation(id: approved.record.id)
    }
}
