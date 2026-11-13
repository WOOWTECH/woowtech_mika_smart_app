import CryptoKit
import Foundation
import Security

/// 「使用 ChatGPT 繼續」 the way the Play build signs in (core/chatgpt/ChatGptAuth.kt and
/// ChatGptSession.kt @964d7bec): OpenAI's sign-in for apps that use a ChatGPT plan's quota. A public
/// client without a secret, authorization code + PKCE (S256). The first sign-in registers through
/// `dynamic_agent_client` with the App's English name and this device's host id; the callback names
/// the account's own client id, used from then on for exchanges, refreshes and later sign-ins. The
/// redirect is always `http://127.0.0.1:<port>/auth/callback` (LoopbackCallbackServer).
///
/// Validation prototype: scripts/CheckChatGPTSignIn.swift checks it offline. No screen or model
/// client uses it yet.
public enum ChatGPTSignIn {
    public static let issuer = "https://auth.openai.com"
    public static let registerClientID = "dynamic_agent_client"
    /// The name OpenAI's consent page shows: the Play woowtech build's English product name
    /// (brand.properties `name`). It follows the owner's decision on the English name.
    public static let appName = "woowtech agent"
    public static let planScope = "chatgpt.tokens.use.direct"
    public static let scopes = "openid profile email offline_access resource.invoke " + planScope
    public static let resource = "https://api.openai.com/v1"
    /// The model list and Responses on the plan's quota.
    public static let apiBase = URL(string: "https://api.openai.com/v1")!
    /// Where the user checks and manages the plan's usage.
    public static let usagePage = URL(string: "https://chatgpt.com/settings/usage")!
    /// How long a sign-in waits for the browser, and for the steps after the callback.
    public static let timeout: TimeInterval = 300
    public static let finishTimeout: TimeInterval = 20
    static let profileClaim = "https://api.openai.com/profile"
    static let defaultExpiresIn: Int64 = 3600
    static let clockSkewMs: Int64 = 120_000

    /// The refresh token can no longer be used: clear the tokens and sign in again (same client id).
    public static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused"]
    static let deniedErrors: Set<String> = ["access_denied", "consent_required", "login_required", "interaction_required"]
    static let planErrors: Set<String> = ["invalid_scope", "insufficient_scope", "subscription_sharing_user_not_eligible"]

    /// This device's id at OpenAI, made once and then kept: `urn:uuid:` and a lowercase v4 UUID.
    public static func newHostID() -> String { "urn:uuid:" + UUID().uuidString.lowercased() }

    public static func currentTimeMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
}

/// PKCE (RFC 7636) and the callback's random values: new for every sign-in, never stored.
public enum PKCE {
    /// S256: the verifier's SHA-256 in base64url without padding.
    public static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// `bytes` random bytes in base64url; 32 make 43 characters, inside RFC 7636's 43–128.
    public static func randomString(bytes: Int) -> String {
        var data = Data(count: max(1, bytes))
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        if status != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            data = Data((0..<max(1, bytes)).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        }
        return base64URL(data)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}

/// One sign-in's random values, checked again on the callback and the exchange.
public struct ChatGPTSignInAttempt: Equatable, Sendable {
    public let state: String
    public let nonce: String
    public let verifier: String
    /// This attempt's callback address on the loopback listener.
    public let redirectURI: String
    public var challenge: String { PKCE.challenge(verifier) }

    public init(state: String, nonce: String, verifier: String, redirectURI: String) {
        self.state = state; self.nonce = nonce; self.verifier = verifier; self.redirectURI = redirectURI
    }

    /// Like Play: 32 random bytes for the state and the nonce, 48 for the verifier (64 characters).
    public static func make(redirectURI: String) -> Self {
        Self(state: PKCE.randomString(bytes: 32), nonce: PKCE.randomString(bytes: 32),
             verifier: PKCE.randomString(bytes: 48), redirectURI: redirectURI)
    }
}

/// Why a sign-in did not finish; the screen words each reason (Play ModelsCopy.chatGptFailure).
public enum ChatGPTSignInFailure: String, Sendable {
    case denied, stateMismatch, clientMismatch, noClientID, timedOut, exchange, codeExpired, region, blocked
    case idToken, noPlanScope, network
}

public struct ChatGPTSignInError: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: ChatGPTSignInFailure
    /// For people and diagnostics; never a token or an authorization code.
    public let detail: String
    /// The server's error code (not a secret), when it gave one.
    public let code: String?

