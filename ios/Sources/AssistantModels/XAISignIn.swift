import Foundation

/// Signing in with an xAI / Grok subscription and calling xAI's own Responses interface
/// (`https://api.x.ai/v1/responses`), the way the Play build does (core/oauth/XaiAuth.kt and
/// DeviceCode.kt): an RFC 8628 device code that the person approves on xAI's page.
///
/// The client is the public sign-in client of xAI's official command-line tool. xAI did not
/// register it for this App and may not support this use, so the screen says so before anything
/// happens. Every discovered address must be https on `auth.x.ai` (the verification page may also
/// be on `accounts.x.ai`); anything else is refused before a request is sent.
public enum XAISignIn {
    public static let provider = "xai"
    public static let host = "auth.x.ai"
    public static let issuer = "https://auth.x.ai"
    /// xAI's official command-line tool's public client (not registered for this App; see the
    /// notice shown before signing in).
    public static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    public static let scopeCLI = "grok-cli:access"
    public static let scopeAPI = "api:access"
    public static let scopes = "openid profile email offline_access \(scopeCLI) \(scopeAPI)"
    /// The subscription's calls: xAI's own Responses, never converted to another protocol.
    public static let apiBase = URL(string: "https://api.x.ai/v1")!
    /// Where people manage the account and its grants.
    public static let accountPage = URL(string: "https://accounts.x.ai")!
    public static let fallbackVerify = "https://accounts.x.ai/oauth2/device"
    public static let issuerHosts: Set<String> = [host]
    public static let verifyHosts: Set<String> = [host, "accounts.x.ai"]
    public static let deviceGrant = "urn:ietf:params:oauth:grant-type:device_code"
    static let defaultExpiresIn: Int64 = 900
    static let defaultInterval: Int64 = 5
    static let slowDownMs: Int64 = 5_000
    static let maximumPollFailures = 3

    /// The refresh token can no longer be used.
    public static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused"]
}

/// Why a subscription sign-in did not finish; the screen words each one (Play
/// AccountSignInFailure). The error carries a category and a server code, never a token, device
/// code or authorization code. `.badIssuer`: a discovered address was not on an allowed host, so
/// nothing was sent there.
public enum XAISignInFailure: String, Sendable {
    case denied, expired, timedOut, rejected, noSubscription, network, badIssuer
}

public struct XAISignInError: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: XAISignInFailure
    /// The server's error code (not a secret), when there is one.
    public let code: String?

    public init(_ reason: XAISignInFailure, code: String? = nil) { self.reason = reason; self.code = code }

    public var description: String { code.map { reason.rawValue + ": " + $0 } ?? reason.rawValue }
}

/// Only https (http only on 127.0.0.1 and localhost, for local test servers) and a host from the
/// list; an address with user info is always refused (Play OauthUrls).
public enum OAuthHosts {
    public static func allowed(_ raw: String, hosts: Set<String>) -> URL? {
        guard let parts = URLComponents(string: raw), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        let local = host == "127.0.0.1" || host == "localhost"
        guard scheme == "https" || (local && scheme == "http") else { return nil }
        return hosts.contains(host) ? url : nil
    }

    static func checked(_ raw: String, hosts: Set<String>) throws -> URL {
        guard let url = allowed(raw, hosts: hosts) else { throw XAISignInError(.badIssuer, code: "host") }
        return url
    }
}

/// The device code's part for people: the user code, the verification page, how long it lasts and
/// the polling interval. The device code itself is not here: it never reaches a screen or a log.
public struct XAIDeviceChallenge: Equatable, Sendable {
    public let userCode: String
    public let verificationURI: String
    /// Has the user code in it already; kept only when its host is allowed.
    public let verificationURIComplete: String?
    public let expiresIn: Int64
    public let interval: Int64

    public init(userCode: String, verificationURI: String, verificationURIComplete: String?, expiresIn: Int64, interval: Int64) {
        self.userCode = userCode; self.verificationURI = verificationURI
        self.verificationURIComplete = verificationURIComplete; self.expiresIn = expiresIn; self.interval = interval
    }

    /// The page to open: the one with the code in it when there is one.
    public var openURL: String { verificationURIComplete ?? verificationURI }
}

/// One device authorization; the device code is kept for polling only.
public struct XAIDeviceGrant: Sendable {
    public let challenge: XAIDeviceChallenge
    let deviceCode: String

