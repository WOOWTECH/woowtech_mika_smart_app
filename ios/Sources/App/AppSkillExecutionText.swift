import AssistantSkills

extension AppText {
    static let skillExecutionErrors: [SkillExecutionError] = [
        .unavailable, .invalidSelection, .fileTooLarge, .invalidPDF, .passwordRequired, .invalidPages,
        .tooManyPages, .outputTooLarge, .approvalRequired, .expiredApproval, .stalePlan, .busy, .cancelled,
    ]

    static func skillExecutionError(_ error: SkillExecutionError) -> AppText {
        switch error {
        case .unavailable: return .skillExecutionErrorUnavailable
        case .invalidSelection: return .skillExecutionErrorInvalidSelection
        case .fileTooLarge: return .skillExecutionErrorFileTooLarge
        case .invalidPDF: return .skillExecutionErrorInvalidPDF
        case .passwordRequired: return .skillExecutionErrorPasswordRequired
        case .invalidPages: return .skillExecutionErrorInvalidPages
        case .tooManyPages: return .skillExecutionErrorTooManyPages
        case .outputTooLarge: return .skillExecutionErrorOutputTooLarge
        case .approvalRequired: return .skillExecutionErrorApprovalRequired
        case .expiredApproval: return .skillExecutionErrorExpiredApproval
        case .stalePlan: return .skillExecutionErrorStalePlan
        case .busy: return .skillExecutionErrorBusy
        case .cancelled: return .skillExecutionErrorCancelled
        }
    }
}
