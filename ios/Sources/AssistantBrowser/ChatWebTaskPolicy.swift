import Foundation

/// Where a web task started from chat may go, like the Play build's
/// WebUrlPolicy: any public HTTPS site, query strings included (search result
/// pages need them), across sites. Research keeps its narrower WebsiteOrigin
/// rule. Account actions such as logging out or deleting are never opened by
/// the task, and sign-in pages are left to the user. A URL-only rule: it does
/// not resolve DNS (see BrowserPolicy).
public enum ChatWebTaskPolicy {
    public static let maximumURLBytes = 4096

    public enum Decision: Equatable, Sendable {
        case allow(URL)
        /// Sign-in, sign-up and other account pages need the user's hands.
        case signIn(URL)
        case block(Reason)
    }

    public enum Reason: String, Equatable, Sendable {
        /// Not an absolute HTTPS URL, too long, or not parseable.
        case invalid = "invalid_url"
        /// Local, private-network or otherwise non-public destination.
        case notPublic = "not_public"
        case credentials = "credentials_in_url"
        /// Logging out, deleting, unsubscribing and similar account actions.
        case accountAction = "account_action"
    }

    /// Path segments that change an account when merely opened.
    static let accountActions: Set<String> = [
        "logout", "log-out", "log_out", "signout", "sign-out", "sign_out", "delete", "destroy",
        "unsubscribe", "revoke", "deactivate", "reset-password", "resetpassword", "password",
        "webhook", "webhooks", "token", "tokens", "secret", "secrets"]
    /// The account paths MultiSourceResearchTypes already treats as sign-in pages.
    static let accountPages: Set<String> = [
        "login", "signin", "sign-in", "sign_in", "signup", "sign-up", "sign_up", "register",
        "account", "accounts", "auth", "oauth", "oauth2", "callback", "authorize", "authentication"]

    /// Text a model supplied. A test origin such as http://127.0.0.1:port is
    /// allowed only when the host passes it (Debug fixtures), never from text.
    public static func evaluate(address: String, fixtureOrigin: URL? = nil) -> Decision {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumURLBytes,
              !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains),
              let url = URL(string: trimmed) else { return .block(.invalid) }
        return evaluate(url, fixtureOrigin: fixtureOrigin)
    }

    public static func evaluate(_ url: URL, fixtureOrigin: URL? = nil) -> Decision {
        guard url.baseURL == nil, url.absoluteString.utf8.count <= maximumURLBytes,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), parts.host?.isEmpty == false else { return .block(.invalid) }
        guard parts.user == nil, parts.password == nil else { return .block(.credentials) }
        if !(fixtureOrigin.map { sameOrigin(url, $0) } ?? false) {
            guard scheme == "https" else { return .block(.invalid) }
            guard case .allow = BrowserPolicy.evaluate(url) else { return .block(.notPublic) }
        }
        let segments = pathSegments(url)
        if segments.contains(where: { accountActions.contains($0) }) { return .block(.accountAction) }
        if segments.contains(where: { accountPages.contains($0) }) { return .signIn(url) }
        return .allow(url)
    }

    /// The address to keep or show: no fragment or user information, and no
    /// query at all when it carries something that looks like a secret.
    public static func displayURL(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.user = nil; parts.password = nil; parts.fragment = nil
        let sensitive = ["code", "token", "key", "secret", "password", "passwd", "credential", "signature", "session",
                         "authorization", "assertion", "samlresponse", "apikey", "accesstoken", "refreshtoken",
                         "idtoken", "sessionid", "clientsecret", "auth", "otp"]
        let hasSecret = (parts.queryItems ?? []).contains { item in
            let name = item.name.lowercased().replacingOccurrences(of: "-", with: "_")
            return sensitive.contains { name == $0 || name.hasSuffix("_" + $0) || name.hasPrefix($0 + "_") }
        }
        let callback = pathSegments(url).contains { ["callback", "oauth", "authorize", "webhook"].contains($0) }
        if hasSecret || callback { parts.query = nil }
        return parts.url ?? url
    }

    /// The site a page belongs to for pacing and display: the host without "www.".
    public static func site(of url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Decoded, lowercased path segments, each also without its extension
    /// ("logout.php" counts as "logout").
    static func pathSegments(_ url: URL) -> [String] {
        var path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        for _ in 0..<3 { path = path.removingPercentEncoding ?? path }
        return path.lowercased().split(separator: "/").flatMap { segment -> [String] in
            let whole = String(segment)
            guard let dot = whole.firstIndex(of: "."), dot != whole.startIndex else { return [whole] }
            return [whole, String(whole[..<dot])]
        }
    }

    static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        url.scheme?.lowercased() == origin.scheme?.lowercased()
            && url.host?.lowercased() == origin.host?.lowercased()
            && (url.port ?? defaultPort(url)) == (origin.port ?? defaultPort(origin))
    }

    private static func defaultPort(_ url: URL) -> Int {
        url.scheme?.lowercased() == "http" ? 80 : 443
    }
}
