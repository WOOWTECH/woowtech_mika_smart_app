import AssistantSkills

extension AppText {
    static let skillAuthoringErrors: [SkillAuthoringError] = [
        .invalidRequest, .requestMismatch, .unavailable, .cancelled, .notFound, .readRequired, .staleRead,
        .disabledNameConflict, .draftConflict, .reviewChanged, .approvalRequired, .expiredApproval,
        .storageChanged, .capabilitiesChanged, .persistenceFailed, .resourceLimit,
    ]

    static func skillAuthoringError(_ error: SkillAuthoringError) -> AppText {
        switch error {
        case .invalidRequest: return .skillAuthoringErrorInvalidRequest
        case .requestMismatch: return .skillAuthoringErrorRequestMismatch
        case .unavailable: return .skillAuthoringErrorUnavailable
        case .cancelled: return .skillAuthoringErrorCancelled
        case .notFound: return .skillAuthoringErrorNotFound
        case .readRequired: return .skillAuthoringErrorReadRequired
        case .staleRead: return .skillAuthoringErrorStaleRead
        case .disabledNameConflict: return .skillAuthoringErrorDisabledNameConflict
        case .draftConflict: return .skillAuthoringErrorDraftConflict
        case .reviewChanged: return .skillAuthoringErrorReviewChanged
        case .approvalRequired: return .skillAuthoringErrorApprovalRequired
        case .expiredApproval: return .skillAuthoringErrorExpiredApproval
        case .storageChanged: return .skillAuthoringErrorStorageChanged
        case .capabilitiesChanged: return .skillAuthoringErrorCapabilitiesChanged
        case .persistenceFailed: return .skillAuthoringErrorPersistenceFailed
        case .resourceLimit: return .skillAuthoringErrorResourceLimit
        }
    }

    static func skillStatus(_ status: SkillStatus) -> AppText {
        switch status {
        case .pending: return .skillStatusPending
        case .trial: return .skillStatusTrial
        case .active: return .skillStatusActive
        case .suspended: return .skillStatusSuspended
        }
    }
}