    public init(_ reason: ChatGPTSignInFailure, detail: String = "", code: String? = nil) {
        self.reason = reason; self.detail = detail; self.code = code
    }

    public var description: String { detail.isEmpty ? reason.rawValue : reason.rawValue + ": " + detail }
}

/// What an exchange or a refresh gave; `scopes` is what was actually granted.
public struct ChatGPTTokenSet: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Int64
    public let scopes: [String]

    public init(accessToken: String, refreshToken: String?, idToken: String?, expiresIn: Int64, scopes: [String]) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken
        self.expiresIn = expiresIn; self.scopes = scopes
    }
}

/// A request that got no usable answer (Play ModelError.Network, Server, BadResponse).
public enum ChatGPTTransportFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case network(String)
    case server(Int)
    case badResponse(String)

    public var description: String {
        switch self {
        case .network(let why): return "network: " + why
        case .server(let status): return "server \(status)"
        case .badResponse(let why): return "bad response: " + why
        }
    }
}

public enum ChatGPTTokenResult: Equatable, Sendable {
    case ok(ChatGPTTokenSet)
    /// `terminal`: this refresh token can't be used again. `nonJSON`: the answer was a web page
    /// (most likely a protection page); the code is then `http_<status>`.
    case rejected(code: String, terminal: Bool, detail: String?, nonJSON: Bool)
    case failed(ChatGPTTransportFailure)
}

/// The identity read from a verified ID token; the email is only shown to people and may be empty.
public struct ChatGPTIdentity: Equatable, Sendable {
    public let sub: String
    public let email: String

    public init(sub: String, email: String) { self.sub = sub; self.email = email }
}

// MARK: - Authorize URL, callback and token requests

extension ChatGPTSignIn {
    /// The authorize page. No `clientID` is the first sign-in: register with the App's name. A later
    /// sign-in names the earlier ID token (expired is fine; none after signing out) and email.
    /// The URL may hold an ID token: never log it.
    public static func authorizeURL(_ attempt: ChatGPTSignInAttempt, clientID: String?, hostID: String,
                                    idTokenHint: String? = nil, loginHint: String? = nil,
                                    issuer: String = issuer) -> URL {
        var items = [("client_id", clientID ?? registerClientID)]
        if clientID == nil { items.append(("agent_name_hint", appName)) }
        items.append(("ext_agent_host_id", hostID))
        if clientID != nil, let hint = idTokenHint, !hint.isEmpty { items.append(("id_token_hint", hint)) }
        if clientID != nil, let hint = loginHint, !hint.isEmpty { items.append(("login_hint", hint)) }
        items += [("response_type", "code"), ("redirect_uri", attempt.redirectURI), ("scope", scopes),
                  ("resource", resource), ("state", attempt.state), ("nonce", attempt.nonce),
                  ("code_challenge_method", "S256"), ("code_challenge", attempt.challenge)]
        return URL(string: issuer + "/api/accounts/authorize?" + formEncode(items))!
    }

    /// The code and the client id to use, from the callback's parameters. The state comes first; a
    /// refusal, another client id than this attempt's, or a first registration without one all throw.
    public static func readCallback(_ params: [String: String], attempt: ChatGPTSignInAttempt,
                                    clientID: String?) throws -> (code: String, clientID: String) {
        guard params["state"] == attempt.state else { throw ChatGPTSignInError(.stateMismatch) }
        if let error = params["error"] {
            // Errors the authorize page sends back: region and plan are worded, the rest is a refusal.
            let reason = failure(code: error, detail: params["error_description"])
            throw ChatGPTSignInError(reason == .region || reason == .noPlanScope ? reason : .denied, detail: error, code: error)
        }
        guard let code = params["code"], !code.isEmpty else {
            throw ChatGPTSignInError(.exchange, detail: "no code", code: "no_code")
        }
        let issued = params["client_id"].flatMap { $0.isEmpty ? nil : $0 }
        if let clientID, let issued, issued != clientID { throw ChatGPTSignInError(.clientMismatch) }
        guard let id = issued ?? clientID else { throw ChatGPTSignInError(.noClientID) }
        return (code, id)
    }

