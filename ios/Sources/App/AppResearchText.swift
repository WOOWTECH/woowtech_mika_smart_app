import AssistantBrowser

extension AppText {
    static let multiSourceErrors: [MultiSourceResearchError] = [
        .invalidPlan, .invalidCommand, .invalidModelJSON, .invalidCitation, .unsafeObservation, .staleObservation, .deadline,
    ]

    static func multiSourceError(_ error: MultiSourceResearchError) -> AppText {
        switch error {
        case .invalidPlan: return .multiResearchErrorInvalidPlan
        case .invalidCommand: return .multiResearchErrorInvalidCommand
        case .invalidModelJSON: return .multiResearchErrorInvalidModelJSON
        case .invalidCitation: return .multiResearchErrorInvalidCitation
        case .unsafeObservation: return .multiResearchErrorUnsafeObservation
        case .staleObservation: return .multiResearchErrorStaleObservation
        case .deadline: return .multiResearchErrorDeadline
        }
    }
}

extension AppText {
    static let sourceDiscoveryErrors: [ResearchSourceDiscoveryError] = [
        .invalidQuery, .alreadyUsed, .cancelled, .deadline, .notMounted, .privacyConfiguration, .navigationRejected,
        .navigationFailed, .responseRejected, .pageTooLarge, .pageChanged, .unavailable, .noCandidates, .invalidSelection,
    ]

    static func sourceDiscoveryError(_ error: ResearchSourceDiscoveryError) -> AppText {
        switch error {
        case .invalidQuery: return .sourceDiscoveryErrorInvalidQuery
        case .alreadyUsed: return .sourceDiscoveryErrorAlreadyUsed
        case .cancelled: return .sourceDiscoveryErrorCancelled
        case .deadline: return .sourceDiscoveryErrorDeadline
        case .notMounted: return .sourceDiscoveryErrorNotMounted
        case .privacyConfiguration: return .sourceDiscoveryErrorPrivacyConfiguration
        case .navigationRejected: return .sourceDiscoveryErrorNavigationRejected
        case .navigationFailed: return .sourceDiscoveryErrorNavigationFailed
        case .responseRejected: return .sourceDiscoveryErrorResponseRejected
        case .pageTooLarge: return .sourceDiscoveryErrorPageTooLarge
        case .pageChanged: return .sourceDiscoveryErrorPageChanged
        case .unavailable: return .sourceDiscoveryErrorUnavailable
        case .noCandidates: return .sourceDiscoveryErrorNoCandidates
        case .invalidSelection: return .sourceDiscoveryErrorInvalidSelection
        }
    }

    static func sourceDiscoveryProviderTitle(_ provider: ResearchSourceDiscoveryProvider) -> AppText {
        switch provider { case .duckDuckGoHTML: return .sourceDiscoveryProviderDuckDuckGo }
    }

    static func sourceDiscoveryProviderDisclosure(_ provider: ResearchSourceDiscoveryProvider) -> AppText {
        switch provider { case .duckDuckGoHTML: return .sourceDiscoveryProviderDuckDuckGoDisclosure }
    }
}
