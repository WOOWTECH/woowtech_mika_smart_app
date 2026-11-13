import Foundation

/// A user-initiated handoff may use only the URL of the page WebKit has
/// finished showing. The encrypted library's filter is necessary but not
/// sufficient for an external handoff: it strips hash routes and predates
/// auth/jwt query parameters. Keep its storage contract unchanged here.
public enum BrowserExternalOpenPolicy {
    // Known credential/callback route markers only. Arbitrary URLs cannot be
    // proven free of private data from their spelling alone.
    private static let sensitiveRouteTerms = [
        "auth", "oauth", "jwt", "token", "secret", "password", "passwd",
        "credential", "signature", "session", "assertion", "saml", "apikey",
        "bearer", "callback", "reset", "verify", "magic", "login", "signin"
    ]

    public static func destination(
        loadedURL: URL?, displayedURL: URL?, isLoading: Bool,
        navigationPending: Bool, isAutomated: Bool, isBusy: Bool,
        isPageAvailable: Bool
    ) -> URL? {
        guard isPageAvailable, !isLoading, !navigationPending,
              !isAutomated, !isBusy, let loadedURL,
              loadedURL == displayedURL,
              BrowserManualNavigationPolicy.libraryURL(loadedURL) != nil,
              let parts = URLComponents(url: loadedURL, resolvingAgainstBaseURL: false),
              safePath(parts), safeQuery(parts),
              safeFragment(parts.percentEncodedFragment) else { return nil }
        // The fragment is part of a hash-routed page. Return the exact WebKit
        // URL only after checking it; libraryURL's normalized URL drops it.
        return loadedURL
    }

    private static func safePath(_ parts: URLComponents) -> Bool {
        let raw = parts.percentEncodedPath.lowercased()
        let path = parts.path
        if raw.isEmpty { return path.isEmpty }
        // URLComponents decodes one layer. Encoded separators can change the
        // route at the receiving App; a remaining '%' may hide another layer.
        guard raw.hasPrefix("/"), path.utf8.count <= 4096,
              !["%2f", "%5c", "%3f", "%23", "%25", "%00"].contains(where: { raw.contains($0) }),
              path.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f }),
              !path.contains(where: { "%\\;=?#".contains($0) }) else { return false }
        for segment in path.split(separator: "/") {
            guard segment != ".", segment != ".." else { return false }
            let normalized = segment.lowercased().filter { $0 != "-" && $0 != "_" && $0 != "." }
            guard !normalized.isEmpty,
                  !sensitiveRouteTerms.contains(where: { normalized.contains($0) }) else { return false }
        }
        return true
    }

    private static func safeQuery(_ parts: URLComponents) -> Bool {
        guard let rawQuery = parts.percentEncodedQuery else { return true }
        guard let items = parts.queryItems, !items.isEmpty,
              !rawQuery.contains(";") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        for item in items {
            let name = item.name
            // URLComponents decodes one layer. A remaining percent sign could
            // hide a second encoded credential name, so fail closed.
            guard !name.isEmpty, name.utf8.count <= 128,
                  name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
            let normalized = name.lowercased().filter { $0 != "-" && $0 != "_" && $0 != "." }
            if ["jwt", "auth", "oauth", "bearer", "token", "secret"].contains(where: {
                normalized.contains($0)
            }) { return false }
        }
        return true
    }

    private static func safeFragment(_ raw: String?) -> Bool {
        guard let raw else { return true }
        // Permit ordinary anchors and ASCII hash routes such as #/docs/42.
        // Encoded, parameter-shaped and oversized fragments cannot be
        // classified reliably and are never handed to another application.
        guard !raw.isEmpty, raw.utf8.count <= 256 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.~/")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let path = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty, segments.count <= 16 else { return false }
        for segment in segments {
            guard !segment.isEmpty, segment.utf8.count <= 48,
                  segment != ".", segment != ".." else { return false }
            let normalized = segment.lowercased().filter { $0 != "-" && $0 != "_" && $0 != "." }
            guard !sensitiveRouteTerms.contains(where: { normalized.contains($0) }) else { return false }
            let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            let hasLetter = segment.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            let hasDigit = segment.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            if segment.utf8.count >= 16 &&
                (segment.unicodeScalars.allSatisfy { hexadecimal.contains($0) } || (hasLetter && hasDigit)) {
                return false
            }
            if segment.utf8.count >= 24 {
                return false
            }
        }
        return true
    }
}
