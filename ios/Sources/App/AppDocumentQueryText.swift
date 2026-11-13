import AssistantSkills

extension AppText {
    static let documentQueryErrors: [DocumentQueryError] = [
        .invalidSource, .emptySource, .sourceTooLarge, .invalidQuestion, .invalidLimits, .invalidRange,
        .invalidSearch, .invalidEvidence, .invalidCommand, .budgetExceeded, .outputTooLarge, .cancelled,
        .timedOut, .contextChanged, .modelFailed,
    ]

    static func documentQueryError(_ error: DocumentQueryError) -> AppText {
        switch error {
        case .invalidSource: return .documentQueryErrorInvalidSource
        case .emptySource: return .documentQueryErrorEmptySource
        case .sourceTooLarge: return .documentQueryErrorSourceTooLarge
        case .invalidQuestion: return .documentQueryErrorInvalidQuestion
        case .invalidLimits: return .documentQueryErrorInvalidLimits
        case .invalidRange: return .documentQueryErrorInvalidRange
        case .invalidSearch: return .documentQueryErrorInvalidSearch
        case .invalidEvidence: return .documentQueryErrorInvalidEvidence
        case .invalidCommand: return .documentQueryErrorInvalidCommand
        case .budgetExceeded: return .documentQueryErrorBudgetExceeded
        case .outputTooLarge: return .documentQueryErrorOutputTooLarge
        case .cancelled: return .documentQueryErrorCancelled
        case .timedOut: return .documentQueryErrorTimedOut
        case .contextChanged: return .documentQueryErrorContextChanged
        case .modelFailed: return .documentQueryErrorModelFailed
        }
    }
}
