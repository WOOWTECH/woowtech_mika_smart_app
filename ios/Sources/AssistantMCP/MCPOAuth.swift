import AssistantModels
import Foundation

/// An MCP server's OAuth 2.1 sign-in, as the MCP authorization spec asks and like the Android
/// edition (core/cap/mcp/McpOAuth.kt @a7439e1a): protected resource metadata (RFC 9728) names the
/// authorization server, whose metadata (RFC 8414) gives its endpoints; the App registers itself
/// (RFC 7591) as a public client, or uses a client the user registered and entered; then an
/// authorization code with PKCE (S256), `state` and the server as `resource` (RFC 8707). The
/// redirect is the loopback listener (LoopbackCallbackServer), as for ChatGPT.
///
/// Differences from Android, as the specs ask: the 401 challenge's `resource_metadata` is tried
/// first, then the path, then the root well-known; authorization server metadata counts only when
/// its issuer is the authorization server's (RFC 8414 §3.3); and an authorization server without a
/// registration endpoint takes a client the user entered instead of failing.
///
/// TODO: Client ID Metadata Documents (the 2025-11-25 spec's other way to name a client without
/// registering) need a client document hosted on the web; they are not supported yet.
///
/// Only HTTPS is used, or HTTP on this device's loopback address (the checks' fake servers).
/// Nothing here logs; an error carries a server's error code at most, never a token, code or secret.
/// Settings › MCP 伺服器 › 登入 runs it (MCPSession); scripts/CheckMCPOAuth.swift checks it offline.
public enum MCPOAuth {
    /// The name consent pages show, as for ChatGPT.
    public static let clientName = ChatGPTSignIn.appName
    /// How long a sign-in looks for the server's settings and registers, waits for the browser,
    /// and takes for the steps after the callback.
    public static let discoveryTimeout: TimeInterval = 30
    public static let timeout: TimeInterval = 300
    public static let finishTimeout: TimeInterval = 20
    /// Android refreshes a minute before the tokens expire; so does iOS.
    public static let refreshAheadMs: Int64 = 60_000
    /// A token whose answer gave no lifetime is used until the server refuses it, then refreshed.
    public static let noExpiry = Int64.max
    static let maximumTokenBytes = 16 * 1024
    static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "[::1]", "localhost"]
}

// MARK: - Failures

/// Why a sign-in did not finish; the server's page words each one.
public enum MCPOAuthFailure: String, Sendable {
    /// The server's sign-in settings are missing or unusable (no metadata, no endpoints, no PKCE).
    case setup
    /// An address the settings named is not HTTPS, or names another server than this one.
    case insecure
    /// The authorization server registers no apps, and the user entered no client.
    case noRegistration
    /// The registration endpoint refused.
    case registration
    /// The authorization page refused, or the person cancelled there.
    case denied
    /// The callback belongs to another sign-in (`state`) or another server (`iss`).
    case mismatch
    case timedOut
    /// The token endpoint refused the code.
    case exchange
    case network
}

public struct MCPOAuthError: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: MCPOAuthFailure
    /// The server's error code (not a secret), when it gave one.
    public let code: String?
    /// For diagnostics; never a token, code, secret or address.
    public let detail: String

    public init(_ reason: MCPOAuthFailure, code: String? = nil, detail: String = "") {
        self.reason = reason; self.code = code; self.detail = detail
    }

    public var description: String {
        [reason.rawValue, code, detail.isEmpty ? nil : detail].compactMap { $0 }.joined(separator: ": ")
    }
}

// MARK: - Discovery

/// What discovery found: the authorization server's endpoints and what to ask it for.
public struct MCPOAuthServer: Equatable, Sendable {
    /// RFC 8707: the MCP server the tokens are for, sent with every authorization and token request.
    public let resource: String
    /// The authorization server's metadata `issuer`, which an `iss` in the callback must match.
    public let issuer: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    /// Nil: the server registers no apps, so the user enters a client.
    public let registrationEndpoint: URL?
    /// The 401 challenge's scope, else the resource metadata's `scopes_supported`; nil asks for none.
    public let scope: String?
    /// RFC 9207: the authorization response always carries `iss`.
    public let issParameter: Bool
    /// `token_endpoint_auth_methods_supported`, for a client with a secret.
    public let tokenAuthMethods: [String]?

