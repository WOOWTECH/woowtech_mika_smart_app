import Foundation
import Network
import Security

/// The ChatGPT sign-in prototype, offline (Sources/AssistantModels/ChatGPTSignIn.swift,
/// LoopbackCallbackServer.swift and ChatGPTResponses.swift): PKCE against RFC 7636; the authorize URL
/// and the token forms against what OkHttp 4.12, the Play build's HTTP client, produced for the same
/// inputs; the callback listener over real loopback sockets; whole sign-ins, refreshes and plan calls
/// against fake servers on 127.0.0.1. Nothing here reaches OpenAI or any other host.
struct Failure: Error { let message: String }

/// What OkHttp 4.12.0, the Play build's HTTP client, built for the inputs used below: a small Java
/// program called HttpUrl.Builder.addQueryParameter in ChatGptAuth.authorizeUrl's order (@964d7bec)
/// and FormBody.Builder for the exchange, refresh and revoke forms.
enum OkHttpGolden {
    static let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    static let first = "https://auth.openai.com/api/accounts/authorize?client_id=dynamic_agent_client&agent_name_hint=woowtech%20agent&ext_agent_host_id=urn%3Auuid%3A3f1c0e7a-6c1d-4a39-9f3e-0b1e4a5d2c11&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback&scope=openid%20profile%20email%20offline_access%20resource.invoke%20chatgpt.tokens.use.direct&resource=https%3A%2F%2Fapi.openai.com%2Fv1&state=st_ate-1&nonce=no_nce-2&code_challenge_method=S256&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    static let later = "https://auth.openai.com/api/accounts/authorize?client_id=app_client%2B1%7Ex&ext_agent_host_id=urn%3Auuid%3A3f1c0e7a-6c1d-4a39-9f3e-0b1e4a5d2c11&id_token_hint=eyJh.eyJz.c2ln&login_hint=a%2Bb%40example.com&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback&scope=openid%20profile%20email%20offline_access%20resource.invoke%20chatgpt.tokens.use.direct&resource=https%3A%2F%2Fapi.openai.com%2Fv1&state=st_ate-1&nonce=no_nce-2&code_challenge_method=S256&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    static let laterWithoutHints = "https://auth.openai.com/api/accounts/authorize?client_id=app_client&ext_agent_host_id=urn%3Auuid%3Ah&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback&scope=openid%20profile%20email%20offline_access%20resource.invoke%20chatgpt.tokens.use.direct&resource=https%3A%2F%2Fapi.openai.com%2Fv1&state=s&nonce=n&code_challenge_method=S256&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    static let exchange = "grant_type=authorization_code&client_id=app_client%2B1%7Ex&code=c0de%2F%2B%3D%7E%20x%26y&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback&resource=https%3A%2F%2Fapi.openai.com%2Fv1"
    static let refresh = "grant_type=refresh_token&client_id=app_client%2B1%7Ex&refresh_token=rt%2F%2B%3D%201&resource=https%3A%2F%2Fapi.openai.com%2Fv1"
    static let revoke = "token=rt%2F%2B%3D%201&token_type_hint=refresh_token&client_id=app_client%2B1%7Ex"
    static let unicodeHint = "%E6%B8%A5%E5%B1%8B%20%C3%A9%21*%27%28%29%7E"
}

/// A value shared with fake servers and callbacks.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    func update(_ change: (inout Value) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

/// A tiny HTTP/1.1 server on 127.0.0.1 standing in for the issuer and the API: one request per
/// connection, answers from `handler`, optionally late or in timed chunks.
final class FakeServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let query: String
        let headers: [String: String]
        let body: Data
        var form: [String: String] { LoopbackCallbackServer.parseQuery(String(decoding: body, as: UTF8.self)) ?? [:] }
        var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:] }
    }

    struct Reply: Sendable {
        var status = 200
        var type = "application/json"
        var chunks: [String] = [""]
        var gap: TimeInterval = 0
        var delay: TimeInterval = 0
        /// Close without answering.
        var hangUp = false

        static func json(_ status: Int, _ body: String) -> Reply { Reply(status: status, chunks: [body]) }
    }

    private let queue = DispatchQueue(label: "fake-server")
    private var listener: NWListener?
    private var log: [Request] = []
    private let handler: @Sendable (Request) -> Reply
    private(set) var port: UInt16 = 0

    init(_ handler: @escaping @Sendable (Request) -> Reply) { self.handler = handler }

    static func start(_ handler: @escaping @Sendable (Request) -> Reply) async throws -> FakeServer {
        let server = FakeServer(handler)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let started = Box(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !started.value else { return }
                    started.value = true
                    server.port = listener.port?.rawValue ?? 0
                    continuation.resume()
                case .failed(let error):
                    guard !started.value else { return }
                    started.value = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in server.serve(connection) }
            listener.start(queue: server.queue)
        }
        server.listener = listener
        return server
    }

    var base: String { "http://127.0.0.1:\(port)" }
    var requests: [Request] { queue.sync { log } }
    func stop() { queue.sync { listener?.cancel(); listener = nil } }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, Data())
    }

    private func read(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let lines = String(decoding: buffer.subdata(in: 0..<end.lowerBound), as: UTF8.self).components(separatedBy: "\r\n")
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                let length = Int(headers["content-length"] ?? "0") ?? 0
                if buffer.count - end.upperBound >= length {
                    let parts = lines[0].split(separator: " ").map(String.init)
                    let target = parts.count > 1 ? parts[1] : ""
                    let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    let query = target.firstIndex(of: "?").map { String(target[target.index(after: $0)...]) } ?? ""
                    let request = Request(method: parts.first ?? "", path: path, query: query, headers: headers,
                                          body: buffer.subdata(in: end.upperBound..<end.upperBound + length))
                    self.log.append(request)
                    return self.answer(connection, self.handler(request))
                }
            }
            if error != nil || isComplete { return connection.cancel() }
            self.read(connection, buffer)
        }
    }

    private func answer(_ connection: NWConnection, _ reply: Reply) {
        let send: @Sendable () -> Void = {
            if reply.hangUp { return connection.cancel() }
            let streamed = reply.chunks.count > 1
            var head = "HTTP/1.1 \(reply.status) Fake\r\nContent-Type: \(reply.type)\r\nConnection: close\r\n"
            if !streamed { head += "Content-Length: \(reply.chunks.joined().utf8.count)\r\n" }
            connection.send(content: Data((head + "\r\n").utf8), completion: .contentProcessed { _ in })
            self.write(connection, ArraySlice(reply.chunks), gap: reply.gap)
        }
        if reply.delay > 0 { queue.asyncAfter(deadline: .now() + reply.delay, execute: send) } else { send() }
    }

    private func write(_ connection: NWConnection, _ chunks: ArraySlice<String>, gap: TimeInterval) {
        guard let chunk = chunks.first else {
            return connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                   completion: .contentProcessed { _ in connection.cancel() })
        }
        connection.send(content: Data(chunk.utf8), completion: .contentProcessed { _ in
            self.queue.asyncAfter(deadline: .now() + gap) { self.write(connection, chunks.dropFirst(), gap: gap) }
        })
    }
}

/// An RSA key that signs ID tokens and publishes itself as a JWK.
struct Signer: @unchecked Sendable {
    let kid: String
    let key: SecKey
    let jwk: [String: Any]