    /// Which plain reason a refusal is (Play ChatGptAuth.failureOf): a protection page (403 or 429
    /// that isn't JSON), an unsupported region, an expired or used code, no consent, the plan or
    /// scope (said by the code or as a whole word in the description); anything else is `.exchange`.
    public static func failure(code: String, detail: String?, nonJSON: Bool = false) -> ChatGPTSignInFailure {
        let text = code + " " + (detail ?? "")
        if nonJSON && (code == "http_403" || code == "http_429") { return .blocked }
        if text.range(of: "unsupported_country|region|territor", options: [.regularExpression, .caseInsensitive]) != nil {
            return .region
        }
        if code == "invalid_grant" { return .codeExpired }
        if deniedErrors.contains(code) { return .denied }
        if planErrors.contains(code) || text.range(of: "(?<![a-z])(plan|subscription|scope)s?(?![a-z])",
                                                    options: [.regularExpression, .caseInsensitive]) != nil {
            return .noPlanScope
        }
        return .exchange
    }

    public static func exchangeRequest(clientID: String, code: String, attempt: ChatGPTSignInAttempt,
                                       issuer: String = issuer) -> URLRequest {
        formRequest(issuer + "/api/accounts/oauth/token", [
            ("grant_type", "authorization_code"), ("client_id", clientID), ("code", code),
            ("code_verifier", attempt.verifier), ("redirect_uri", attempt.redirectURI), ("resource", resource)])
    }

    /// No scope: the refresh keeps what was granted.
    public static func refreshRequest(clientID: String, refreshToken: String, issuer: String = issuer) -> URLRequest {
        formRequest(issuer + "/api/accounts/oauth/token", [
            ("grant_type", "refresh_token"), ("client_id", clientID), ("refresh_token", refreshToken), ("resource", resource)])
    }

    public static func revokeRequest(clientID: String, refreshToken: String, issuer: String = issuer) -> URLRequest {
        formRequest(issuer + "/api/accounts/oauth/revoke", [
            ("token", refreshToken), ("token_type_hint", "refresh_token"), ("client_id", clientID)])
    }

    /// Reads a token endpoint's answer like Play's ChatGptAuth.token().
    public static func tokenResult(status: Int, body: Data) -> ChatGPTTokenResult {
        let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if (500...599).contains(status) { return .failed(.server(status)) }
        if status != 200 {
            let error = root?["error"]
            let code = ((error as? [String: Any])?["code"] as? String) ?? (error as? String)
                ?? (root?["code"] as? String) ?? "http_\(status)"
            let detail = (root?["error_description"] as? String) ?? ((error as? [String: Any])?["message"] as? String)
            return .rejected(code: code, terminal: terminalRefreshErrors.contains(code), detail: detail, nonJSON: root == nil)
        }
        guard let root, let access = root["access_token"] as? String else {
            return .failed(.badResponse("no access_token in the token answer"))
        }
        return .ok(ChatGPTTokenSet(
            accessToken: access, refreshToken: root["refresh_token"] as? String, idToken: root["id_token"] as? String,
            expiresIn: int64(root["expires_in"]) ?? defaultExpiresIn,
            scopes: (root["scope"] as? String)?.split(separator: " ").map(String.init) ?? []))
    }

    static func formRequest(_ url: String, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)
        return request
    }

    /// OkHttp 4.12's query-component and form encoding, which the Play build sends: only
    /// `A–Z a–z 0–9 - . _ *` stay; every other UTF-8 byte is %XX (a space is %20, `+` is %2B).
    static func formEncode(_ fields: [(String, String)]) -> String {
        fields.map { percentEncode($0.0) + "=" + percentEncode($0.1) }.joined(separator: "&")
    }

    static func percentEncode(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var out: [UInt8] = []
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "*"):
                out.append(byte)
            default:
                out += [UInt8(ascii: "%"), hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]]
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// A JSON integer (or an integer written as a string, like kotlinx `longOrNull`); not a Boolean.
    static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            guard double == double.rounded(), abs(double) < 9.2e18 else { return nil }
            return number.int64Value
        }
        if let text = value as? String { return Int64(text) }
        return nil
    }
}