    public init(resource: String, issuer: String?, authorizationEndpoint: URL, tokenEndpoint: URL, registrationEndpoint: URL?,
                scope: String?, issParameter: Bool, tokenAuthMethods: [String]?) {
        self.resource = resource; self.issuer = issuer; self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint; self.registrationEndpoint = registrationEndpoint; self.scope = scope
        self.issParameter = issParameter; self.tokenAuthMethods = tokenAuthMethods
    }
}

extension MCPOAuth {
    /// Finds the authorization server the way the MCP spec orders it. The resource metadata comes
    /// from (a) the `resource_metadata` of the 401 an unauthenticated request gets, (b) the
    /// well-known address with the endpoint's path, (c) the one at the root; without any, the
    /// server's own origin is the authorization server (the 2025-03-26 spec, like Android). Its
    /// metadata is the first 200 answer of `authorizationServerMetadataURLs` whose issuer is that
    /// authorization server's (`sameIssuer`); a document naming another issuer is passed over.
    public static func discover(endpoint: URL, http: MCPOAuthHTTP) async throws -> MCPOAuthServer {
        let challenge = try await probe(endpoint, http: http)
        let protected = try await firstMetadata(resourceMetadataURLs(endpoint: endpoint, challenge: challenge), http: http)
        var resource = canonicalResource(endpoint)
        var issuer = origin(endpoint)?.absoluteString
        if let protected {
            // RFC 9728 §3.3: metadata about another server is not used.
            if let named = protected["resource"] as? String {
                guard let url = allowed(named), covers(url, endpoint) else { throw MCPOAuthError(.insecure, detail: "resource") }
                resource = named
            }
            guard let first = (protected["authorization_servers"] as? [Any])?.first as? String else {
                throw MCPOAuthError(.setup, detail: "no authorization_servers")
            }
            guard allowed(first) != nil else { throw MCPOAuthError(.insecure, detail: "authorization server") }
            issuer = first.trimmingCharacters(in: .whitespaces)
        }
        guard let issuer, let issuerURL = allowed(issuer),
              let metadata = try await firstMetadata(authorizationServerMetadataURLs(issuer: issuerURL), http: http,
                                                     where: { sameIssuer($0["issuer"] as? String, issuer) }) else {
            throw MCPOAuthError(.setup, detail: "no authorization server metadata for its issuer")
        }
        func address(_ key: String) throws -> URL? {
            guard let text = metadata[key] as? String else { return nil }
            guard let url = allowed(text) else { throw MCPOAuthError(.insecure, detail: key) }
            return url
        }
        guard let authorization = try address("authorization_endpoint"), let token = try address("token_endpoint") else {
            throw MCPOAuthError(.setup, detail: "no authorization or token endpoint")
        }
        let registration = try address("registration_endpoint")
        func strings(_ value: Any?) -> [String]? { (value as? [Any])?.compactMap { $0 as? String } }
        // An absent list says nothing; a list without S256 or the code flow can't be used safely.
        if let methods = strings(metadata["code_challenge_methods_supported"]), !methods.contains("S256") {
            throw MCPOAuthError(.setup, detail: "no S256")
        }
        if let types = strings(metadata["response_types_supported"]), !types.contains("code") {
            throw MCPOAuthError(.setup, detail: "no code flow")
        }
        let supported = strings(protected?["scopes_supported"])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let scope = challenge?.scope.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? supported.flatMap { $0.isEmpty ? nil : $0.joined(separator: " ") }
        return MCPOAuthServer(resource: resource, issuer: metadata["issuer"] as? String, authorizationEndpoint: authorization,
                              tokenEndpoint: token, registrationEndpoint: registration, scope: scope,
                              issParameter: (metadata["authorization_response_iss_parameter_supported"] as? Bool) == true,
                              tokenAuthMethods: strings(metadata["token_endpoint_auth_methods_supported"]))
    }