    init(kid: String) throws {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let pub = SecKeyCopyPublicKey(key),
              let der = SecKeyCopyExternalRepresentation(pub, &error) as Data? else { throw Failure(message: "RSA key") }
        var reader = DERReader(bytes: [UInt8](der))
        guard reader.expect(0x30) != nil, let modulus = reader.expect(0x02), let exponent = reader.expect(0x02) else {
            throw Failure(message: "RSA public key DER")
        }
        self.kid = kid
        self.key = key
        jwk = ["kty": "RSA", "kid": kid, "alg": "RS256", "use": "sig",
               "n": PKCE.base64URL(Data(modulus.drop { $0 == 0 })), "e": PKCE.base64URL(Data(exponent))]
    }

    func token(_ claims: [String: Any], kid: String? = nil, alg: String = "RS256") throws -> String {
        let header: [String: Any] = ["alg": alg, "kid": kid ?? self.kid, "typ": "JWT"]
        let head = PKCE.base64URL(try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let body = PKCE.base64URL(try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data((head + "." + body).utf8) as CFData,
                                                    &error) as Data? else { throw Failure(message: "sign") }
        return head + "." + body + "." + PKCE.base64URL(signature)
    }

    static func jwks(_ signers: [Signer]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["keys": signers.map(\.jwk)]), as: UTF8.self)
    }
}

struct DERReader {
    let bytes: [UInt8]
    var index = 0

    /// The next element's content when its tag is `tag`; a SEQUENCE is entered, not skipped.
    mutating func expect(_ tag: UInt8) -> [UInt8]? {
        guard index < bytes.count, bytes[index] == tag, index + 1 < bytes.count else { return nil }
        index += 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            length = 0
            for _ in 0..<count { length = length << 8 | Int(bytes[index]); index += 1 }
        }
        guard index + length <= bytes.count else { return nil }
        if tag == 0x30 { return [] }
        defer { index += length }
        return Array(bytes[index..<index + length])
    }
}

@main enum CheckChatGPTSignIn {
    #if DEBUG
    static let config = "Debug"
    #else
    static let config = "Release"
    #endif
    static var checks = 0
    /// Every failed assertion, so one run shows them all; a broken precondition still stops at once.
    static var failures: [String] = []
    static let web = URLSession(configuration: .ephemeral)
    static let clock: Int64 = 1_800_000_000_000
    static let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    static let redirect = "http://127.0.0.1:4321/auth/callback"
    static let hostID = "urn:uuid:3f1c0e7a-6c1d-4a39-9f3e-0b1e4a5d2c11"

    static func check(_ value: Bool, _ message: String) throws {
        checks += 1
        if !value { failures.append(message) }
    }