// MARK: - Talking to the issuer

/// The one way the sign-in and the plan's calls reach the network, so checks can stand in a fake.
public protocol ChatGPTHTTP: Sendable {
    /// The status and the whole body; throws only when no answer arrived.
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

public struct URLSessionChatGPTHTTP: ChatGPTHTTP {
    let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTTransportFailure.badResponse("not HTTP") }
        return (http.statusCode, data)
    }
}

/// Exchanges, refreshes and revokes at one issuer and verifies its ID tokens against the published
/// JWKS (RS256), fetched again when a key id is unknown (the issuer rotated its keys).
public final class ChatGPTAuthClient: @unchecked Sendable {
    public let issuer: String
    private let http: any ChatGPTHTTP
    private let lock = NSLock()
    private var jwks: [String: (n: String, e: String)] = [:]

    public init(http: any ChatGPTHTTP = URLSessionChatGPTHTTP(), issuer: String = ChatGPTSignIn.issuer) {
        self.http = http; self.issuer = issuer
    }

    public func exchange(clientID: String, code: String, attempt: ChatGPTSignInAttempt) async throws -> ChatGPTTokenResult {
        try await token(ChatGPTSignIn.exchangeRequest(clientID: clientID, code: code, attempt: attempt, issuer: issuer))
    }

    public func refresh(clientID: String, refreshToken: String) async throws -> ChatGPTTokenResult {
        try await token(ChatGPTSignIn.refreshRequest(clientID: clientID, refreshToken: refreshToken, issuer: issuer))
    }

    /// True when the issuer confirmed (HTTP 200, also for a token that was already dead).
    /// Revoking keeps the registered client.
    public func revoke(clientID: String, refreshToken: String) async -> Bool {
        let request = ChatGPTSignIn.revokeRequest(clientID: clientID, refreshToken: refreshToken, issuer: issuer)
        guard let answer = try? await http.send(request) else { return false }
        return answer.status == 200
    }

    /// Only cancellation throws; every other failure is a result.
    private func token(_ request: URLRequest) async throws -> ChatGPTTokenResult {
        do {
            let answer = try await http.send(request)
            return ChatGPTSignIn.tokenResult(status: answer.status, body: answer.body)
        } catch {
            try Task.checkCancellation()
            return .failed(.network(String(describing: type(of: error))))
        }
    }

    /// Checks the signature, issuer, audience (the client id), expiry (two minutes of skew) and this
    /// attempt's nonce; gives the identity, or throws `.idToken`.
    public func verifyIDToken(_ idToken: String, clientID: String, nonce: String, nowMs: Int64) async throws -> ChatGPTIdentity {
        func failure(_ why: String) -> ChatGPTSignInError { ChatGPTSignInError(.idToken, detail: why) }
        let pieces = idToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 3 else { throw failure("not a JWT") }
        guard let header = Self.json(pieces[0]) else { throw failure("bad header") }
        guard let claims = Self.json(pieces[1]) else { throw failure("bad payload") }
        guard let algorithm = header["alg"] as? String, algorithm == "RS256" else {
            throw failure("alg " + ((header["alg"] as? String) ?? "missing"))
        }
        let kid = header["kid"] as? String
        var key = try await jwk(kid, refresh: false)
        if key == nil { key = try await jwk(kid, refresh: true) }
        guard let key else { throw failure("unknown key") }
        guard let signature = PKCE.base64URLDecode(pieces[2]), let modulus = PKCE.base64URLDecode(key.n),
              let exponent = PKCE.base64URLDecode(key.e),
              ChatGPTSignIn.verifyRS256(Data((pieces[0] + "." + pieces[1]).utf8), signature: signature,
                                        modulus: modulus, exponent: exponent) else { throw failure("signature") }
        guard claims["iss"] as? String == issuer else { throw failure("issuer") }
        let audience = claims["aud"]
        guard (audience as? String) == clientID || ((audience as? [Any])?.contains { ($0 as? String) == clientID } ?? false) else {
            throw failure("audience")
        }
        guard let expiry = ChatGPTSignIn.int64(claims["exp"]) else { throw failure("no exp") }
        guard expiry * 1000 + ChatGPTSignIn.clockSkewMs >= nowMs else { throw failure("expired") }
        guard claims["nonce"] as? String == nonce else { throw failure("nonce") }
        guard let sub = claims["sub"] as? String, !sub.isEmpty else { throw failure("no sub") }
        let email = (claims["email"] as? String)
            ?? ((claims[ChatGPTSignIn.profileClaim] as? [String: Any])?["email"] as? String) ?? ""
        return ChatGPTIdentity(sub: sub, email: email)
    }

