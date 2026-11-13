import AssistantBrowser

extension AppText {
    static func downloadStatus(_ status: BrowserDownloadStatus) -> AppText {
        switch status {
        case .waiting: return .downloadStatusWaiting
        case .downloading: return .downloadStatusDownloading
        case .cancelling: return .downloadStatusCancelling
        case .completed: return .downloadStatusCompleted
        case .cancelled: return .downloadStatusCancelled
        case .failed: return .downloadStatusFailed
        }
    }

    static func downloadError(_ error: BrowserDownloadError) -> AppText {
        switch error {
        case .unavailable: return .downloadErrorUnavailable
        case .unsafeURL: return .downloadErrorUnsafeURL
        case .researchDisabled: return .downloadErrorResearchDisabled
        case .tooMany: return .downloadErrorTooMany
        case .tooLarge: return .downloadErrorTooLarge
        case .invalidFile: return .downloadErrorInvalidFile
        case .invalidMetadata: return .downloadErrorInvalidMetadata
        case .confirmationRequired: return .downloadErrorConfirmationRequired
        case .stillRunning: return .downloadErrorStillRunning
        case .missingFile: return .downloadErrorMissingFile
        case .network: return .downloadErrorNetwork
        case .redirectLimit: return .downloadErrorRedirectLimit
        }
    }

    /// The download manager stores its notices and an item's failure as text
    /// (failures are saved with the item). That text is always one of the
    /// manager's own closed messages, so it maps back to a typed message here;
    /// anything else is shown as stored.
    static func downloadMessage(_ stored: String) -> AppText? {
        if stored == AppText.downloadCleanupFailed.traditionalFallback { return .downloadCleanupFailed }
        let errors: [BrowserDownloadError] = [.unavailable, .unsafeURL, .researchDisabled, .tooMany, .tooLarge,
                                              .invalidFile, .invalidMetadata, .confirmationRequired, .stillRunning,
                                              .missingFile, .network, .redirectLimit]
        return errors.first { $0.errorDescription == stored }.map(downloadError)
    }
}
