import AssistantSkills

extension AppText {
    static let transcriptErrors: [TranscriptError] = [
        .invalidSelection, .unsupportedType, .tooLarge, .invalidEncoding, .emptySource, .approvalRequired,
        .cancelled, .readTimedOut, .invalidCommand, .invalidRange, .incompleteCoverage, .invalidEvidence,
        .budgetExceeded, .modelFailed, .timedOut, .contextChanged,
    ]

    static func transcriptError(_ error: TranscriptError) -> AppText {
        switch error {
        case .invalidSelection: return .transcriptErrorInvalidSelection
        case .unsupportedType: return .transcriptErrorUnsupportedType
        case .tooLarge: return .transcriptErrorTooLarge
        case .invalidEncoding: return .transcriptErrorInvalidEncoding
        case .emptySource: return .transcriptErrorEmptySource
        case .approvalRequired: return .transcriptErrorApprovalRequired
        case .cancelled: return .transcriptErrorCancelled
        case .readTimedOut: return .transcriptErrorReadTimedOut
        case .invalidCommand: return .transcriptErrorInvalidCommand
        case .invalidRange: return .transcriptErrorInvalidRange
        case .incompleteCoverage: return .transcriptErrorIncompleteCoverage
        case .invalidEvidence: return .transcriptErrorInvalidEvidence
        case .budgetExceeded: return .transcriptErrorBudgetExceeded
        case .modelFailed: return .transcriptErrorModelFailed
        case .timedOut: return .transcriptErrorTimedOut
        case .contextChanged: return .transcriptErrorContextChanged
        }
    }

    /// The picker's names; TranscriptFormat.title stays Chinese for the model's goal text.
    static func transcriptFormat(_ format: TranscriptFormat) -> AppText {
        switch format {
        case .summary: return .transcriptFormatSummary
        case .chapters: return .transcriptFormatChapters
        case .quotations: return .transcriptFormatQuotations
        case .transcript: return .transcriptFormatTranscript
        case .article: return .transcriptFormatArticle
        }
    }
}