    init(challenge: XAIDeviceChallenge, deviceCode: String) { self.challenge = challenge; self.deviceCode = deviceCode }
}

/// What an exchange or a refresh gave. Fields a refresh leaves out are nil and kept from before.
public struct XAITokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Int64
    public let scopes: [String]

    public init(accessToken: String, refreshToken: String? = nil, idToken: String? = nil, expiresIn: Int64 = 3600,
                scopes: [String] = []) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken
        self.expiresIn = expiresIn; self.scopes = scopes
    }
}

/// One poll. Errors keep only the code, never the body (which can hold tokens).
public enum XAIDevicePoll: Equatable, Sendable {
    case pending
    case slowDown
    case tokens(XAITokens)
    case rejected(code: String, terminal: Bool)
    case failed(AccountTransportFailure)
}

/// The discovered device and token addresses, hosts already checked.
public struct XAIEndpoints: Equatable, Sendable {
    public let deviceURL: URL
    public let tokenURL: URL
    public let userinfoURL: URL?
}

/// One xAI account's sign-in (Play AccountSession), kept whole in the provider's Keychain item.
/// Signing out clears the tokens; the account name stays to be shown.
public struct XAISession: Codable, Equatable, Sendable, ModelAccountSessionValue {
    public var provider: String
    public var accountId: String
    /// Shown to people only (an email address, when xAI gave one).
    public var label: String
    public var accessToken: String
    public var refreshToken: String
    public var expiresAtMs: Int64
    public var scopes: [String]
    public var apiBase: String
    public var clientId: String
    public var issuer: String
    /// The token endpoint read from discovery when signing in (host checked); refreshes use it.
    public var tokenURL: String

    public init(provider: String = XAISignIn.provider, accountId: String = "", label: String = "", accessToken: String = "",
                refreshToken: String = "", expiresAtMs: Int64 = 0, scopes: [String] = [], apiBase: String = "",
                clientId: String = "", issuer: String = "", tokenURL: String = "") {
        self.provider = provider; self.accountId = accountId; self.label = label; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.expiresAtMs = expiresAtMs; self.scopes = scopes; self.apiBase = apiBase
        self.clientId = clientId; self.issuer = issuer; self.tokenURL = tokenURL
    }

    public var signedIn: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }

    public func signedOut() -> Self {
        var session = self
        session.accessToken = ""; session.refreshToken = ""; session.expiresAtMs = 0
        return session
    }

    private enum CodingKeys: String, CodingKey {
        case provider, accountId, label, accessToken, refreshToken, expiresAtMs, scopes, apiBase, clientId, issuer, tokenURL
    }

    /// Also reads Play's JSON, which leaves out fields still at their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(String.self, forKey: .provider)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        expiresAtMs = try c.decodeIfPresent(Int64.self, forKey: .expiresAtMs) ?? 0
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        apiBase = try c.decodeIfPresent(String.self, forKey: .apiBase) ?? ""
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId) ?? ""
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer) ?? ""
        tokenURL = try c.decodeIfPresent(String.self, forKey: .tokenURL) ?? ""
    }
}

/// Discovery, the device code, polling, the identity and refreshes at one issuer (Play XaiAuth and
/// DeviceCodeClient). Every address is checked against the host lists first.
public final class XAIAuthClient: @unchecked Sendable {
    public let issuer: String
    public let clientID: String
    private let http: any AccountHTTP
    private let issuerHosts: Set<String>
    private let verifyHosts: Set<String>

    public init(http: any AccountHTTP = URLSessionAccountHTTP.shared, issuer: String = XAISignIn.issuer,
                clientID: String = XAISignIn.clientID, issuerHosts: Set<String> = XAISignIn.issuerHosts,
                verifyHosts: Set<String> = XAISignIn.verifyHosts) {
        self.http = http; self.issuer = issuer; self.clientID = clientID
        self.issuerHosts = issuerHosts; self.verifyHosts = verifyHosts
    }