    /// The challenge an unauthenticated `initialize` gets; nil without a 401 or an answer.
    static func probe(_ endpoint: URL, http: MCPOAuthHTTP) async throws -> MCPBearerChallenge? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("WoowAssistant/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("1"), "method": .string("initialize"),
            "params": .object(["protocolVersion": .string("2025-03-26"), "capabilities": .object([:]),
                               "clientInfo": .object(["name": .string("WoowAssistant-iOS"), "version": .string("0.1")])])
        ]))
        do {
            let answer = try await http.send(request)
            return answer.status == 401 ? MCPBearerChallenge(answer.challenge) : nil
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    /// RFC 9728 §3.1: the challenge's address, then the well-known address with the endpoint's path,
    /// then the one at the root. An address that is not HTTPS is skipped.
    static func resourceMetadataURLs(endpoint: URL, challenge: MCPBearerChallenge?) -> [URL] {
        let candidates = [allowed(challenge?.resourceMetadata), wellKnown("oauth-protected-resource", before: endpoint),
                          wellKnown("oauth-protected-resource", before: endpoint, path: false)]
        return unique(candidates.compactMap { $0 })
    }

    /// The MCP spec's order for an issuer with a path: RFC 8414 path insertion, OpenID Connect
    /// Discovery with the same insertion, then after the path; without a path, both at the root.
    static func authorizationServerMetadataURLs(issuer: URL) -> [URL] {
        let candidates = [wellKnown("oauth-authorization-server", before: issuer),
                          wellKnown("openid-configuration", before: issuer),
                          path(of: issuer).isEmpty ? nil : wellKnown("openid-configuration", after: issuer)]
        return unique(candidates.compactMap { $0 })
    }

    /// RFC 8414 §3.2 and RFC 9728 §3.2: only a 200 answer with a JSON object is metadata. A
    /// redirect is not followed, and a failed or missing one, or one `usable` refuses, goes on to
    /// the next address.
    static func firstMetadata(_ urls: [URL], http: MCPOAuthHTTP,
                              where usable: ([String: Any]) -> Bool = { _ in true }) async throws -> [String: Any]? {
        for url in urls {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let answer: MCPOAuthAnswer
            do { answer = try await http.send(request) }
            catch {
                try Task.checkCancellation()
                continue
            }
            if answer.status == 200, let found = object(answer.body), usable(found) { return found }
        }
        return nil
    }

    /// RFC 8414 §3.3 and OpenID Connect Discovery 1.0 §4.3: authorization server metadata is used
    /// only when its `issuer` is identical to the issuer its address was built from (the resource
    /// metadata's authorization server, or the server's origin), give or take one trailing slash.
    /// So an MCP host's own metadata (Higgsfield's mcp.higgsfield.ai) never stands in for the
    /// authorization server the resource metadata names (higgsfield.ai/_clerk).
    static func sameIssuer(_ found: String?, _ expected: String) -> Bool {
        guard let found else { return false }
        return found == expected || found == expected + "/" || found + "/" == expected
    }
}

// MARK: - Addresses

extension MCPOAuth {
    /// HTTPS, or HTTP on this device's loopback address; no user info or fragment.
    public static func allowed(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil, let url = parts.url else { return nil }
        guard scheme == "https" || (scheme == "http" && loopbackHosts.contains(host)) else { return nil }
        return url
    }

    /// RFC 8707 and the MCP spec's canonical server address: the scheme and host in lowercase, the
    /// path without a trailing slash. The query stays out: the App keeps a query as part of the
    /// credential, and the authorization server has no need of it.
    static func canonicalResource(_ endpoint: URL) -> String {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return endpoint.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.percentEncodedHost = parts.percentEncodedHost?.lowercased()
        parts.percentEncodedPath = path(of: endpoint)
        parts.percentEncodedQuery = nil
        parts.fragment = nil
        return parts.url?.absoluteString ?? endpoint.absoluteString
    }

    /// Whether resource metadata naming `resource` is about `endpoint`: the same origin, and a path
    /// the endpoint's path is in (the TypeScript SDK's checkResourceAllowed).
    static func covers(_ resource: URL, _ endpoint: URL) -> Bool {
        guard let own = origin(resource), let other = origin(endpoint), own == other else { return false }
        let base = path(of: resource), path = path(of: endpoint)
        return base.isEmpty || path == base || path.hasPrefix(base + "/")
    }

    static func origin(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.percentEncodedHost = parts.percentEncodedHost?.lowercased()
        parts.percentEncodedPath = ""
        parts.percentEncodedQuery = nil
        parts.fragment = nil
        return parts.url
    }

