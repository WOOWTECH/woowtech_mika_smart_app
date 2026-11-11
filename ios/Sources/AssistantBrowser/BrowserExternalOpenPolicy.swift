import Foundation

/// A user-initiated handoff may use only the public URL of the page that
/// WebKit has actually finished showing. Reuse the library's secret filter so
/// callback/session URLs cannot escape through the external-open action.
public enum BrowserExternalOpenPolicy {
    public static func destination(
        loadedURL: URL?, displayedURL: URL?, isLoading: Bool,
        navigationPending: Bool, isAutomated: Bool, isBusy: Bool,
        isPageAvailable: Bool
    ) -> URL? {
        guard isPageAvailable, !isLoading, !navigationPending,
              !isAutomated, !isBusy, let loadedURL,
              loadedURL == displayedURL else { return nil }
        return BrowserManualNavigationPolicy.libraryURL(loadedURL)
    }
}
