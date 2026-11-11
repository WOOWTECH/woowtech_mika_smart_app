import Foundation

/// Captures the particular unsent attachment or unsaved result the user saw
/// when confirming a new conversation. A changed result needs a fresh review.
@MainActor struct NewConversationProtection: Equatable {
    let pdfID: UUID?
    let previewID: UUID?
    let unsavedAnswerID: UUID?
    let hasUnsavedAnswer: Bool
    let archiveNotice: String?

    static func current(in session: ChatSession) -> Self? {
        let unsaved = session.canRetryArchiveSave || session.archiveNotice != nil
        let pdfID = session.pdfAttachment?.id
        let previewID = session.replyPreview?.id
        guard pdfID != nil || previewID != nil || unsaved else { return nil }
        return Self(pdfID: pdfID, previewID: previewID,
                    unsavedAnswerID: unsaved ? session.entries.last?.id : nil,
                    hasUnsavedAnswer: unsaved,
                    archiveNotice: unsaved ? session.archiveNotice : nil)
    }

    var warningKeys: [AppText] {
        var keys: [AppText] = []
        if pdfID != nil { keys.append(.newConversationPDFWarning) }
        if hasUnsavedAnswer { keys.append(.newConversationUnsavedWarning) }
        if previewID != nil { keys.append(.newConversationPreviewWarning) }
        keys.append(.newConversationDraftRetained)
        return keys
    }
}

@MainActor enum NewConversationAction {
    /// A nil approval starts only when there is nothing protected to discard.
    /// A non-nil approval must still describe the exact current attachment/result.
    @discardableResult static func start(in session: ChatSession,
                                         approved: NewConversationProtection?) -> Bool {
        guard !session.isSubmitting,
              session.pendingMCPApproval == nil,
              session.pendingProfileReview == nil,
              session.pendingMemoryReview == nil,
              NewConversationProtection.current(in: session) == approved
        else { return false }
        session.newConversation()
        return true
    }
}
