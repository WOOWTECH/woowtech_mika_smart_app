import AssistantSkills

extension AppText {
    static let skillToolErrors: [SkillToolError] = [
        .invalidLimits, .invalidCommand, .invalidState, .sourceReadRequired, .searchRequired, .unknownReference,
        .staleVersion, .unsupportedFile, .budgetExceeded, .timedOut, .modelFailed, .modelRejected,
        .modelInvalidResponse, .cancelled, .tooManyFailures,
    ]

    static func skillToolError(_ error: SkillToolError) -> AppText {
        switch error {
        case .invalidLimits: return .skillToolErrorInvalidLimits
        case .invalidCommand: return .skillToolErrorInvalidCommand
        case .invalidState: return .skillToolErrorInvalidState
        case .sourceReadRequired: return .skillToolErrorSourceReadRequired
        case .searchRequired: return .skillToolErrorSearchRequired
        case .unknownReference: return .skillToolErrorUnknownReference
        case .staleVersion: return .skillToolErrorStaleVersion
        case .unsupportedFile: return .skillToolErrorUnsupportedFile
        case .budgetExceeded: return .skillToolErrorBudgetExceeded
        case .timedOut: return .skillToolErrorTimedOut
        case .modelFailed: return .skillToolErrorModelFailed
        case .modelRejected: return .skillToolErrorModelRejected
        case .modelInvalidResponse: return .skillToolErrorModelInvalidResponse
        case .cancelled: return .skillToolErrorCancelled
        case .tooManyFailures: return .skillToolErrorTooManyFailures
        }
    }
}