    private func jwk(_ kid: String?, refresh: Bool) async throws -> (n: String, e: String)? {
        if refresh || locked({ jwks.isEmpty }) {
            let body: Data
            do {
                body = try await http.send(URLRequest(url: URL(string: issuer + "/.well-known/jwks.json")!)).body
            } catch {
                try Task.checkCancellation()
                throw ChatGPTSignInError(.network, detail: "jwks")
            }
            let keys = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["keys"] as? [Any] ?? []
            var table: [String: (n: String, e: String)] = [:]
            for case let key as [String: Any] in keys where key["kty"] as? String == "RSA" {
                table[(key["kid"] as? String) ?? ""] = ((key["n"] as? String) ?? "", (key["e"] as? String) ?? "")
            }
            locked { jwks = table }
        }
        return locked {
            if let kid { return jwks[kid] }
            return jwks.count == 1 ? jwks.values.first : nil
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func json(_ part: String) -> [String: Any]? {
        guard let data = PKCE.base64URLDecode(part) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension ChatGPTSignIn {
    static func verifyRS256(_ signingInput: Data, signature: Data, modulus: Data, exponent: Data) -> Bool {
        guard let key = rsaPublicKey(modulus: modulus, exponent: exponent) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, signingInput as CFData, signature as CFData, nil)
    }

    /// An RSA public key from a JWK's numbers, as PKCS #1 DER: SEQUENCE { INTEGER n, INTEGER e }.
    static func rsaPublicKey(modulus: Data, exponent: Data) -> SecKey? {
        func integer(_ raw: Data) -> Data {
            var bytes = Array(raw.drop { $0 == 0 })
            if bytes.isEmpty { bytes = [0] }
            if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
            return der(0x02, Data(bytes))
        }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(der(0x30, integer(modulus) + integer(exponent)) as CFData, attributes as CFDictionary, nil)
    }

    static func der(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        if content.count < 0x80 {
            out.append(UInt8(content.count))
        } else {
            var length: [UInt8] = []
            var remaining = content.count
            while remaining > 0 { length.insert(UInt8(remaining & 0xFF), at: 0); remaining >>= 8 }
            out.append(0x80 | UInt8(length.count))
            out.append(contentsOf: length)
        }
        out.append(content)
        return out
    }
}

// MARK: - The saved sign-in and its tokens

/// One ChatGPT account's sign-in (Play ChatGptSession): the registered client id, the verified
/// identity and the tokens. It is kept whole where a provider's API key is kept (the provider's item
/// in the model-credentials Keychain service). Signing out clears only the tokens; the client id and
/// the identity stay, so signing in again reuses the registration.
public struct ChatGPTSession: Codable, Equatable, Sendable {
    public var clientId: String
    public var sub: String
    public var email: String
    public var accessToken: String
    public var refreshToken: String
    public var idToken: String
    public var expiresAtMs: Int64
    public var scopes: [String]

    public init(clientId: String, sub: String, email: String = "", accessToken: String = "", refreshToken: String = "",
                idToken: String = "", expiresAtMs: Int64 = 0, scopes: [String] = []) {
        self.clientId = clientId; self.sub = sub; self.email = email; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.idToken = idToken; self.expiresAtMs = expiresAtMs; self.scopes = scopes
    }

    public var signedIn: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }
    /// The user allowed calls on the plan's quota.
    public var planUsage: Bool { scopes.contains(ChatGPTSignIn.planScope) }

    public func signedOut() -> Self {
        var session = self
        session.accessToken = ""; session.refreshToken = ""; session.idToken = ""; session.expiresAtMs = 0
        return session
    }

    private enum CodingKeys: String, CodingKey {
        case clientId, sub, email, accessToken, refreshToken, idToken, expiresAtMs, scopes
    }

    /// Also reads Play's JSON, which leaves out fields still at their defaults.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try values.decode(String.self, forKey: .clientId)
        sub = try values.decode(String.self, forKey: .sub)
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try values.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        idToken = try values.decodeIfPresent(String.self, forKey: .idToken) ?? ""
        expiresAtMs = try values.decodeIfPresent(Int64.self, forKey: .expiresAtMs) ?? 0
        scopes = try values.decodeIfPresent([String].self, forKey: .scopes) ?? []
    }
}

/// How the plan's calls end (the Play ModelError cases ResponsesModel and ChatGptTokens raise).
public enum ChatGPTModelError: Error, Equatable, Sendable {
    /// The sign-in is gone (refresh token dead or missing): sign in again.
    case signInExpired
    case auth
    /// The account may not use its plan in other apps (or the plan scope was taken away).
    case notEligible(String)
    /// The plan's usage limit; not retried.
    case limitReached
    case server(Int)
    case network(String)
    case badResponse(String)
    /// The stream ended before `response.completed`; may be retried.
    case streamCut
    case contentRefused
    case contextTooLong
    case quotaExceeded
    case rateLimited(retryAfterMs: Int64?)
    case modelNotFound(String)