    static func main() async {
        do {
            try pkce()
            try authorizeURLs()
            try tokenForms()
            try callbacks()
            try refusals()
            try tokenAnswers()
            try sessions()
            try await idTokens()
            try await loopback()
            try await signIns()
            try await tokenRefresh()
            try responsesRequests()
            try responsesStreams()
            try await responsesClient()
            try models()
        } catch let failure as Failure {
            failures.append(failure.message)
        } catch {
            failures.append("unexpected \(error)")
        }
        guard failures.isEmpty else {
            for failure in failures { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS ChatGPT sign-in prototype (\(config)): \(checks) assertions; loopback only, no request to OpenAI")
    }

    // MARK: - PKCE, URL and forms

    static func pkce() throws {
        try check(PKCE.challenge(verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "S256 gives RFC 7636 appendix B's challenge")
        try check(PKCE.challenge(verifier) == OkHttpGolden.challenge, "S256 gives what the Play build computes")
        let a = ChatGPTSignInAttempt.make(redirectURI: redirect)
        let b = ChatGPTSignInAttempt.make(redirectURI: redirect)
        try check(a.state != b.state && a.nonce != b.nonce && a.verifier != b.verifier, "every attempt gets new random values")
        try check(a.state.count == 43 && a.nonce.count == 43 && a.verifier.count == 64,
                  "32 random bytes for the state and nonce, 48 for the verifier, like Play")
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        try check([a.state, a.nonce, a.verifier, a.challenge].allSatisfy { $0.allSatisfy(alphabet.contains) },
                  "random values and the challenge are base64url without padding")
        try check(PKCE.base64URLDecode(PKCE.base64URL(Data([0xFB, 0xFF, 0x01]))) == Data([0xFB, 0xFF, 0x01]), "base64url round trip")
        let host = ChatGPTSignIn.newHostID()
        try check(host.hasPrefix("urn:uuid:") && host.count == 45 && host == host.lowercased() && host != ChatGPTSignIn.newHostID(),
                  "the host id is a new lowercase urn:uuid like Java's UUID")
    }

    static func authorizeURLs() throws {
        let attempt = ChatGPTSignInAttempt(state: "st_ate-1", nonce: "no_nce-2", verifier: verifier, redirectURI: redirect)
        let first = ChatGPTSignIn.authorizeURL(attempt, clientID: nil, hostID: hostID, idTokenHint: "old.id.token", loginHint: "a@b.test")
        try check(first.absoluteString == OkHttpGolden.first, "the first sign-in's authorize URL is the Play build's, byte for byte")
        let later = ChatGPTSignIn.authorizeURL(attempt, clientID: "app_client+1~x", hostID: hostID, idTokenHint: "eyJh.eyJz.c2ln",
                                               loginHint: "a+b@example.com")
        try check(later.absoluteString == OkHttpGolden.later, "a later sign-in's URL is the Play build's, hints included")
        let plain = ChatGPTSignIn.authorizeURL(ChatGPTSignInAttempt(state: "s", nonce: "n", verifier: verifier, redirectURI: redirect),
                                               clientID: "app_client", hostID: "urn:uuid:h", idTokenHint: "", loginHint: nil)
        try check(plain.absoluteString == OkHttpGolden.laterWithoutHints, "empty hints are left out, like Play")
        try check(ChatGPTSignIn.percentEncode("渥屋 é!*'()~") == OkHttpGolden.unicodeHint, "non-ASCII and reserved characters encode like OkHttp")
        let items = URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        try check(query["redirect_uri"] == redirect && query["scope"] == ChatGPTSignIn.scopes && query["agent_name_hint"] == "woowtech agent"
                    && query["id_token_hint"] == nil && query["login_hint"] == nil,
                  "the URL decodes to the redirect, the scopes and the App name; a first sign-in sends no hints")
    }

    static func tokenForms() throws {
        let attempt = ChatGPTSignInAttempt(state: "s", nonce: "n", verifier: verifier, redirectURI: redirect)
        let exchange = ChatGPTSignIn.exchangeRequest(clientID: "app_client+1~x", code: "c0de/+=~ x&y", attempt: attempt)
        try check(exchange.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/token" && exchange.httpMethod == "POST",
                  "the exchange posts to the token endpoint")
        try check(exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded", "the exchange is a form, like OkHttp's FormBody")
        try check(exchange.httpBody == Data(OkHttpGolden.exchange.utf8), "the exchange form is the Play build's, byte for byte")
        let refresh = ChatGPTSignIn.refreshRequest(clientID: "app_client+1~x", refreshToken: "rt/+= 1")
        try check(refresh.httpBody == Data(OkHttpGolden.refresh.utf8) && refresh.url?.path == "/api/accounts/oauth/token",
                  "the refresh form is the Play build's, without a scope")
        let revoke = ChatGPTSignIn.revokeRequest(clientID: "app_client+1~x", refreshToken: "rt/+= 1")
        try check(revoke.httpBody == Data(OkHttpGolden.revoke.utf8) && revoke.url?.path == "/api/accounts/oauth/revoke",
                  "the revoke form is the Play build's")
    }

    static func callbacks() throws {
        let attempt = ChatGPTSignInAttempt.make(redirectURI: "r")
        func reason(_ params: [String: String], _ clientID: String?) -> ChatGPTSignInFailure? {
            do { _ = try ChatGPTSignIn.readCallback(params, attempt: attempt, clientID: clientID); return nil }
            catch let error as ChatGPTSignInError { return error.reason } catch { return nil }
        }
        let issued = try ChatGPTSignIn.readCallback(["state": attempt.state, "code": "c", "client_id": "issued"], attempt: attempt, clientID: nil)
        try check(issued.code == "c" && issued.clientID == "issued", "a first sign-in takes the issued client id")
        let kept = try ChatGPTSignIn.readCallback(["state": attempt.state, "code": "c"], attempt: attempt, clientID: "client-1")
        try check(kept.clientID == "client-1", "a later sign-in keeps its client id")
        try check(reason(["state": "x", "code": "c"], nil) == .stateMismatch, "another state is refused before anything else")
        try check(reason(["state": attempt.state, "error": "access_denied"], nil) == .denied, "a refusal on the authorize page")
        try check(reason(["state": attempt.state, "error": "unsupported_country_region_territory"], nil) == .region, "the region is worded")
        try check(reason(["state": attempt.state, "error": "invalid_scope"], nil) == .noPlanScope, "the plan is worded")
        try check(reason(["state": attempt.state, "error": "server_error"], nil) == .denied, "any other authorize error is a refusal")
        try check(reason(["state": attempt.state, "code": "c", "client_id": "other"], "client-1") == .clientMismatch, "another client id")
        try check(reason(["state": attempt.state, "code": "c"], nil) == .noClientID, "a first sign-in without a client id")
        try check(reason(["state": attempt.state], "client-1") == .exchange, "a callback without a code")
        do {
            _ = try ChatGPTSignIn.readCallback(["state": attempt.state, "error": "access_denied"], attempt: attempt, clientID: nil)
            try check(false, "a refusal throws")
        } catch let error as ChatGPTSignInError {
            try check(error.code == "access_denied", "a refusal keeps its code for diagnostics")
        }
    }

    static func refusals() throws {
        func f(_ code: String, _ detail: String? = nil, nonJSON: Bool = false) -> ChatGPTSignInFailure {
            ChatGPTSignIn.failure(code: code, detail: detail, nonJSON: nonJSON)
        }
        try check(f("invalid_grant", "Invalid authorization code") == .codeExpired, "invalid_grant: the code expired or was used")
        try check(f("unsupported_country_region_territory", "Country, region, or territory not supported") == .region, "region code")
        try check(f("forbidden", "Your region is not supported") == .region, "region in the description")
        try check(f("unsupported_country") == .region, "unsupported_country")
        try check(f("http_403", nonJSON: true) == .blocked && f("http_429", nonJSON: true) == .blocked, "a protection page is blocked")
        try check(f("http_403") == .exchange, "a JSON 403 is not a protection page")
        try check(f("access_denied") == .denied && f("consent_required") == .denied, "no consent")
        try check(f("invalid_scope") == .noPlanScope && f("subscription_sharing_user_not_eligible") == .noPlanScope, "plan codes")
        try check(f("forbidden", "Your plan does not include this") == .noPlanScope, "the plan as a whole word in the description")
        try check(f("server_error", "no explanation") == .exchange, "words count only whole (explanation is not plan)")
        try check(f("invalid_client", "Client authentication failed") == .exchange, "anything else is an exchange refusal")
    }

    static func tokenAnswers() throws {
        func result(_ status: Int, _ body: String) -> ChatGPTTokenResult { ChatGPTSignIn.tokenResult(status: status, body: Data(body.utf8)) }
        let full = result(200, #"{"access_token":"at","refresh_token":"rt","id_token":"it","token_type":"Bearer","expires_in":3600,"scope":"chatgpt.tokens.use.direct email offline_access openid profile resource.invoke"}"#)
        try check(full == .ok(ChatGPTTokenSet(accessToken: "at", refreshToken: "rt", idToken: "it", expiresIn: 3600,
                                              scopes: ["chatgpt.tokens.use.direct", "email", "offline_access", "openid", "profile", "resource.invoke"])),
                  "a full token answer")
        try check(result(200, #"{"access_token":"at"}"#) == .ok(ChatGPTTokenSet(accessToken: "at", refreshToken: nil, idToken: nil, expiresIn: 3600, scopes: [])),
                  "a missing lifetime is an hour")
        try check(result(200, #"{"access_token":"at","expires_in":"1800"}"#) == .ok(ChatGPTTokenSet(accessToken: "at", refreshToken: nil, idToken: nil, expiresIn: 1800, scopes: [])),
                  "a lifetime written as a string counts")
        try check(result(400, #"{"error":"invalid_grant"}"#) == .rejected(code: "invalid_grant", terminal: true, detail: nil, nonJSON: false),
                  "invalid_grant ends the refresh token")
        try check(result(401, #"{"error":{"code":"refresh_token_reused","message":"reused"}}"#)
                    == .rejected(code: "refresh_token_reused", terminal: true, detail: "reused", nonJSON: false), "a reused refresh token")
        try check(result(401, #"{"error":"invalid_client","error_description":"bad client"}"#)
                    == .rejected(code: "invalid_client", terminal: false, detail: "bad client", nonJSON: false), "invalid_client keeps the token")
        try check(result(503, "") == .failed(.server(503)), "a 5xx is a server failure, not a refusal")
        try check(result(403, "<!DOCTYPE html><html><body>Just a moment...</body></html>")
                    == .rejected(code: "http_403", terminal: false, detail: nil, nonJSON: true), "an HTML 403 is a protection page")
        if case .failed(.badResponse(_)) = result(200, #"{"token_type":"Bearer"}"#) {} else { try check(false, "no access token is a bad answer") }
    }

    static func sessions() throws {
        let session = ChatGPTSession(clientId: "client-1", sub: "user-1", email: "a@b.test", accessToken: "at", refreshToken: "rt",
                                     idToken: "it", expiresAtMs: clock, scopes: [ChatGPTSignIn.planScope])
        let decoded = try JSONDecoder().decode(ChatGPTSession.self, from: JSONEncoder().encode(session))
        try check(decoded == session && session.signedIn && session.planUsage, "a session round-trips through JSON")
        let play = try JSONDecoder().decode(ChatGPTSession.self, from: Data(#"{"clientId":"client-1","sub":"user-1"}"#.utf8))
        try check(play == ChatGPTSession(clientId: "client-1", sub: "user-1") && !play.signedIn, "Play's JSON without default fields reads")
        let out = session.signedOut()
        try check(!out.signedIn && out.clientId == "client-1" && out.email == "a@b.test" && out.idToken.isEmpty && out.expiresAtMs == 0,
                  "signing out clears the tokens and keeps the registration and identity")
    }

    // MARK: - ID tokens

    static func claims(aud: Any = "client-1", nonce: String = "n", exp: Int64 = clock / 1000 + 3600,
                       iss: String, extra: [String: Any] = [:]) -> [String: Any] {
        var claims: [String: Any] = ["iss": iss, "aud": aud, "sub": "user-1", "email": "a@b.test", "nonce": nonce, "exp": exp,
                                     "iat": clock / 1000]
        for (key, value) in extra { claims[key] = value }
        return claims
    }

    static func idTokens() async throws {
        let signer = try Signer(kid: "k1")
        let stranger = try Signer(kid: "k1")
        let rotated = try Signer(kid: "k3")
        let published = Box([signer])
        let issuer = try await FakeServer.start { request in
            request.path == "/.well-known/jwks.json" ? .json(200, Signer.jwks(published.value)) : .json(404, "{}")
        }
        defer { issuer.stop() }
        let auth = ChatGPTAuthClient(issuer: issuer.base)
        func reason(_ token: String, clientID: String = "client-1", nonce: String = "n") async -> String? {
            do { _ = try await auth.verifyIDToken(token, clientID: clientID, nonce: nonce, nowMs: clock); return nil }
            catch let error as ChatGPTSignInError { return error.reason == .idToken ? error.detail : "\(error.reason)" }
            catch { return "\(error)" }
        }
        let identity = try await auth.verifyIDToken(try signer.token(claims(iss: issuer.base)), clientID: "client-1", nonce: "n", nowMs: clock)
        try check(identity == ChatGPTIdentity(sub: "user-1", email: "a@b.test"), "a valid ID token gives the identity")
        try check(issuer.requests.map(\.path) == ["/.well-known/jwks.json"], "the JWKS is fetched once and kept")
        try check(await reason(try signer.token(claims(aud: "other", iss: issuer.base))) == "audience", "another audience is refused")
        try check(await reason(try signer.token(claims(aud: ["x", "client-1"], iss: issuer.base))) == nil, "an audience list naming the client")
        try check(await reason(try signer.token(claims(nonce: "x", iss: issuer.base))) == "nonce", "another attempt's nonce is refused")
        try check(await reason(try signer.token(claims(iss: "https://evil.test"))) == "issuer", "another issuer is refused")
        try check(await reason(try signer.token(claims(exp: clock / 1000 - 3600, iss: issuer.base))) == "expired", "an expired token")
        try check(await reason(try signer.token(claims(exp: clock / 1000 - 60, iss: issuer.base))) == nil, "two minutes of clock skew")
        try check(await reason(try stranger.token(claims(iss: issuer.base))) == "signature", "another key's signature is refused")
        try check(await reason(try signer.token(claims(iss: issuer.base), alg: "none")) == "alg none", "only RS256")
        try check(await reason("a.b") == "not a JWT", "not a JWT")
        var noSub = claims(iss: issuer.base)
        noSub["sub"] = ""
        try check(await reason(try signer.token(noSub)) == "no sub", "an empty subject is refused")
        var profile = claims(iss: issuer.base)
        profile["email"] = nil
        profile["https://api.openai.com/profile"] = ["email": "p@b.test"]
        let fromProfile = try await auth.verifyIDToken(try signer.token(profile), clientID: "client-1", nonce: "n", nowMs: clock)
        try check(fromProfile.email == "p@b.test", "the email can come from the profile claim")
        let before = issuer.requests.count
        try check(await reason(try signer.token(claims(iss: issuer.base), kid: "k2")) == "unknown key", "an unknown key id is refused")
        try check(issuer.requests.count == before + 1, "an unknown key id fetches the JWKS once more")
        published.value = [signer, rotated]
        try check(await reason(try rotated.token(claims(iss: issuer.base))) == nil, "a rotated key is found after fetching again")
    }

    // MARK: - The callback listener

    static func get(_ url: String) async -> (status: Int, body: String)? {
        guard let answer = try? await web.data(from: URL(string: url)!) else { return nil }
        return ((answer.1 as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: answer.0, as: UTF8.self))
    }

    /// The status of a request URLSession would not send as is (it repairs a malformed escape).
    static func rawStatus(port: UInt16, target: String) async -> Int? {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "raw-request")
        let answer: Data? = await withCheckedContinuation { continuation in
            let finished = Box(false)
            let received = Box(Data())
            @Sendable func finish(_ data: Data?) {
                guard !finished.value else { return }
                finished.value = true
                connection.cancel()
                continuation.resume(returning: data)
            }
            @Sendable func read() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let data { received.update { $0.append(data) } }
                    if isComplete || error != nil { finish(received.value) } else { read() }
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data("GET \(target) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in read() })
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
        guard let answer, let line = String(decoding: answer, as: UTF8.self).split(separator: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        return parts.count > 1 ? Int(parts[1]) : nil
    }

    static func listening(on port: UInt16) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", String(getpid()), "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    static func loopback() async throws {
        try check(LoopbackCallbackServer.parseQuery("code=%zz&state=s") == nil
                    && LoopbackCallbackServer.parseQuery("a=1+2&b=%2F&&c") == ["a": "1 2", "b": "/", "c": ""],
                  "callback queries decode like java.net.URLDecoder; a malformed escape is no query")
        let server = try await LoopbackCallbackServer.open()
        let port = server.port
        try check(port > 0 && server.redirectURI == "http://127.0.0.1:\(port)/auth/callback", "the redirect is 127.0.0.1 with the given port")
        let bound = listening(on: port)
        try check(bound.contains("127.0.0.1:\(port) (LISTEN)") && !bound.contains("*:\(port)"), "it listens on 127.0.0.1 only")
        async let waited = server.waitForCallback(timeout: 10, accept: { $0["state"] == "s" }) { params in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return "<p>ok \(params["code"] ?? "")</p>"
        }
        try check(await get("http://127.0.0.1:\(port)/favicon.ico")?.status == 404, "other paths get 404")
        try check(await get(server.redirectURI + "?code=x&state=other")?.status == 400, "another attempt's callback gets 400")
        try check(await rawStatus(port: port, target: "/auth/callback?code=%zz&state=s") == 400, "a malformed escape gets 400")
        let hit = await get(server.redirectURI + "?code=a+b%2Fc&state=s")
        try check(hit?.status == 200 && hit?.body == "<p>ok a b/c</p>", "the callback's page comes after the work, + and %2F decoded")
        let params = await waited
        try check(params == ["code": "a b/c", "state": "s"], "the wait returns the callback's parameters")
        try check(await get(server.redirectURI + "?code=again&state=s")?.status == 400, "only one callback is taken")
        server.close()
        var refused = false
        for _ in 0..<20 where !refused {
            refused = await get(server.redirectURI + "?state=s") == nil
            if !refused { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        try check(refused, "a closed listener refuses connections")

        let timing = try await LoopbackCallbackServer.open()
        let started = Date()
        let timedOut = await timing.waitForCallback(timeout: 0.4) { _ in "" }
        try check(timedOut == nil && Date().timeIntervalSince(started) < 3, "no callback in time ends the wait with nil")
        timing.close()

        let early = try await LoopbackCallbackServer.open()
        let earlyHit = Task { await get(early.redirectURI + "?code=e&state=s") }
        try await Task.sleep(nanoseconds: 300_000_000)
        let earlyParams = await early.waitForCallback(timeout: 5) { _ in "early" }
        let earlyPage = await earlyHit.value
        try check(earlyParams?["code"] == "e" && earlyPage?.body == "early", "a browser quicker than the waiter is answered once the wait starts")
        early.close()

        let cancelled = try await LoopbackCallbackServer.open()
        let waiting = Task { await cancelled.waitForCallback(timeout: 30) { _ in "" } }
        try await Task.sleep(nanoseconds: 200_000_000)
        let cancelStart = Date()
        waiting.cancel()
        try check(await waiting.value == nil && Date().timeIntervalSince(cancelStart) < 2, "cancelling ends the wait at once")
        cancelled.close()

        let closing = try await LoopbackCallbackServer.open()
        let closingWait = Task { await closing.waitForCallback(timeout: 30) { _ in "" } }
        try await Task.sleep(nanoseconds: 200_000_000)
        closing.close()
        try check(await closingWait.value == nil, "closing ends the wait")

        let reopened = try await LoopbackCallbackServer.open()
        let samePort = reopened.port
        try await reopened.reopen()
        try check(reopened.port == samePort && reopened.isListening, "reopening listens on the same port")
        async let afterReopen = reopened.waitForCallback(timeout: 5) { _ in "back" }
        try check(await get(reopened.redirectURI + "?code=r&state=s")?.body == "back", "the reopened listener takes the callback")
        let reopenedParams = await afterReopen
        try check(reopenedParams?["code"] == "r", "the wait survives reopening")
        reopened.close()
    }

    // MARK: - Whole sign-ins against a fake issuer

    final class Browser: @unchecked Sendable {
        let authorize = Box<[String: String]>([:])
        let shown = Box<String?>(nil)
        let opened = Box(false)
        /// Reads the authorize URL like a browser would, then comes back with `answer(params)`.
        func open(_ url: URL, answer: @escaping @Sendable ([String: String]) -> String?) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            authorize.value = params
            opened.value = true
            guard let query = answer(params) else { return }
            Task { self.shown.value = await CheckChatGPTSignIn.get((params["redirect_uri"] ?? "") + "?" + query)?.body }
        }
    }

    static func issuer(signer: Signer, browser: Browser, scope: String, token: FakeServer.Reply? = nil) async throws -> FakeServer {
        let base = Box("")
        let server = try await FakeServer.start { request in
            switch request.path {
            case "/.well-known/jwks.json":
                return .json(200, Signer.jwks([signer]))
            case "/api/accounts/oauth/token":
                if let token { return token }
                let claims: [String: Any] = ["iss": base.value, "aud": request.form["client_id"] ?? "",
                                             "sub": "user-1", "email": "a@b.test", "nonce": browser.authorize.value["nonce"] ?? "",
                                             "exp": clock / 1000 + 3600]
                let id = (try? signer.token(claims)) ?? ""
                return .json(200, #"{"access_token":"at","refresh_token":"rt","id_token":"\#(id)","expires_in":3600,"scope":"\#(scope)"}"#)
            default:
                return .json(404, "{}")
            }
        }
        base.value = server.base
        return server
    }

    static func signIn(_ fake: FakeServer, browser: Browser, clientID: String?, previous: ChatGPTSession? = nil,
                       answer: @escaping @Sendable ([String: String]) -> String?, timeout: TimeInterval = 10,
                       finishTimeout: TimeInterval = 5, registered: Box<[String]> = Box([])) async -> Result<ChatGPTSession, Error> {
        guard let server = try? await LoopbackCallbackServer.open() else { return .failure(Failure(message: "listener")) }
        defer { server.close() }
        let auth = ChatGPTAuthClient(issuer: fake.base)
        do {
            return .success(try await ChatGPTSignIn.signIn(
                auth: auth, server: server, hostID: "urn:uuid:h", clientID: clientID, previous: previous,
                openBrowser: { url in browser.open(url, answer: answer) },
                onRegistered: { id in registered.update { $0.append(id) } },
                page: { error in "result=\(error?.reason.rawValue ?? "ok") requests=\(fake.requests.count)" },
                timeout: timeout, finishTimeout: finishTimeout, nowMs: { clock }))
        } catch {
            return .failure(error)
        }
    }

    static func signInError(_ result: Result<ChatGPTSession, Error>) -> ChatGPTSignInError? {
        if case .failure(let error) = result { return error as? ChatGPTSignInError }
        return nil
    }

    static func shown(_ browser: Browser) async -> String? {
        for _ in 0..<50 {
            if let page = browser.shown.value { return page }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    static func signIns() async throws {
        let signer = try Signer(kid: "k1")
        let browser = Browser()
        let fake = try await issuer(signer: signer, browser: browser, scope: "openid email " + ChatGPTSignIn.planScope)
        defer { fake.stop() }
        let registered = Box<[String]>([])
        let result = await signIn(fake, browser: browser, clientID: nil, answer: { "code=c1&state=\($0["state"] ?? "")&client_id=issued-1" },
                                  registered: registered)
        let session = try result.get()
        let authorize = browser.authorize.value
        try check(authorize["client_id"] == "dynamic_agent_client" && authorize["agent_name_hint"] == "woowtech agent"
                    && authorize["ext_agent_host_id"] == "urn:uuid:h" && authorize["response_type"] == "code"
                    && authorize["scope"] == ChatGPTSignIn.scopes && authorize["resource"] == ChatGPTSignIn.resource
                    && authorize["code_challenge_method"] == "S256", "a first sign-in registers with the App name and host id")
        let exchange = fake.requests.first { $0.path == "/api/accounts/oauth/token" }?.form ?? [:]
        try check(exchange["grant_type"] == "authorization_code" && exchange["client_id"] == "issued-1" && exchange["code"] == "c1"
                    && exchange["redirect_uri"] == authorize["redirect_uri"] && exchange["resource"] == ChatGPTSignIn.resource,
                  "the code is exchanged with the issued client id and the same redirect")
        try check(PKCE.challenge(exchange["code_verifier"] ?? "") == authorize["code_challenge"], "the exchange proves the authorize challenge")
        try check(registered.value == ["issued-1"], "the new client id is handed over before the exchange")
        try check(session.clientId == "issued-1" && session.sub == "user-1" && session.email == "a@b.test" && session.accessToken == "at"
                    && session.refreshToken == "rt" && session.expiresAtMs == clock + 3_600_000 && session.planUsage,
                  "the session holds the client, identity, tokens and plan scope")
        try check(await shown(browser) == "result=ok requests=2", "the browser's page comes after the exchange and the JWKS")

        let noPlan = Browser()
        let planless = try await issuer(signer: signer, browser: noPlan, scope: "openid email")
        defer { planless.stop() }
        let noPlanRegistered = Box<[String]>([])
        let refused = await signIn(planless, browser: noPlan, clientID: "issued-1", answer: { "code=c1&state=\($0["state"] ?? "")" },
                                   registered: noPlanRegistered)
        try check(signInError(refused)?.reason == .noPlanScope && noPlan.authorize.value["client_id"] == "issued-1"
                    && noPlanRegistered.value.isEmpty, "without the plan scope the sign-in fails; a known client isn't registered again")
        try check(await shown(noPlan) == "result=noPlanScope requests=2", "the browser is told why")

        let expiredCode = Browser()
        let rejecting = try await issuer(signer: signer, browser: expiredCode, scope: "",
                                         token: .json(400, #"{"error":"invalid_grant","error_description":"Invalid authorization code"}"#))
        defer { rejecting.stop() }
        let rejected = await signIn(rejecting, browser: expiredCode, clientID: "issued-1", answer: { "code=c1&state=\($0["state"] ?? "")" })
        try check(signInError(rejected)?.reason == .codeExpired && signInError(rejected)?.code == "invalid_grant",
                  "a refused exchange is worded and keeps the code")
        try check(await shown(expiredCode) == "result=codeExpired requests=1", "the browser shows the same reason")

        let slow = Browser()
        let slowIssuer = try await issuer(signer: signer, browser: slow, scope: "",
                                          token: FakeServer.Reply(status: 200, chunks: ["{}"], delay: 3))
        defer { slowIssuer.stop() }
        let started = Date()
        let late = await signIn(slowIssuer, browser: slow, clientID: "issued-1", answer: { "code=c1&state=\($0["state"] ?? "")" },
                                finishTimeout: 0.5)
        try check(signInError(late)?.reason == .network && (signInError(late)?.detail.contains("no answer") ?? false)
                    && Date().timeIntervalSince(started) < 2.5, "the steps after the callback have a deadline")

        let away = Browser()
        let awayIssuer = try await issuer(signer: signer, browser: away, scope: "")
        defer { awayIssuer.stop() }
        let timedOut = await signIn(awayIssuer, browser: away, clientID: nil, answer: { _ in nil }, timeout: 0.5)
        try check(signInError(timedOut)?.reason == .timedOut && away.opened.value, "no callback in time is a timeout")

        let denied = Browser()
        let deniedIssuer = try await issuer(signer: signer, browser: denied, scope: "")
        defer { deniedIssuer.stop() }
        let deniedResult = await signIn(deniedIssuer, browser: denied, clientID: nil,
                                        answer: { "error=access_denied&state=\($0["state"] ?? "")" })
        try check(signInError(deniedResult)?.reason == .denied && deniedIssuer.requests.isEmpty, "a refusal exchanges nothing")

        let hinted = Browser()
        let hintIssuer = try await issuer(signer: signer, browser: hinted, scope: ChatGPTSignIn.planScope)
        defer { hintIssuer.stop() }
        let previous = ChatGPTSession(clientId: "issued-1", sub: "user-1", email: "a@b.test", accessToken: "old", refreshToken: "old",
                                      idToken: "prev.id.token", expiresAtMs: clock, scopes: [ChatGPTSignIn.planScope])
        _ = await signIn(hintIssuer, browser: hinted, clientID: "issued-1", previous: previous, answer: { "code=c1&state=\($0["state"] ?? "")" })
        try check(hinted.authorize.value["id_token_hint"] == "prev.id.token" && hinted.authorize.value["login_hint"] == "a@b.test"
                    && hinted.authorize.value["agent_name_hint"] == nil, "a later sign-in sends the earlier ID token and email")
        let signedOut = Browser()
        let outIssuer = try await issuer(signer: signer, browser: signedOut, scope: ChatGPTSignIn.planScope)
        defer { outIssuer.stop() }
        _ = await signIn(outIssuer, browser: signedOut, clientID: "issued-1", previous: previous.signedOut(),
                         answer: { "code=c1&state=\($0["state"] ?? "")" })
        try check(signedOut.authorize.value["id_token_hint"] == nil && signedOut.authorize.value["login_hint"] == "a@b.test",
                  "after signing out only the email is a hint")

        let cancelling = Browser()
        let cancelIssuer = try await issuer(signer: signer, browser: cancelling, scope: "")
        defer { cancelIssuer.stop() }
        let task = Task { await signIn(cancelIssuer, browser: cancelling, clientID: nil, answer: { _ in nil }) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let cancelled = await task.value
        if case .failure(let error) = cancelled { try check(error is CancellationError, "cancelling a sign-in throws CancellationError") }
        else { try check(false, "cancelling a sign-in does not sign in") }
    }

    // MARK: - Token refresh

    static func tokenRefresh() async throws {
        let replies = Box<[FakeServer.Reply]>([])
        let fake = try await FakeServer.start { _ in
            var next = FakeServer.Reply.json(500, "{}")
            replies.update { if !$0.isEmpty { next = $0.removeFirst() } }
            return next
        }
        defer { fake.stop() }
        let auth = ChatGPTAuthClient(issuer: fake.base)
        func session(expiresAt: Int64 = clock + 3_600_000, refreshToken: String = "rt") -> ChatGPTSession {
            ChatGPTSession(clientId: "client-1", sub: "user-1", email: "a@b.test", accessToken: "at", refreshToken: refreshToken,
                           idToken: "it", expiresAtMs: expiresAt, scopes: [ChatGPTSignIn.planScope])
        }
        let stored = Box<ChatGPTSession?>(session())
        let tokens = ChatGPTTokens(auth: auth, load: { stored.value }, save: { stored.value = $0 }, nowMs: { clock })
        func failure(_ fresh: Bool = false) async -> ChatGPTModelError? {
            do { _ = try await tokens.token(fresh: fresh); return nil } catch { return error as? ChatGPTModelError }
        }
        try check(try await tokens.token(fresh: false) == "at" && fake.requests.isEmpty, "a token far from expiry is used as is")
        stored.value = session(expiresAt: clock + 60_000)
        replies.value = [.json(200, #"{"access_token":"at2","refresh_token":"rt2","expires_in":3600,"scope":"chatgpt.tokens.use.direct openid"}"#)]
        try check(try await tokens.token(fresh: false) == "at2", "a token about to expire is refreshed")
        try check(stored.value?.refreshToken == "rt2" && stored.value?.expiresAtMs == clock + 3_600_000, "the rotated pair is saved")
        try check(fake.requests.last?.form["refresh_token"] == "rt" && fake.requests.last?.form["grant_type"] == "refresh_token",
                  "the refresh sends the old refresh token")
        replies.value = [.json(200, #"{"access_token":"at3","expires_in":3600}"#)]
        try check(try await tokens.token(fresh: true) == "at3" && stored.value?.refreshToken == "rt2",
                  "a refused token is refreshed even before expiry; an answer without a new refresh token keeps the old one")
        try check(fake.requests.last?.form["refresh_token"] == "rt2", "the next refresh uses the rotated refresh token")

        stored.value = session(expiresAt: 0)
        replies.value = [.json(503, "")]
        try check(await failure() == .server(503) && stored.value?.signedIn == true, "a server failure keeps the sign-in")
        replies.value = [.json(401, #"{"error":"invalid_client"}"#)]
        try check(await failure() == .auth && stored.value?.signedIn == true, "a non-terminal refusal keeps the sign-in")
        replies.value = [.json(200, #"{"access_token":"at4","expires_in":3600,"scope":"openid"}"#)]
        try check(await failure() == .notEligible("") && stored.value?.planUsage == false, "a refresh without the plan scope is not eligible")
        stored.value = session(expiresAt: 0)
        replies.value = [.json(400, #"{"error":"invalid_grant"}"#)]
        try check(await failure() == .signInExpired && stored.value?.signedIn == false && stored.value?.clientId == "client-1",
                  "a dead refresh token signs out and keeps the client id")
        let count = fake.requests.count
        try check(await failure() == .signInExpired && fake.requests.count == count, "signed out asks nothing")
        stored.value = session(expiresAt: 0, refreshToken: "")
        try check(await failure() == .signInExpired && stored.value?.accessToken == "", "no refresh token is signed out")

        stored.value = session(expiresAt: 0)
        replies.value = [FakeServer.Reply(status: 200, chunks: [#"{"access_token":"at5","refresh_token":"rt5","expires_in":3600,"scope":"chatgpt.tokens.use.direct"}"#],
                                          delay: 0.3)]
        let before = fake.requests.count
        async let one = tokens.token(fresh: false)
        async let two = tokens.token(fresh: false)
        let both = try await [one, two]
        try check(both == ["at5", "at5"] && fake.requests.count == before + 1, "concurrent calls share one refresh")
    }

    // MARK: - Responses

    static func responsesRequests() throws {
        let messages = [ResponsesRequest.Message(role: .system, text: "Earlier summary"),
                        ResponsesRequest.Message(role: .user, text: "What is this?", images: ["data:image/png;base64,AAAA"]),
                        ResponsesRequest.Message(role: .assistant, text: "A cat."),
                        ResponsesRequest.Message(role: .assistant, text: ""),
                        ResponsesRequest.Message(role: .user, text: "")]
        let body = ResponsesRequest.body(model: "gpt-x", instructions: "Be brief.", messages: messages, vision: true)
        try check(Set(body.keys) == ["model", "instructions", "input", "store", "stream"], "only Play's fields: no tools, temperature or limit")
        try check(body["store"] as? Bool == false && body["stream"] as? Bool == true, "streamed and never stored")
        let input = body["input"] as? [[String: Any]] ?? []
        guard input.count == 3 else { throw Failure(message: "empty messages are left out (got \(input.count) items)") }
        try check(input[0]["role"] as? String == "developer", "a conversation's system message becomes a developer message")
        let content = input[1]["content"] as? [[String: Any]] ?? []
        try check(content.count == 2 && content[0]["type"] as? String == "input_text" && content[1]["type"] as? String == "input_image"
                    && content[1]["image_url"] as? String == "data:image/png;base64,AAAA", "text then the image")
        let reply = (input[2]["content"] as? [[String: Any]])?.first
        try check(input[2]["role"] as? String == "assistant" && reply?["type"] as? String == "output_text", "earlier replies are output_text")
        let blind = ResponsesRequest.body(model: "m", instructions: "", messages: [messages[1]], vision: false,
                                          reasoningEffort: "high", includeReasoning: true)
        let blindContent = ((blind["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        try check(blindContent.last?["text"] as? String == ResponsesRequest.imageOmitted, "a model that can't see gets Play's stand-in")
        try check(blind["instructions"] == nil && (blind["reasoning"] as? [String: String]) == ["effort": "high"]
                    && (blind["include"] as? [String]) == [ResponsesRequest.encryptedReasoning], "effort and include only when asked")
        let request = try ResponsesRequest.urlRequest(base: ChatGPTSignIn.apiBase, token: "t", body: body, headers: ["User-Agent": "woowtech-agent/1.0"])
        try check(request.url?.absoluteString == "https://api.openai.com/v1/responses" && request.httpMethod == "POST",
                  "POST {base}/responses")
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer t" && request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
                    && request.value(forHTTPHeaderField: "User-Agent") == "woowtech-agent/1.0", "the token, the stream and the App's headers")
        try check(ResponsesRequest.refusedInclude(status: 400, body: Data(#"{"error":{"param":"include","message":"no"}}"#.utf8))
                    && ResponsesRequest.refusedInclude(status: 400, body: Data("reasoning.encrypted_content is not supported".utf8))
                    && !ResponsesRequest.refusedInclude(status: 400, body: Data(#"{"error":{"param":"model"}}"#.utf8))
                    && !ResponsesRequest.refusedInclude(status: 401, body: Data(#"{"error":{"param":"include"}}"#.utf8)),
                  "only a 400 about include is sent again")
    }

    static func feed(_ text: String) -> (deltas: [String], result: Result<ResponsesReply, Error>) {
        var stream = ResponsesEventStream(chatGPTPlan: true, model: "gpt-x")
        var deltas: [String] = []
        do {
            for byte in Array(text.utf8) {
                if let delta = try stream.append(byte) { deltas.append(delta) }
            }
            return (deltas, .success(try stream.end()))
        } catch {
            return (deltas, .failure(error))
        }
    }

    static func event(_ json: String) -> String { "data: " + json + "\n\n" }

    static func modelError(_ result: Result<ResponsesReply, Error>) -> ChatGPTModelError? {
        if case .failure(let error) = result { return error as? ChatGPTModelError }
        return nil
    }

    static func responsesStreams() throws {
        let usage = #""usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":2},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":1}}"#
        let normal = "event: response.created\n" + event(#"{"type":"response.created","response":{}}"#)
            + event(#"{"type":"response.output_text.delta","delta":"Hel"}"#) + ": keep-alive\n\n"
            + event(#"{"type":"response.output_text.delta","delta":"lo"}"#)
            + event(#"{"type":"response.output_item.done","item":{"type":"reasoning","summary":[{"type":"summary_text","text":"Thought."}]}}"#)
            + event(#"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"output_text","text":"Hello"}]}}"#)
            + event(#"{"type":"response.completed","response":{"status":"completed",\#(usage)}}"#)
            + event(#"{"type":"response.output_text.delta","delta":"ignored"}"#) + "data: [DONE]\n\n"
        let (deltas, result) = feed(normal)
        let reply = try result.get()
        try check(deltas == ["Hel", "lo"] && reply.text == "Hello" && reply.thinking == "Thought." && reply.stop == .endTurn,
                  "deltas as they come, the finished text and the reasoning summary")
        try check(reply.usage == ResponsesUsage(input: 10, output: 5, cachedInput: 2, reasoning: 1), "usage from response.usage")
        try check(try feed(normal.replacingOccurrences(of: "\n", with: "\r\n")).result.get() == reply, "CRLF lines read the same")
        let truncated = feed(event(#"{"type":"response.output_text.delta","delta":"Part"}"#)
            + event(#"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"#))
        try check((try? truncated.result.get()) == ResponsesReply(text: "Part", thinking: "", usage: nil, stop: .maxTokens),
                  "an incomplete reply keeps the streamed text and says it was cut at the limit")
        try check(modelError(feed(event(#"{"type":"response.output_text.delta","delta":"Hi"}"#)).result) == .streamCut,
                  "a stream that ends before its end event was cut off")
        try check(modelError(feed(event(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}"#)).result)
                    == .limitReached, "the plan's limit")
        try check(modelError(feed(event(#"{"type":"error","error":{"code":"rate_limit_exceeded","message":"slow down"}}"#)).result)
                    == .limitReached, "a rate limit on the plan is its limit")
        try check(modelError(feed(event(#"{"type":"error","code":"subscription_sharing_user_not_eligible","message":"not here"}"#)).result)
                    == .notEligible("not here"), "an error event without an error object")
        if case .badResponse(let said)? = modelError(feed(event(#"{"type":"error","error":{"code":"weird_code","message":"odd"}}"#)).result) {
            try check(said == "weird_code odd", "an unknown code is passed on with its words")
        } else { try check(false, "an unknown code is a bad response") }
        try check(modelError(feed("data: {not json\n\n").result) != nil, "an event that isn't JSON fails")
        try check(modelError(feed(event(#"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"refusal","refusal":"no"}]}}"#)
                                  + event(#"{"type":"response.completed","response":{}}"#)).result) == .contentRefused, "a refusal")
        try check(modelError(feed(event(#"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}"#)).result)
                    == .contentRefused, "a filtered reply with no text")
        let whole = try ResponsesEventStream.reply(fromBody: Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Whole"}]}],"usage":{"input_tokens":3,"output_tokens":1}}"#.utf8),
                                                   chatGPTPlan: true, model: "gpt-x")
        try check(whole.text == "Whole" && whole.usage == ResponsesUsage(input: 3, output: 1, cachedInput: 0, reasoning: 0),
                  "a whole response object instead of a stream")
        func http(_ status: Int, _ body: String = "", plan: Bool = true) -> ChatGPTModelError {
            ChatGPTModelError.http(status: status, body: Data(body.utf8), retryAfter: "7", chatGPTPlan: plan, model: "gpt-x")
        }
        try check(http(401) == .auth && http(402) == .quotaExceeded && http(404) == .modelNotFound("gpt-x") && http(502) == .server(502)
                    && http(418) == .badResponse("HTTP 418"), "plain statuses")
        try check(http(403, #"{"error":{"message":"not allowed"}}"#) == .notEligible("not allowed") && http(403, plan: false) == .auth,
                  "403 on the plan: the account may not use it this way")
        try check(http(429) == .limitReached && http(429, plan: false) == .rateLimited(retryAfterMs: 7000), "429 on the plan is its limit")
        try check(http(400, #"{"error":{"code":"context_length_exceeded","message":"long"}}"#) == .contextTooLong
                    && http(400, #"{"error":{"code":"subscription_sharing_usage_unavailable"}}"#) == .server(503)
                    && http(400, #"{"error":{"type":"insufficient_quota"}}"#) == .quotaExceeded
                    && http(403, #"{"error":{"code":"chatpass_v2_scope_not_authorized"}}"#) == .auth, "the body's code comes first")
    }

    static func responsesClient() async throws {
        let replies = Box<[FakeServer.Reply]>([])
        let fake = try await FakeServer.start { _ in
            var next = FakeServer.Reply.json(500, "{}")
            replies.update { if !$0.isEmpty { next = $0.removeFirst() } }
            return next
        }
        defer { fake.stop() }
        let freshAsked = Box<[Bool]>([])
        let client = ChatGPTResponsesClient(base: URL(string: fake.base + "/v1")!, headers: ["User-Agent": "woowtech-agent/1.0"]) { fresh in
            freshAsked.update { $0.append(fresh) }
            return fresh ? "new" : "old"
        }
        let stream = [event(#"{"type":"response.output_text.delta","delta":"Hi "}"#), event(#"{"type":"response.output_text.delta","delta":"there"}"#),
                      event(#"{"type":"response.completed","response":{"usage":{"input_tokens":4,"output_tokens":2}}}"#)]
        replies.value = [.json(401, #"{"error":{"code":"invalid_api_key"}}"#),
                         FakeServer.Reply(status: 200, type: "text/event-stream", chunks: stream, gap: 0.05)]
        let deltas = Box<[String]>([])
        let messages = [ResponsesRequest.Message(role: .user, text: "Hello")]
        let reply = try await client.complete(model: "gpt-x", instructions: "Be brief.", messages: messages, vision: false) { delta in
            deltas.update { $0.append(delta) }
        }
        try check(reply.text == "Hi there" && deltas.value == ["Hi ", "there"] && reply.usage?.input == 4, "a streamed reply over HTTP")
        try check(freshAsked.value == [false, true] && fake.requests.map { $0.headers["authorization"] ?? "" } == ["Bearer old", "Bearer new"],
                  "a 401 gets one fresh token")
        let sent = fake.requests.last?.json ?? [:]
        try check(fake.requests.last?.path == "/v1/responses" && sent["store"] as? Bool == false && sent["stream"] as? Bool == true
                    && sent["instructions"] as? String == "Be brief." && fake.requests.last?.headers["user-agent"] == "woowtech-agent/1.0",
                  "the request on the wire")

        replies.value = [.json(400, #"{"error":{"param":"include","message":"include is not supported"}}"#),
                         FakeServer.Reply(status: 200, type: "text/event-stream", chunks: stream, gap: 0)]
        let count = fake.requests.count
        _ = try await client.complete(model: "gpt-x", instructions: "", messages: messages, vision: false, includeReasoning: true)
        let tries = Array(fake.requests.dropFirst(count))
        try check(tries.count == 2 && tries[0].json["include"] != nil && tries[1].json["include"] == nil, "a refused include is dropped once")

        func failure(_ reply: FakeServer.Reply) async -> ChatGPTModelError? {
            replies.value = [reply]
            do { _ = try await client.complete(model: "gpt-x", instructions: "", messages: messages, vision: false); return nil }
            catch { return error as? ChatGPTModelError }
        }
        let beforeLimit = fake.requests.count
        try check(await failure(.json(429, #"{"error":{"message":"limit"}}"#)) == .limitReached && fake.requests.count == beforeLimit + 1,
                  "the plan's limit ends the call without retrying")
        try check(await failure(FakeServer.Reply(status: 200, type: "text/event-stream", chunks: [stream[0], stream[1]], gap: 0)) == .streamCut,
                  "a stream closed before its end event")
        if case .network(_)? = await failure(FakeServer.Reply(hangUp: true)) {} else { try check(false, "no answer is a network failure") }
        replies.value = [.json(200, #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Whole"}]}]}"#)]
        try check(try await client.complete(model: "gpt-x", instructions: "", messages: messages, vision: false).text == "Whole",
                  "a JSON answer instead of a stream")
        let signedOut = ChatGPTResponsesClient(base: URL(string: fake.base + "/v1")!) { _ in throw ChatGPTModelError.signInExpired }
        let beforeSignedOut = fake.requests.count
        do {
            _ = try await signedOut.complete(model: "gpt-x", instructions: "", messages: messages, vision: false)
            try check(false, "a signed-out call fails")
        } catch {
            try check(error as? ChatGPTModelError == .signInExpired && fake.requests.count == beforeSignedOut, "signed out sends nothing")
        }
    }

    // MARK: - Model list

    static func models() throws {
        let table = #"""
        {"models":[
          {"slug":"gpt-5.1","display_name":"GPT-5.1","visibility":"list","input_modalities":["text","image"],"context_window":272000,
           "supported_reasoning_levels":[{"effort":"low","description":"Fast"},{"effort":"medium"},{"effort":"high"}]},
          {"slug":"internal-model","display_name":"Hidden","visibility":"hide"},
          {"slug":"gpt-5.1-mini","display_name":"GPT-5.1 mini","visibility":"list","input_modalities":["text"],
           "supported_reasoning_levels":["low","high","low"]},
          {"slug":"gpt-5.1","display_name":"Duplicate","visibility":"list"}]}
        """#
        let listed = ChatGPTSignIn.listedModels(Data(table.utf8)) ?? []
        try check(listed.map(\.id) == ["gpt-5.1", "gpt-5.1-mini"], "listed models keep the server's order, drop hidden and duplicates")
        try check(listed.first == ChatGPTListedModel(id: "gpt-5.1", displayName: "GPT-5.1", vision: true, contextTokens: 272000,
                                                     reasoningEfforts: ["low", "medium", "high"]), "the slug, label, image input, context and efforts")
        try check(listed.last?.vision == false && listed.last?.contextTokens == nil && listed.last?.reasoningEfforts == ["low", "high"],
                  "text only, no context given, efforts listed once")
        try check(ChatGPTSignIn.listedModels(Data(#"{"data":[{"id":"x"}]}"#.utf8)) == [ChatGPTListedModel(id: "x", displayName: "", vision: nil,
                                                                                                        contextTokens: nil, reasoningEfforts: nil)],
                  "a plain list reads too")
        try check(ChatGPTSignIn.listedModels(Data("nope".utf8)) == nil && ChatGPTSignIn.listedModels(Data(#"{"x":1}"#.utf8)) == nil,
                  "not a model list")
        let request = ChatGPTSignIn.modelsRequest(accessToken: "at", userAgent: "woowtech-agent/1.0")
        try check(request.url?.absoluteString == "https://api.openai.com/v1/models" && request.value(forHTTPHeaderField: "Authorization") == "Bearer at",
                  "GET {base}/models with the access token")
    }
}