    /// The URL's path without its trailing slashes ("" for the root).
    static func path(of url: URL) -> String {
        var path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// `/.well-known/<name>` between the host and the path (RFC 8414 §3.1, RFC 9728 §3.1), or at
    /// the root; no query.
    static func wellKnown(_ name: String, before url: URL, path keepsPath: Bool = true) -> URL? {
        guard let origin = origin(url) else { return nil }
        return URL(string: origin.absoluteString + "/.well-known/" + name + (keepsPath ? path(of: url) : ""))
    }

    /// OpenID Connect Discovery 1.0 §4: after the issuer's path.
    static func wellKnown(_ name: String, after url: URL) -> URL? {
        guard let origin = origin(url) else { return nil }
        return URL(string: origin.absoluteString + path(of: url) + "/.well-known/" + name)
    }

    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    static func object(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

// MARK: - The client

/// The client a sign-in uses: registered by the App (RFC 7591), or registered by the user and
/// entered on the server's page. `auth` is how the token endpoint authenticates it.
public struct MCPOAuthRegistration: Equatable, Sendable {
    public let id: String
    /// Empty for a public client.
    public let secret: String
    /// "none", "client_secret_post" or "client_secret_basic".
    public let auth: String

    public init(id: String, secret: String = "", auth: String = "none") {
        self.id = id; self.secret = secret; self.auth = auth
    }
}

extension MCPOAuth {
    /// A public client: no secret, `token_endpoint_auth_method` none, the loopback redirect.
    static func registrationRequest(_ endpoint: URL, redirectURI: String, scope: String?) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["client_name": clientName, "redirect_uris": [redirectURI],
                                   "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
                                   "token_endpoint_auth_method": "none"]
        if let scope { body["scope"] = scope }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Registers the App for this sign-in's redirect. A server that hands out a secret anyway gets
    /// it back on the token requests, the way it said to.
    public static func register(_ server: MCPOAuthServer, redirectURI: String, http: MCPOAuthHTTP) async throws -> MCPOAuthRegistration {
        guard let endpoint = server.registrationEndpoint else { throw MCPOAuthError(.noRegistration) }
        let answer: MCPOAuthAnswer
        do { answer = try await http.send(registrationRequest(endpoint, redirectURI: redirectURI, scope: server.scope)) }
        catch {
            try Task.checkCancellation()
            throw MCPOAuthError(.network, detail: "registration")
        }
        let root = object(answer.body)
        guard (200...299).contains(answer.status) else {
            let code = (root?["error"] as? String) ?? "http_\(answer.status)"
            throw MCPOAuthError((500...599).contains(answer.status) ? .network : .registration, code: code)
        }
        guard let id = root?["client_id"] as? String, !id.isEmpty else { throw MCPOAuthError(.registration, code: "no_client_id") }
        let secret = (root?["client_secret"] as? String) ?? ""
        return MCPOAuthRegistration(id: id, secret: secret,
                                    auth: clientAuth(secret: secret, registered: root?["token_endpoint_auth_method"] as? String,
                                                     supported: server.tokenAuthMethods))
    }

    /// How a client with `secret` authenticates: what its registration said, else what the server
    /// supports (RFC 8414: client_secret_basic when it does not say).
    static func clientAuth(secret: String, registered: String?, supported: [String]?) -> String {
        guard !secret.isEmpty else { return "none" }
        let methods = ["client_secret_basic", "client_secret_post"]
        if let registered, methods.contains(registered) { return registered }
        return methods.first { (supported ?? ["client_secret_basic"]).contains($0) } ?? "client_secret_basic"
    }
}

// MARK: - Authorize, callback and tokens

extension MCPOAuth {
    /// The authorize page: the code flow with PKCE (S256), `state`, the server as `resource` and the
    /// scope, added to any query the endpoint already has (RFC 6749 §3.1).
    public static func authorizeURL(_ server: MCPOAuthServer, clientID: String, attempt: ChatGPTSignInAttempt) -> URL? {
        var items = [("response_type", "code"), ("client_id", clientID), ("redirect_uri", attempt.redirectURI),
                     ("code_challenge", attempt.challenge), ("code_challenge_method", "S256"), ("state", attempt.state),
                     ("resource", server.resource)]
        if let scope = server.scope { items.append(("scope", scope)) }
        guard var parts = URLComponents(url: server.authorizationEndpoint, resolvingAgainstBaseURL: false) else { return nil }
        let query = ChatGPTSignIn.formEncode(items)
        parts.percentEncodedQuery = parts.percentEncodedQuery.map { $0.isEmpty ? query : $0 + "&" + query } ?? query
        return parts.url
    }

    /// The code from the callback. The state comes first, then the issuer (RFC 9207: an `iss` must be
    /// the server's, and a server that promised one must send it); a refusal or no code throws.
    public static func readCallback(_ params: [String: String], attempt: ChatGPTSignInAttempt,
                                    server: MCPOAuthServer) throws -> String {
        guard params["state"] == attempt.state else { throw MCPOAuthError(.mismatch, code: "state_mismatch") }
        if let iss = params["iss"] {
            guard iss == server.issuer else { throw MCPOAuthError(.mismatch, code: "iss_mismatch") }
        } else if server.issParameter {
            throw MCPOAuthError(.mismatch, code: "iss_missing")
        }
        if let error = params["error"] { throw MCPOAuthError(.denied, code: error) }
        guard let code = params["code"], !code.isEmpty else { throw MCPOAuthError(.exchange, code: "no_code") }
        return code
    }

    /// A form to the token endpoint, the client authenticated the way it was registered.
    static func tokenRequest(_ endpoint: URL, _ fields: [(String, String)], client: MCPOAuthRegistration) -> URLRequest {
        var fields = fields
        switch client.auth {
        case "client_secret_basic": break
        case "client_secret_post": fields += [("client_id", client.id), ("client_secret", client.secret)]
        default: fields.append(("client_id", client.id))
        }
        var request = ChatGPTSignIn.formRequest(endpoint.absoluteString, fields)
        if client.auth == "client_secret_basic" {
            // RFC 6749 §2.3.1: the id and the secret form-encoded, then Base64.
            let pair = ChatGPTSignIn.percentEncode(client.id) + ":" + ChatGPTSignIn.percentEncode(client.secret)
            request.setValue("Basic " + Data(pair.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func exchangeRequest(_ server: MCPOAuthServer, client: MCPOAuthRegistration, code: String,
                                attempt: ChatGPTSignInAttempt) -> URLRequest {
        tokenRequest(server.tokenEndpoint, [("grant_type", "authorization_code"), ("code", code),
                                            ("redirect_uri", attempt.redirectURI), ("code_verifier", attempt.verifier),
                                            ("resource", server.resource)], client: client)
    }

    /// No scope: the refresh keeps what was granted.
    static func refreshRequest(_ session: MCPOAuthSession, endpoint: URL) -> URLRequest {
        var fields = [("grant_type", "refresh_token"), ("refresh_token", session.refreshToken)]
        if !session.resource.isEmpty { fields.append(("resource", session.resource)) }
        return tokenRequest(endpoint, fields, client: session.registration)
    }

    struct Tokens: Equatable {
        let accessToken: String
        let refreshToken: String?
        /// Seconds; nil when the answer did not say.
        let expiresIn: Int64?
    }

    enum TokenResult: Equatable {
        case ok(Tokens)
        /// The server's error code, or `http_<status>`.
        case rejected(String)
        /// No usable answer: a 5xx or an unreadable 200.
        case failed(String)
    }

    /// Reads a token endpoint's answer (RFC 6749 §5). A token must be one line of visible ASCII,
    /// as it goes into a header, and only a Bearer token is taken.
    static func tokenResult(status: Int, body: Data) -> TokenResult {
        let root = object(body)
        if (500...599).contains(status) { return .failed("server \(status)") }
        guard (200...299).contains(status) else { return .rejected((root?["error"] as? String) ?? "http_\(status)") }
        func token(_ value: Any?) -> String? {
            guard let text = value as? String, !text.isEmpty, text.utf8.count <= maximumTokenBytes,
                  text.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else { return nil }
            return text
        }
        guard let root, let access = token(root["access_token"]) else { return .failed("no usable access_token") }
        if let type = root["token_type"] as? String, type.lowercased() != "bearer" { return .rejected("unsupported_token_type") }
        return .ok(Tokens(accessToken: access, refreshToken: token(root["refresh_token"]),
                          expiresIn: ChatGPTSignIn.int64(root["expires_in"]).flatMap { $0 > 0 ? $0 : nil }))
    }

    static func expiry(_ expiresIn: Int64?, nowMs: Int64) -> Int64 {
        guard let expiresIn, expiresIn < (noExpiry - nowMs) / 1000 else { return noExpiry }
        return nowMs + expiresIn * 1000
    }
}

// MARK: - The saved sign-in

/// One MCP server's OAuth sign-in, kept whole in its Keychain item ("<prefix>oauth", MCPSettingsStore):
/// the client, where its tokens are refreshed and for which server, and the tokens. An empty one is
/// a server that uses OAuth and is not signed in. A sign-in that ran out keeps its client and token
/// endpoint, so the page says to sign in again; signing out keeps only a client the user entered.
public struct MCPOAuthSession: Codable, Equatable, Sendable, ModelAccountSessionValue {
    public var clientId: String
    public var clientSecret: String
    /// "none", "client_secret_post" or "client_secret_basic".
    public var clientAuth: String
    /// The user registered the client and entered it, because the server registers no apps.
    public var userClient: Bool
    public var tokenEndpoint: String
    /// RFC 8707: the server the tokens are for.
    public var resource: String
    public var accessToken: String
    public var refreshToken: String
    /// Milliseconds since 1970; MCPOAuth.noExpiry when the server gave no lifetime.
    public var expiresAtMs: Int64

    public init(clientId: String = "", clientSecret: String = "", clientAuth: String = "none", userClient: Bool = false,
                tokenEndpoint: String = "", resource: String = "", accessToken: String = "", refreshToken: String = "",
                expiresAtMs: Int64 = 0) {
        self.clientId = clientId; self.clientSecret = clientSecret; self.clientAuth = clientAuth; self.userClient = userClient
        self.tokenEndpoint = tokenEndpoint; self.resource = resource; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.expiresAtMs = expiresAtMs
    }

    /// A server that uses OAuth with a client the user registered, not signed in yet.
    public static func withUserClient(id: String, secret: String) -> Self {
        Self(clientId: id, clientSecret: secret, userClient: true)
    }

    public enum Status: Sendable { case signedOut, signedIn, expired }

    public var status: Status { signedIn ? .signedIn : tokenEndpoint.isEmpty ? .signedOut : .expired }
    public var signedIn: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }
    var registration: MCPOAuthRegistration { MCPOAuthRegistration(id: clientId, secret: clientSecret, auth: clientAuth) }

    /// The tokens cleared (ModelAccountTokenGate: the refresh token is dead); the rest stays.
    public func signedOut() -> Self {
        var session = self
        session.accessToken = ""; session.refreshToken = ""; session.expiresAtMs = 0
        return session
    }

    /// What signing out on the page leaves: a client the user entered, and nothing else.
    public func signedOutByUser() -> Self {
        userClient ? .withUserClient(id: clientId, secret: clientSecret) : Self()
    }

    private enum CodingKeys: String, CodingKey {
        case clientId, clientSecret, clientAuth, userClient, tokenEndpoint, resource, accessToken, refreshToken, expiresAtMs
    }

    /// Fields at their defaults may be left out.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try values.decodeIfPresent(String.self, forKey: .clientId) ?? ""
        clientSecret = try values.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
        clientAuth = try values.decodeIfPresent(String.self, forKey: .clientAuth) ?? "none"
        userClient = try values.decodeIfPresent(Bool.self, forKey: .userClient) ?? false
        tokenEndpoint = try values.decodeIfPresent(String.self, forKey: .tokenEndpoint) ?? ""
        resource = try values.decodeIfPresent(String.self, forKey: .resource) ?? ""
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try values.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        expiresAtMs = try values.decodeIfPresent(Int64.self, forKey: .expiresAtMs) ?? 0
    }
}

extension ModelAccountTokenGate: MCPAccessTokenProviding {}

extension MCPOAuth {
    /// One refresh (RFC 6749 §6): a rotated refresh token replaces the old one, and what the answer
    /// left out is kept. A dead refresh token is terminal; anything else the server refuses keeps it.
    public static func refresh(_ session: MCPOAuthSession, http: MCPOAuthHTTP,
                               nowMs: @Sendable () -> Int64) async throws -> ModelAccountRefreshResult<MCPOAuthSession> {
        guard let endpoint = allowed(session.tokenEndpoint) else { return .rejected(terminal: true) }
        let answer: MCPOAuthAnswer
        do { answer = try await http.send(refreshRequest(session, endpoint: endpoint)) }
        catch {
            try Task.checkCancellation()
            return .failed(MCPError.transportFailure)
        }
        switch tokenResult(status: answer.status, body: answer.body) {
        case .ok(let tokens):
            var next = session
            next.accessToken = tokens.accessToken
            next.refreshToken = tokens.refreshToken ?? session.refreshToken
            next.expiresAtMs = expiry(tokens.expiresIn, nowMs: nowMs())
            return .refreshed(next)
        case .rejected(let code):
            return .rejected(terminal: ChatGPTSignIn.terminalRefreshErrors.contains(code))
        case .failed:
            return .failed(MCPError.transportFailure)
        }
    }

    /// One server's tokens for its connections (MCPCredential.oauth): refreshed a minute before
    /// they expire or after a 401, one refresh at a time. A sign-in that ran out, or that the
    /// authorization server refused, throws MCPError.signInRequired.
    public static func tokenGate(http: MCPOAuthHTTP = .shared,
                                 load: @escaping @Sendable () throws -> MCPOAuthSession?,
                                 save: @escaping @Sendable (_ before: MCPOAuthSession, _ after: MCPOAuthSession) throws -> Void,
                                 nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() })
        -> ModelAccountTokenGate<MCPOAuthSession> {
        ModelAccountTokenGate(signInExpired: MCPError.signInRequired, refused: MCPError.signInRequired,
                              refreshAheadMs: refreshAheadMs, nowMs: nowMs, load: load, save: save,
                              refresh: { try await MCPOAuth.refresh($0, http: http, nowMs: nowMs) })
    }
}

// MARK: - The whole sign-in

extension MCPOAuth {
    /// One sign-in (Android McpServerStore.authorize). The listener is open already: the screen owns
    /// it, so it can listen again after iOS took the socket away from a suspended App. Discovers and
    /// registers (at most `discoveryTimeout`), opens the authorize page, waits for the callback, then
    /// checks it and exchanges the code (at most `finishTimeout`) before `page` answers the browser
    /// (nil: signed in). `userClient` is a client the user entered; without one the App registers.
    public static func signIn(endpoint: URL, userClient: MCPOAuthRegistration?, listener: LoopbackCallbackServer,
                              http: MCPOAuthHTTP = .shared, openBrowser: @Sendable (URL) async -> Void,
                              page: @escaping @Sendable (MCPOAuthError?) -> String,
                              discoveryTimeout: TimeInterval = MCPOAuth.discoveryTimeout, timeout: TimeInterval = MCPOAuth.timeout,
                              finishTimeout: TimeInterval = MCPOAuth.finishTimeout,
                              nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() }) async throws -> MCPOAuthSession {
        let redirectURI = listener.redirectURI
        let prepared: (server: MCPOAuthServer, client: MCPOAuthRegistration)
        do {
            prepared = try await ChatGPTSignIn.withDeadline(discoveryTimeout) {
                let server = try await discover(endpoint: endpoint, http: http)
                if let userClient, !userClient.id.isEmpty {
                    return (server: server, client: MCPOAuthRegistration(
                        id: userClient.id, secret: userClient.secret,
                        auth: clientAuth(secret: userClient.secret, registered: nil, supported: server.tokenAuthMethods)))
                }
                return (server: server, client: try await register(server, redirectURI: redirectURI, http: http))
            }
        } catch is ChatGPTSignIn.DeadlineExceeded {
            throw MCPOAuthError(.network, detail: "no answer in \(Int(discoveryTimeout))s")
        }
        let (server, client) = prepared
        let attempt = ChatGPTSignInAttempt.make(redirectURI: redirectURI)
        guard let url = authorizeURL(server, clientID: client.id, attempt: attempt) else {
            throw MCPOAuthError(.setup, detail: "authorization endpoint")
        }
        let outcome = SignInOutcome()
        let entered = userClient.map { !$0.id.isEmpty } ?? false
        async let callback = listener.waitForCallback(timeout: timeout, accept: { $0["state"] == attempt.state }) { params in
            let result: Result<MCPOAuthSession, MCPOAuthError>
            do {
                result = .success(try await ChatGPTSignIn.withDeadline(finishTimeout) {
                    try await completeSignIn(params: params, attempt: attempt, server: server, client: client,
                                             userClient: entered, http: http, nowMs: nowMs)
                })
            } catch let error as MCPOAuthError {
                result = .failure(error)
            } catch is ChatGPTSignIn.DeadlineExceeded {
                result = .failure(MCPOAuthError(.network, detail: "no answer in \(Int(finishTimeout))s"))
            } catch {
                result = .failure(MCPOAuthError(.network, detail: String(describing: type(of: error))))
            }
            outcome.set(result)
            if case .failure(let error) = result { return page(error) }
            return page(nil)
        }
        await openBrowser(url)
        guard await callback != nil, let result = outcome.get() else {
            try Task.checkCancellation()
            throw MCPOAuthError(.timedOut)
        }
        return try result.get()
    }

    static func completeSignIn(params: [String: String], attempt: ChatGPTSignInAttempt, server: MCPOAuthServer,
                               client: MCPOAuthRegistration, userClient: Bool, http: MCPOAuthHTTP,
                               nowMs: @Sendable () -> Int64) async throws -> MCPOAuthSession {
        let code = try readCallback(params, attempt: attempt, server: server)
        let answer: MCPOAuthAnswer
        do { answer = try await http.send(exchangeRequest(server, client: client, code: code, attempt: attempt)) }
        catch {
            try Task.checkCancellation()
            throw MCPOAuthError(.network, detail: "token")
        }
        switch tokenResult(status: answer.status, body: answer.body) {
        case .ok(let tokens):
            return MCPOAuthSession(clientId: client.id, clientSecret: client.secret, clientAuth: client.auth,
                                   userClient: userClient, tokenEndpoint: server.tokenEndpoint.absoluteString,
                                   resource: server.resource, accessToken: tokens.accessToken,
                                   refreshToken: tokens.refreshToken ?? "", expiresAtMs: expiry(tokens.expiresIn, nowMs: nowMs()))
        case .rejected(let code):
            throw MCPOAuthError(.exchange, code: code)
        case .failed(let why):
            throw MCPOAuthError(.network, detail: why)
        }
    }

    private final class SignInOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<MCPOAuthSession, MCPOAuthError>?
        func set(_ value: Result<MCPOAuthSession, MCPOAuthError>) { lock.lock(); result = value; lock.unlock() }
        func get() -> Result<MCPOAuthSession, MCPOAuthError>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }
    }
}

// MARK: - HTTP

/// One answer: its status, the WWW-Authenticate challenge and the body.
public struct MCPOAuthAnswer: Sendable {
    public let status: Int
    public let challenge: String?
    public let body: Data
}

/// The sign-in's requests (Android McpOAuth's client: 20 seconds, no redirects). Redirects are
/// refused: metadata counts only as a 200 answer (RFC 8414 §3.2, RFC 9728 §3.2), and a code,
/// secret or token never follows one to another host. At most 1 MiB of an answer is read; no
/// cookie, cache or credential is kept.
public final class MCPOAuthHTTP: @unchecked Sendable {
    public static let shared = MCPOAuthHTTP()
    static let maximumBodyBytes = 1024 * 1024
    private let session: URLSession

    public convenience init() { self.init(configuration: .ephemeral) }

    init(configuration: URLSessionConfiguration) {
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    deinit { session.finishTasksAndInvalidate() }

    /// Only cancellation and a missing answer throw.
    func send(_ request: URLRequest) async throws -> MCPOAuthAnswer {
        var request = request
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request, delegate: MCPRejectRedirects())
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse }
        var body = Data()
        for try await byte in bytes {
            guard body.count < Self.maximumBodyBytes else { throw MCPError.responseTooLarge }
            body.append(byte)
        }
        return MCPOAuthAnswer(status: http.statusCode, challenge: http.value(forHTTPHeaderField: "WWW-Authenticate"), body: body)
    }
}