    init(_ failure: ChatGPTTransportFailure) {
        switch failure {
        case .network(let why): self = .network(why)
        case .server(let status): self = .server(status)
        case .badResponse(let why): self = .badResponse(why)
        }
    }
}

/// The access token for a call (Play ChatGptTokens): refreshed when it expires within five minutes
/// or after the server refused it (`fresh`), and the rotated pair is saved together. One refresh at
/// a time: a refresh token works once, so concurrent refreshes would sign each other out.
public actor ChatGPTTokens {
    private let auth: ChatGPTAuthClient
    private let load: @Sendable () -> ChatGPTSession?
    private let save: @Sendable (ChatGPTSession) -> Void
    private let nowMs: @Sendable () -> Int64
    private let refreshAheadMs: Int64
    private var refreshing: Task<String, Error>?

    public init(auth: ChatGPTAuthClient, load: @escaping @Sendable () -> ChatGPTSession?,
                save: @escaping @Sendable (ChatGPTSession) -> Void,
                nowMs: @escaping @Sendable () -> Int64 = { ChatGPTSignIn.currentTimeMs() }, refreshAheadMs: Int64 = 300_000) {
        self.auth = auth; self.load = load; self.save = save; self.nowMs = nowMs; self.refreshAheadMs = refreshAheadMs
    }

    /// A dead refresh token clears the tokens and throws `.signInExpired`; a network or server
    /// failure throws and keeps them.
    public func token(fresh: Bool) async throws -> String {
        if let refreshing { return try await refreshing.value }
        guard let session = load(), session.signedIn else { throw ChatGPTModelError.signInExpired }
        if !fresh, !session.accessToken.isEmpty, nowMs() < session.expiresAtMs - refreshAheadMs { return session.accessToken }
        guard !session.refreshToken.isEmpty else {
            save(session.signedOut())
            throw ChatGPTModelError.signInExpired
        }
        let task = Task { try await self.refresh(session) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func refresh(_ session: ChatGPTSession) async throws -> String {
        switch try await auth.refresh(clientID: session.clientId, refreshToken: session.refreshToken) {
        case .ok(let tokens):
            var next = session
            next.accessToken = tokens.accessToken
            next.refreshToken = tokens.refreshToken ?? session.refreshToken
            next.idToken = tokens.idToken ?? session.idToken
            next.expiresAtMs = nowMs() + tokens.expiresIn * 1000
            next.scopes = tokens.scopes.isEmpty ? session.scopes : tokens.scopes
            save(next)
            guard next.planUsage else { throw ChatGPTModelError.notEligible("") }
            return next.accessToken
        case .rejected(_, let terminal, _, _):
            if terminal {
                save(session.signedOut())
                throw ChatGPTModelError.signInExpired
            }
            // A client configuration problem and the like: retrying won't help, but the token isn't dead.
            throw ChatGPTModelError.auth
        case .failed(let failure):
            throw ChatGPTModelError(failure)
        }
    }
}

// MARK: - The whole sign-in

extension ChatGPTSignIn {
    /// One sign-in (Play signInWithChatGpt). The listener is open already: the screen owns it so it can
    /// listen again after iOS took the socket away from a suspended App. Opens the authorize page,
    /// waits for the callback, then checks it, exchanges the code, verifies the ID token and the plan
    /// scope (at most `finishTimeout`) before `page` answers the browser (nil: signed in).
    /// `clientID` is the registered one (nil the first time); `onRegistered` gets a new one before the
    /// exchange, to be stored even if the exchange fails. `previous` gives the ID-token and email hints.
    public static func signIn(auth: ChatGPTAuthClient, server: LoopbackCallbackServer, hostID: String, clientID: String?,
                              previous: ChatGPTSession?, openBrowser: @Sendable (URL) async -> Void,
                              onRegistered: @escaping @Sendable (String) -> Void,
                              page: @escaping @Sendable (ChatGPTSignInError?) -> String,
                              timeout: TimeInterval = ChatGPTSignIn.timeout, finishTimeout: TimeInterval = ChatGPTSignIn.finishTimeout,
                              nowMs: @escaping @Sendable () -> Int64 = { ChatGPTSignIn.currentTimeMs() }) async throws -> ChatGPTSession {
        let attempt = ChatGPTSignInAttempt.make(redirectURI: server.redirectURI)
        let hint = previous.flatMap { $0.signedIn && $0.clientId == clientID ? $0 : nil }
        let url = authorizeURL(attempt, clientID: clientID, hostID: hostID, idTokenHint: hint?.idToken,
                               loginHint: clientID == nil ? nil : previous?.email, issuer: auth.issuer)
        let outcome = SignInOutcome()
        async let callback = server.waitForCallback(timeout: timeout, accept: { $0["state"] == attempt.state }) { params in
            let result: Result<ChatGPTSession, ChatGPTSignInError>
            do {
                result = .success(try await withDeadline(finishTimeout) {
                    try await completeSignIn(auth: auth, params: params, attempt: attempt, clientID: clientID,
                                             onRegistered: onRegistered, nowMs: nowMs)
                })
            } catch let error as ChatGPTSignInError {
                result = .failure(error)
            } catch is DeadlineExceeded {
                result = .failure(ChatGPTSignInError(.network, detail: "no answer in \(Int(finishTimeout))s"))
            } catch {
                result = .failure(ChatGPTSignInError(.network, detail: String(describing: type(of: error))))
            }
            outcome.set(result)
            if case .failure(let error) = result { return page(error) }
            return page(nil)
        }
        await openBrowser(url)
        guard await callback != nil, let result = outcome.get() else {
            try Task.checkCancellation()
            throw ChatGPTSignInError(.timedOut)
        }
        return try result.get()
    }

    static func completeSignIn(auth: ChatGPTAuthClient, params: [String: String], attempt: ChatGPTSignInAttempt,
                               clientID: String?, onRegistered: @Sendable (String) -> Void,
                               nowMs: @Sendable () -> Int64) async throws -> ChatGPTSession {
        let (code, issued) = try readCallback(params, attempt: attempt, clientID: clientID)
        if issued != clientID { onRegistered(issued) }
        let tokens: ChatGPTTokenSet
        switch try await auth.exchange(clientID: issued, code: code, attempt: attempt) {
        case .ok(let set):
            tokens = set
        case .rejected(let code, _, let detail, let nonJSON):
            throw ChatGPTSignInError(failure(code: code, detail: detail, nonJSON: nonJSON),
                                     detail: [code, detail].compactMap { $0 }.joined(separator: " — "), code: code)
        case .failed(let failure):
            throw ChatGPTSignInError(.network, detail: failure.description)
        }
        guard let idToken = tokens.idToken else { throw ChatGPTSignInError(.idToken, detail: "no id_token") }
        let identity = try await auth.verifyIDToken(idToken, clientID: issued, nonce: attempt.nonce, nowMs: nowMs())
        guard tokens.scopes.contains(planScope) else {
            throw ChatGPTSignInError(.noPlanScope, detail: "scope", code: "no_plan_scope")
        }
        return ChatGPTSession(clientId: issued, sub: identity.sub, email: identity.email, accessToken: tokens.accessToken,
                              refreshToken: tokens.refreshToken ?? "", idToken: idToken,
                              expiresAtMs: nowMs() + tokens.expiresIn * 1000, scopes: tokens.scopes)
    }

    struct DeadlineExceeded: Error {}

    /// `body`'s value, or `DeadlineExceeded` after `seconds` (the body is cancelled).
    static func withDeadline<T: Sendable>(_ seconds: TimeInterval,
                                          _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard case let value?? = try await group.next() else { throw DeadlineExceeded() }
            return value
        }
    }

    private final class SignInOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<ChatGPTSession, ChatGPTSignInError>?
        func set(_ value: Result<ChatGPTSession, ChatGPTSignInError>) { lock.lock(); result = value; lock.unlock() }
        func get() -> Result<ChatGPTSession, ChatGPTSignInError>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }
    }
}