    private var trimmedIssuer: String {
        var value = issuer
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Reads the OpenID discovery document and keeps only device and token addresses on allowed
    /// hosts; the issuer it names must be this one.
    public func discover() async throws -> XAIEndpoints {
        let documentURL = try OAuthHosts.checked(trimmedIssuer + "/.well-known/openid-configuration", hosts: issuerHosts)
        let answer = try await get(documentURL)
        guard answer.status == 200 else { throw XAISignInError(.network, code: "http_\(answer.status)") }
        guard let root = Self.object(answer.body) else { throw XAISignInError(.badIssuer, code: "discovery") }
        var found = (root["issuer"] as? String) ?? ""
        while found.hasSuffix("/") { found.removeLast() }
        guard found == trimmedIssuer else { throw XAISignInError(.badIssuer, code: "issuer") }
        guard let device = root["device_authorization_endpoint"] as? String else { throw XAISignInError(.badIssuer, code: "no_device") }
        guard let token = root["token_endpoint"] as? String else { throw XAISignInError(.badIssuer, code: "no_token") }
        let userinfo = (root["userinfo_endpoint"] as? String).flatMap { OAuthHosts.allowed($0, hosts: issuerHosts) }
        return XAIEndpoints(deviceURL: try OAuthHosts.checked(device, hosts: issuerHosts),
                            tokenURL: try OAuthHosts.checked(token, hosts: issuerHosts), userinfoURL: userinfo)
    }

    /// Asks for a device code. The verification pages are kept only on allowed hosts: the plain
    /// one falls back to xAI's own page, the one with the code is dropped.
    public func start(_ endpoints: XAIEndpoints) async throws -> XAIDeviceGrant {
        let request = ChatGPTSignIn.formRequest(endpoints.deviceURL.absoluteString, [("client_id", clientID), ("scope", XAISignIn.scopes)])
        let answer: (status: Int, body: Data)
        do { answer = try await http.send(request) }
        catch {
            try Task.checkCancellation()
            throw XAISignInError(.network)
        }
        guard let root = Self.object(answer.body) else { throw XAISignInError(.rejected, code: "http_\(answer.status)") }
        guard answer.status == 200 else {
            let code = (root["error"] as? String) ?? "http_\(answer.status)"
            let reason: XAISignInFailure = (500...599).contains(answer.status) || answer.status == 429 ? .network
                : code == "access_denied" ? .denied : .rejected
            throw XAISignInError(reason, code: code)
        }
        guard let device = root["device_code"] as? String, !device.isEmpty else { throw XAISignInError(.rejected, code: "no_device_code") }
        guard let user = root["user_code"] as? String, !user.isEmpty else { throw XAISignInError(.rejected, code: "no_user_code") }
        guard let verify = root["verification_uri"] as? String, !verify.isEmpty else {
            throw XAISignInError(.rejected, code: "no_verification_uri")
        }
        let complete = (root["verification_uri_complete"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expires = ChatGPTSignIn.int64(root["expires_in"]).flatMap { $0 > 0 ? $0 : nil } ?? XAISignIn.defaultExpiresIn
        let interval = ChatGPTSignIn.int64(root["interval"]).flatMap { $0 > 0 ? $0 : nil } ?? XAISignIn.defaultInterval
        let shown = OAuthHosts.allowed(verify, hosts: verifyHosts) != nil ? verify : XAISignIn.fallbackVerify
        guard OAuthHosts.allowed(shown, hosts: verifyHosts) != nil else { throw XAISignInError(.badIssuer, code: "verify") }
        let completeShown = complete.flatMap { OAuthHosts.allowed($0, hosts: verifyHosts) != nil ? $0 : nil }
        return XAIDeviceGrant(challenge: XAIDeviceChallenge(userCode: user, verificationURI: shown, verificationURIComplete: completeShown,
                                                            expiresIn: expires, interval: interval),
                              deviceCode: device)
    }

    /// Asks once. The device code goes only in the form; only cancellation throws.
    public func poll(_ endpoints: XAIEndpoints, deviceCode: String) async throws -> XAIDevicePoll {
        guard let url = OAuthHosts.allowed(endpoints.tokenURL.absoluteString, hosts: issuerHosts) else {
            return .rejected(code: "host", terminal: true)
        }
        let request = ChatGPTSignIn.formRequest(url.absoluteString, [("client_id", clientID), ("device_code", deviceCode),
                                                                     ("grant_type", XAISignIn.deviceGrant)])
        let answer: (status: Int, body: Data)
        do { answer = try await http.send(request) }
        catch {
            try Task.checkCancellation()
            return .failed(.network(String(describing: type(of: error))))
        }
        return Self.interpret(status: answer.status, body: answer.body)
    }

    static func interpret(status: Int, body: Data) -> XAIDevicePoll {
        if (500...599).contains(status) { return .failed(.server(status)) }
        let root = object(body)
        if let error = root?["error"] as? String {
            switch error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "access_denied", "authorization_denied", "expired_token": return .rejected(code: error, terminal: true)
            default: return .rejected(code: error, terminal: status != 429)
            }
        }
        if status == 429 { return .slowDown }
        guard status == 200, let root else { return .rejected(code: "http_\(status)", terminal: false) }
        guard let access = root["access_token"] as? String, !access.isEmpty else { return .rejected(code: "no_access_token", terminal: true) }
        return .tokens(tokens(root, access: access))
    }

    /// Waits until the person approved, or the code expired, was refused or the wait was cancelled
    /// (Play awaitDeviceGrant). The interval is the server's; `slow_down` adds five seconds. While the
    /// person is on xAI's page the App may lose the network for a moment: only three failed polls in a
    /// row end the wait. `sleep` is in milliseconds; tests stand in a fake clock.
    public static func awaitGrant(_ grant: XAIDeviceGrant, nowMs: @Sendable () -> Int64,
                                  sleep: @Sendable (Int64) async throws -> Void,
                                  poll: @Sendable (String) async throws -> XAIDevicePoll) async throws -> XAITokens {
        let deadline = nowMs() + grant.challenge.expiresIn * 1000
        var interval = max(1, grant.challenge.interval) * 1000
        var failures = 0
        while nowMs() < deadline {
            try Task.checkCancellation()
            switch try await poll(grant.deviceCode) {
            case .pending:
                failures = 0
            case .slowDown:
                failures = 0
                interval += XAISignIn.slowDownMs
            case .tokens(let tokens):
                return tokens
            case .rejected(let code, _):
                let reason: XAISignInFailure = code == "expired_token" ? .expired
                    : code == "access_denied" || code == "authorization_denied" ? .denied : .rejected
                throw XAISignInError(reason, code: code)
            case .failed:
                failures += 1
                if failures >= XAISignIn.maximumPollFailures { throw XAISignInError(.network) }
            }
            try await sleep(min(interval, max(0, deadline - nowMs())))
        }
        throw XAISignInError(.timedOut, code: "expired")
    }

    /// The whole sign-in (Play XaiAuth.signIn): discovery, the code (`onChallenge` shows it and
    /// opens the page), the wait, the subscription scope and who signed in.
    public func signIn(onChallenge: @Sendable (XAIDeviceChallenge) async -> Void,
                       sleep: @escaping @Sendable (Int64) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0)) * 1_000_000) },
                       nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() }) async throws -> XAISession {
        let endpoints = try await discover()
        let grant = try await start(endpoints)
        await onChallenge(grant.challenge)
        let tokens = try await Self.awaitGrant(grant, nowMs: nowMs, sleep: sleep) { code in
            try await self.poll(endpoints, deviceCode: code)
        }
        if !tokens.scopes.isEmpty, !tokens.scopes.contains(where: { $0 == XAISignIn.scopeCLI || $0 == XAISignIn.scopeAPI }) {
            throw XAISignInError(.noSubscription, code: "scope")
        }
        let who = await identity(endpoints.userinfoURL, tokens: tokens)
        return XAISession(accountId: who.sub.isEmpty ? "xai" : who.sub, label: who.email, accessToken: tokens.accessToken,
                          refreshToken: tokens.refreshToken ?? "", expiresAtMs: nowMs() + tokens.expiresIn * 1000,
                          scopes: tokens.scopes, apiBase: XAISignIn.apiBase.absoluteString, clientId: clientID,
                          issuer: trimmedIssuer, tokenURL: endpoints.tokenURL.absoluteString)
    }

    /// A new pair from the refresh token, at the token address read when signing in; its host must
    /// still be allowed (Play XaiAuth.refresh).
    public func refresh(_ session: XAISession, nowMs: @Sendable () -> Int64 = { ModelAccountClock.nowMs() })
        async throws -> ModelAccountRefreshResult<XAISession> {
        guard !session.refreshToken.isEmpty else { return .rejected(terminal: true) }
        var base = session.issuer.isEmpty ? trimmedIssuer : session.issuer
        while base.hasSuffix("/") { base.removeLast() }
        let address = session.tokenURL.isEmpty ? base + "/oauth2/token" : session.tokenURL
        guard let url = OAuthHosts.allowed(address, hosts: issuerHosts) else { return .rejected(terminal: true) }
        let request = ChatGPTSignIn.formRequest(url.absoluteString, [
            ("grant_type", "refresh_token"), ("refresh_token", session.refreshToken),
            ("client_id", session.clientId.isEmpty ? clientID : session.clientId)])
        let answer: (status: Int, body: Data)
        do { answer = try await http.send(request) }
        catch {
            try Task.checkCancellation()
            return .failed(HTTPChatModelError.transportFailure)
        }
        if (500...599).contains(answer.status) { return .failed(HTTPChatModelError.httpStatus(answer.status)) }
        let root = Self.object(answer.body)
        let error = root?["error"] as? String
        guard answer.status == 200, error == nil, let root else {
            let code = error ?? "http_\(answer.status)"
            return .rejected(terminal: XAISignIn.terminalRefreshErrors.contains(code) || answer.status == 401)
        }
        guard let access = root["access_token"] as? String, !access.isEmpty else { return .rejected(terminal: false) }
        let tokens = Self.tokens(root, access: access)
        var next = session
        next.accessToken = tokens.accessToken
        next.refreshToken = tokens.refreshToken ?? session.refreshToken
        next.expiresAtMs = nowMs() + tokens.expiresIn * 1000
        next.scopes = tokens.scopes.isEmpty ? session.scopes : tokens.scopes
        next.apiBase = XAISignIn.apiBase.absoluteString
        return .refreshed(next)
    }

    /// The token gate for one xAI provider: refreshed five minutes before expiry or after a 401,
    /// one refresh at a time.
    public func tokenGate(load: @escaping @Sendable () throws -> XAISession?,
                          save: @escaping @Sendable (_ before: XAISession, _ after: XAISession) throws -> Void,
                          nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() }) -> ModelAccountTokenGate<XAISession> {
        ModelAccountTokenGate(kind: .xai, nowMs: nowMs, load: load, save: save,
                              refresh: { [self] session in try await self.refresh(session, nowMs: nowMs) })
    }

    /// Who signed in, for people only: userinfo first, otherwise the ID token's claims (not
    /// verified, so never used to authorize anything). Empty when neither says.
    func identity(_ userinfo: URL?, tokens: XAITokens) async -> (sub: String, email: String) {
        if let userinfo {
            var request = URLRequest(url: userinfo)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer " + tokens.accessToken, forHTTPHeaderField: "Authorization")
            if let answer = try? await http.send(request), answer.status == 200, let root = Self.object(answer.body) {
                let sub = (root["sub"] as? String) ?? ""
                let email = (root["email"] as? String) ?? (root["preferred_username"] as? String) ?? ""
                if !sub.isEmpty || !email.isEmpty { return (sub, email) }
            }
        }
        return Self.idClaims(tokens.idToken)
    }

    /// The ID token's middle part, unverified: only to show an email.
    static func idClaims(_ idToken: String?) -> (sub: String, email: String) {
        let parts = idToken?.split(separator: ".", omittingEmptySubsequences: false) ?? []
        guard parts.count > 1, let data = PKCE.base64URLDecode(String(parts[1])), let root = object(data) else { return ("", "") }
        let email = (root["email"] as? String) ?? ((root["https://api.x.ai/profile"] as? [String: Any])?["email"] as? String) ?? ""
        return ((root["sub"] as? String) ?? "", email)
    }

    private static func tokens(_ root: [String: Any], access: String) -> XAITokens {
        XAITokens(accessToken: access, refreshToken: root["refresh_token"] as? String, idToken: root["id_token"] as? String,
                  expiresIn: ChatGPTSignIn.int64(root["expires_in"]).flatMap { $0 > 0 ? $0 : nil } ?? 3600,
                  scopes: (root["scope"] as? String)?.split(separator: " ").map(String.init) ?? [])
    }

    private func get(_ url: URL) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { return try await http.send(request) }
        catch {
            try Task.checkCancellation()
            throw XAISignInError(.network, code: "http")
        }
    }

    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