// MARK: - The plan's model list

/// One model the plan offers. Nil means the list did not say.
public struct ChatGPTListedModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let vision: Bool?
    public let contextTokens: Int?
    public let reasoningEfforts: [String]?

    public init(id: String, displayName: String, vision: Bool?, contextTokens: Int?, reasoningEfforts: [String]?) {
        self.id = id; self.displayName = displayName; self.vision = vision
        self.contextTokens = contextTokens; self.reasoningEfforts = reasoningEfforts
    }
}

extension ChatGPTSignIn {
    /// `GET {base}/models` with the access token (Play ModelCatalog.openAiCompat).
    public static func modelsRequest(accessToken: String, base: URL = apiBase, userAgent: String? = nil) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        return request
    }

    /// The plan answers with a `models` table: the name in `slug`, the label in `display_name`, only
    /// `visibility: list` kept, in the server's order; `input_modalities`, `context_window` and
    /// `supported_reasoning_levels` fill what they say. Nil: not a model list.
    public static func listedModels(_ body: Data) -> [ChatGPTListedModel]? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let entries = (root["data"] ?? root["models"]) as? [Any] else { return nil }
        var seen = Set<String>()
        var models: [ChatGPTListedModel] = []
        for case let entry as [String: Any] in entries {
            if let visibility = entry["visibility"] as? String, visibility != "list" { continue }
            guard let id = ((entry["id"] as? String) ?? (entry["slug"] as? String)),
                  !id.trimmingCharacters(in: .whitespaces).isEmpty, seen.insert(id).inserted else { continue }
            let inputs = (((entry["modalities"] as? [String: Any])?["input"]) ?? entry["input_modalities"]) as? [Any]
            let vision = inputs.map { list in
                list.contains { item in (item as? String).map { $0 == "image" || $0.hasPrefix("image/") } ?? false }
            }
            let context = [entry["context_length"], entry["context_window"], entry["max_context_length"]]
                .lazy.compactMap { int64($0) }.first.map { Int($0) }
            let efforts = (entry["supported_reasoning_levels"] as? [Any]).map { levels -> [String] in
                var names: [String] = []
                for level in levels {
                    let raw = ((level as? [String: Any])?["effort"] ?? level) as? String
                    if let name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty, !names.contains(name) { names.append(name) }
                }
                return names
            }
            models.append(ChatGPTListedModel(id: id, displayName: (entry["name"] as? String) ?? (entry["display_name"] as? String) ?? "",
                                             vision: vision, contextTokens: context, reasoningEfforts: efforts))
        }
        return models
    }
}
