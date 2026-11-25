@testable import AssistantMCP
@testable import AssistantModels
import Foundation
import Network

/// The MCP OAuth sign-in, offline (Sources/AssistantMCP: MCPOAuth.swift, MCPClient.swift and
/// MCPHTTPTransport.swift; Sources/App: MCPSettings.swift and MCPSession.swift): the 401 challenge,
/// the spec's order for resource and authorization server metadata, registration or a client the user
/// entered, the authorize URL and callback, the code exchange with PKCE, refreshes with rotation, a
/// client that refreshes once after a 401, and the server page's sign-in, sign-in-needed and sign-out.
/// Fake authorization servers run on 127.0.0.1; the HTTPS hosts MCPClient and the server page need
/// exist only in this process (FakeHTTPS). Nothing here reaches a real server.
struct Failure: Error { let message: String }

/// A value shared with fake servers and callbacks.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    @discardableResult func update<T>(_ change: (inout Value) -> T) -> T { lock.lock(); defer { lock.unlock() }; return change(&stored) }
}

struct FakeRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    /// Lowercase names.
    let headers: [String: String]
    let body: Data
    var form: [String: String] { LoopbackCallbackServer.parseQuery(String(decoding: body, as: UTF8.self)) ?? [:] }
    var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:] }
    var bearer: String? {
        guard let value = headers["authorization"], value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst(7))
    }
}

struct FakeReply: Sendable {
    var status = 200
    var headers = ["Content-Type": "application/json"]
    var body = ""

    static func json(_ status: Int, _ body: String) -> FakeReply { FakeReply(status: status, body: body) }
    static func redirect(_ location: String) -> FakeReply { FakeReply(status: 302, headers: ["Location": location]) }
}

typealias FakeHandler = @Sendable (FakeRequest) -> FakeReply

/// A tiny HTTP/1.1 server on 127.0.0.1: one request per connection, answers from `handler`.
final class FakeServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fake-oauth-server")
    private var listener: NWListener?
    private let handler: FakeHandler
    private(set) var port: UInt16 = 0

    private init(_ handler: @escaping FakeHandler) { self.handler = handler }

    static func start(_ handler: @escaping FakeHandler) async throws -> FakeServer {
        let server = FakeServer(handler)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let started = Box(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !started.update({ was in defer { was = true }; return was }) else { return }
                    server.port = listener.port?.rawValue ?? 0
                    continuation.resume()
                case .failed(let error):
                    guard !started.update({ was in defer { was = true }; return was }) else { return }
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
                    let request = FakeRequest(method: parts.first ?? "", path: path,
                                              query: LoopbackCallbackServer.parseQuery(query) ?? [:], headers: headers,
                                              body: buffer.subdata(in: end.upperBound..<end.upperBound + length))
                    return self.answer(connection, self.handler(request))
                }
            }
            if error != nil || isComplete { return connection.cancel() }
            self.read(connection, buffer)
        }
    }

    private func answer(_ connection: NWConnection, _ reply: FakeReply) {
        var head = "HTTP/1.1 \(reply.status) Fake\r\nConnection: close\r\nContent-Length: \(reply.body.utf8.count)\r\n"
        for (name, value) in reply.headers { head += name + ": " + value + "\r\n" }
        connection.send(content: Data((head + "\r\n" + reply.body).utf8), isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// HTTPS hosts that exist only in this process (MCPClient and the server page take HTTPS only). Other
/// requests, the loopback listener's included, go to the network stack as usual.
final class FakeHTTPS: URLProtocol {
    private static let lock = NSLock()
    private static var hosts: [String: FakeHandler] = [:]

    static func register(_ host: String, _ handler: @escaping FakeHandler) { lock.lock(); hosts[host] = handler; lock.unlock() }
    static func remove(_ host: String) { lock.lock(); hosts[host] = nil; lock.unlock() }

    static func handler(_ request: URLRequest) -> FakeHandler? {
        guard request.url?.scheme == "https", let host = request.url?.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        return hosts[host]
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeHTTPS.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { handler(request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler(request) else {
            return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let headers = Dictionary((request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        let reply = handler(FakeRequest(method: request.httpMethod ?? "GET", path: parts?.percentEncodedPath ?? "",
                                        query: LoopbackCallbackServer.parseQuery(parts?.percentEncodedQuery ?? "") ?? [:],
                                        headers: headers, body: body))
        // A redirect is handed over as it is: the session decides, as with a real server.
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// An MCP endpoint and its authorization server, shaped like Higgsfield's (the issuer has a path): the
/// endpoint answers 401 with a challenge unless it gets the current token; the authorize endpoint
/// redirects with a code bound to the PKCE challenge, client, redirect and resource; the token endpoint
/// checks the code_verifier and the rest against it and rotates refresh tokens.
final class FakeAuthorization: @unchecked Sendable {
    struct Options {
        /// The 401's `resource_metadata` path; nil leaves it out.
        var challengePath: String? = "/meta/protected"
        var challengeScope: String? = "openid email offline_access"
        /// Where resource metadata answers, and paths that redirect to it instead.
        var protectedPaths: Set<String> = ["/meta/protected"]
        var redirectPaths: [String: String] = [:]
        /// The resource metadata's `resource`: nil the endpoint, "" left out.
        var resource: String?
        var scopesSupported: [String]?
        /// The resource metadata's authorization server: nil this server at `issuerPath`.
        var authorizationServer: String?
        var issuerPath = "/_clerk"
        /// Where authorization server metadata answers, and whether that copy names the registration endpoint.
        var metadataPaths = ["/.well-known/oauth-authorization-server/_clerk": true, "/_clerk/.well-known/openid-configuration": false]
        var challengeMethods: [String]? = ["S256"]
        var authMethods: [String]? = ["none"]
        var issParameter = false
        /// The authorize redirect's `iss`: nil none.
        var iss: String?
        /// The authorize endpoint's refusal, if any.
        var denied: String?
        var expiresIn: Int? = 3600
        var rotates = true
        /// The token endpoint's answer to every refresh, if not the usual one.
        var refreshRefused: FakeReply?
        /// The endpoint refuses every token.
        var refusesAll = false
        /// The endpoint answers 403 insufficient_scope.
        var insufficientScope = false
    }

    let options: Box<Options>
    let base: Box<String>
    let log = Box<[FakeRequest]>([])
    /// code → (client, challenge, redirect, resource)
    let codes = Box<[String: (client: String, challenge: String, redirect: String, resource: String)]>([:])
    let refreshTokens = Box<Set<String>>([])
    let clients = Box<[String: String]>(["user-client": "", "secret-client": "s:e/c"])
    /// The access token the endpoint takes.
    let current = Box("")
    private let serial = Box(0)

    init(base: String, _ configure: (inout Options) -> Void = { _ in }) {
        var options = Options()
        configure(&options)
        self.options = Box(options)
        self.base = Box(base)
    }

    var endpoint: String { base.value + "/mcp" }
    var issuer: String { base.value + options.value.issuerPath }
    var paths: [String] { log.value.map(\.path) }
    func requests(_ path: String) -> [FakeRequest] { log.value.filter { $0.path == path } }

    static func loopback(_ configure: (inout Options) -> Void = { _ in }) async throws -> (FakeAuthorization, FakeServer) {
        let fake = FakeAuthorization(base: "", configure)
        let server = try await FakeServer.start { fake.handle($0) }
        fake.base.value = server.base
        return (fake, server)
    }

    private func next(_ prefix: String) -> String { prefix + String(serial.update { $0 += 1; return $0 }) }

    func handle(_ request: FakeRequest) -> FakeReply {
        log.update { $0.append(request) }
        let options = options.value
        switch request.path {
        case "/mcp": return mcp(request, options)
        case "/register": return register(request)
        case options.issuerPath + "/authorize": return authorize(request, options)
        case options.issuerPath + "/token": return token(request, options)
        default:
            if let target = options.redirectPaths[request.path] { return .redirect(base.value + target) }
            if options.protectedPaths.contains(request.path) {
                var metadata: [String: Any] = ["authorization_servers": [options.authorizationServer ?? issuer]]
                if options.resource != "" { metadata["resource"] = options.resource ?? endpoint }
                if let scopes = options.scopesSupported { metadata["scopes_supported"] = scopes }
                return .json(200, Self.text(metadata))
            }
            if let registers = options.metadataPaths[request.path] {
                var metadata: [String: Any] = ["issuer": issuer, "authorization_endpoint": issuer + "/authorize",
                                               "token_endpoint": issuer + "/token", "response_types_supported": ["code"],
                                               "authorization_response_iss_parameter_supported": options.issParameter]
                if registers { metadata["registration_endpoint"] = base.value + "/register" }
                if let methods = options.challengeMethods { metadata["code_challenge_methods_supported"] = methods }
                if let methods = options.authMethods { metadata["token_endpoint_auth_methods_supported"] = methods }
                return .json(200, Self.text(metadata))
            }
            return .json(404, #"{"error":"not_found"}"#)
        }
    }

    private func mcp(_ request: FakeRequest, _ options: Options) -> FakeReply {
        if options.insufficientScope {
            return FakeReply(status: 403, headers: ["WWW-Authenticate": #"Bearer error="insufficient_scope", scope="admin""#])
        }
        guard let token = request.bearer, token == current.value, !options.refusesAll else {
            var parts: [String] = []
            if let path = options.challengePath { parts.append(#"resource_metadata="\#(base.value + path)""#) }
            if let scope = options.challengeScope { parts.append(#"scope="\#(scope)""#) }
            if request.bearer != nil { parts.append(#"error="invalid_token""#) }
            return FakeReply(status: 401, headers: ["WWW-Authenticate": parts.isEmpty ? "Bearer" : "Bearer " + parts.joined(separator: ", ")])
        }
        let call = request.json
        let id = call["id"] as? String ?? ""
        switch call["method"] as? String {
        case "initialize":
            return .json(200, #"{"jsonrpc":"2.0","id":"\#(id)","result":{"protocolVersion":"2025-03-26","capabilities":{"tools":{}},"serverInfo":{"name":"fake","version":"1"}}}"#)
        case "notifications/initialized":
            return FakeReply(status: 202, headers: [:])
        case "tools/list":
            return .json(200, #"{"jsonrpc":"2.0","id":"\#(id)","result":{"tools":[{"name":"echo","inputSchema":{"type":"object"}}]}}"#)
        default:
            return .json(200, #"{"jsonrpc":"2.0","id":"\#(id)","result":{}}"#)
        }
    }

    private func register(_ request: FakeRequest) -> FakeReply {
        let body = request.json
        guard body["client_name"] as? String == ChatGPTSignIn.appName, body["token_endpoint_auth_method"] as? String == "none",
              let redirects = body["redirect_uris"] as? [String], redirects.count == 1,
              redirects[0].hasPrefix("http://127.0.0.1:"), redirects[0].hasSuffix("/auth/callback"),
              body["grant_types"] as? [String] == ["authorization_code", "refresh_token"],
              body["response_types"] as? [String] == ["code"] else {
            return .json(400, #"{"error":"invalid_client_metadata"}"#)
        }
        let id = next("client-")
        clients.update { $0[id] = "" }
        return .json(201, #"{"client_id":"\#(id)","token_endpoint_auth_method":"none"}"#)
    }

    private func authorize(_ request: FakeRequest, _ options: Options) -> FakeReply {
        let query = request.query
        guard let redirect = query["redirect_uri"], var back = URLComponents(string: redirect) else { return .json(400, "{}") }
        var items = [URLQueryItem(name: "state", value: query["state"])]
        if let iss = options.iss { items.append(URLQueryItem(name: "iss", value: iss)) }
        if let denied = options.denied {
            back.queryItems = items + [URLQueryItem(name: "error", value: denied)]
            return .redirect(back.string ?? "")
        }
        guard query["response_type"] == "code", let client = query["client_id"], clients.value[client] != nil,
              query["code_challenge_method"] == "S256", let challenge = query["code_challenge"], !challenge.isEmpty,
              query["state"]?.isEmpty == false, let resource = query["resource"] else {
            back.queryItems = items + [URLQueryItem(name: "error", value: "invalid_request")]
            return .redirect(back.string ?? "")
        }
        let code = next("code-")
        codes.update { $0[code] = (client, challenge, redirect, resource) }
        back.queryItems = [URLQueryItem(name: "code", value: code)] + items
        return .redirect(back.string ?? "")
    }

    /// The client's id from a form or HTTP Basic, if its secret (when it has one) is right.
    private func client(_ request: FakeRequest) -> String? {
        let form = request.form
        if let basic = request.headers["authorization"], basic.hasPrefix("Basic "),
           let decoded = Data(base64Encoded: String(basic.dropFirst(6))).map({ String(decoding: $0, as: UTF8.self) }),
           let colon = decoded.firstIndex(of: ":") {
            let id = String(decoded[..<colon]).removingPercentEncoding ?? ""
            let secret = String(decoded[decoded.index(after: colon)...]).removingPercentEncoding ?? ""
            return form["client_id"] == nil && clients.value[id] == secret ? id : nil
        }
        guard let id = form["client_id"], let secret = clients.value[id] else { return nil }
        return (form["client_secret"] ?? "") == secret ? id : nil
    }

    private func token(_ request: FakeRequest, _ options: Options) -> FakeReply {
        let form = request.form
        guard let client = client(request) else { return .json(401, #"{"error":"invalid_client"}"#) }
        switch form["grant_type"] {
        case "authorization_code":
            guard let code = form["code"], let grant = codes.update({ $0.removeValue(forKey: code) }), grant.client == client,
                  form["redirect_uri"] == grant.redirect, PKCE.challenge(form["code_verifier"] ?? "") == grant.challenge else {
                return .json(400, #"{"error":"invalid_grant"}"#)
            }
            guard form["resource"] == grant.resource else { return .json(400, #"{"error":"invalid_target"}"#) }
            return issue(options, refresh: true)
        case "refresh_token":
            if let refused = options.refreshRefused { return refused }
            guard let token = form["refresh_token"], refreshTokens.value.contains(token) else {
                return .json(400, #"{"error":"invalid_grant"}"#)
            }
            guard form["resource"] == endpoint else { return .json(400, #"{"error":"invalid_target"}"#) }
            if options.rotates { refreshTokens.update { $0.remove(token) } }
            return issue(options, refresh: options.rotates)
        default:
            return .json(400, #"{"error":"unsupported_grant_type"}"#)
        }
    }

    private func issue(_ options: Options, refresh: Bool) -> FakeReply {
        let access = next("at-")
        current.value = access
        var answer: [String: Any] = ["access_token": access, "token_type": "Bearer"]
        if let expiresIn = options.expiresIn { answer["expires_in"] = expiresIn }
        if refresh {
            let token = next("rt-")
            refreshTokens.update { $0.insert(token) }
            answer["refresh_token"] = token
        }
        return .json(200, Self.text(answer))
    }

    static func text(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }
}

/// The person in the browser: opens the authorize page, which redirects back to the loopback listener,
/// and keeps the page the listener answers with. `state` replaces the callback's state.
enum Browser {
    static func follow(_ url: URL, state: String? = nil) async -> String? {
        let pages = URLSession(configuration: FakeHTTPS.configuration())
        guard let (_, response) = try? await pages.data(for: URLRequest(url: url), delegate: NoRedirects()),
              let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              var callback = URLComponents(string: location) else { return nil }
        if let state {
            callback.queryItems = callback.queryItems?.map { $0.name == "state" ? URLQueryItem(name: "state", value: state) : $0 }
        }
        guard let address = callback.url, let (data, answer) = try? await URLSession(configuration: .ephemeral).data(from: address) else {
            return nil
        }
        return "\((answer as? HTTPURLResponse)?.statusCode ?? 0) " + String(decoding: data, as: UTF8.self)
    }
}

/// The server page's browser (MCPSignInBrowsing), which follows the page like `Browser`.
@MainActor final class PageBrowser: MCPSignInBrowsing {
    var opened: [URL] = []
    var closes = 0
    var page: String?
    var follows = true
    private var closed: (@MainActor () -> Void)?

    func open(_ url: URL, closed: @escaping @MainActor () -> Void) {
        opened.append(url)
        self.closed = closed
        guard follows else { return }
        Task { self.page = await Browser.follow(url) }
    }

    func close() { closes += 1; closed = nil }
    func personCloses() { closed?() }
}

@main enum CheckMCPOAuth {
    #if DEBUG
    static let config = "Debug"
    #else
    static let config = "Release"
    #endif
    static var checks = 0
    /// Every failed assertion, so one run shows them all; a broken precondition still stops at once.
    static var failures: [String] = []
    static let clock: Int64 = 1_800_000_000_000
    static let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    static let higgsfield = #"Bearer resource_metadata="https://mcp.higgsfield.ai/.well-known/oauth-protected-resource/mcp", scope="openid email offline_access""#

    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { failures.append(message) }
    }

    @MainActor static func main() async {
        do {
            challenges()
            try addresses()
            try requests()
            callbacks()
            tokenAnswers()
            try sessions()
            try storage()
            try await discovery()
            try await signIns()
            try await refreshes()
            try await retries()
            try await serverPage()
        } catch let failure as Failure {
            failures.append(failure.message)
        } catch {
            failures.append("unexpected \(error)")
        }
        guard failures.isEmpty else {
            for failure in failures { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS MCP OAuth sign-in (\(config)): \(checks) assertions; loopback and in-process fakes only, no request to a real server")
    }

    static func error(_ body: () async throws -> Void) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }

    // MARK: - The challenge, addresses and requests

    static func challenges() {
        let challenge = MCPBearerChallenge(higgsfield)
        check(challenge?.resourceMetadata == "https://mcp.higgsfield.ai/.well-known/oauth-protected-resource/mcp"
                && challenge?.scope == "openid email offline_access" && challenge?.error == nil, "Higgsfield's 401 challenge reads")
        let mixed = MCPBearerChallenge(#"Basic realm="x", Newauth realm="apps", type=1, title="Login to \"apps\"", bearer Error="invalid_token", SCOPE=read, resource_metadata=https://a.test/meta,DPoP algs="ES256""#)
        check(mixed?.error == "invalid_token" && mixed?.scope == "read" && mixed?.resourceMetadata == "https://a.test/meta",
              "the Bearer challenge among others: any case, unquoted values, the next scheme ends it")
        let quoted = MCPBearerChallenge(#"Bearer realm="a \"b\", c", error_description="x, y", scope="s1 s2""#)
        check(quoted?.scope == "s1 s2" && quoted?.error == nil, "quoted strings with commas and escapes")
        check(MCPBearerChallenge(#"Basic dXNlcjpwYXNz==, Bearer scope="a", scope="b""#)?.scope == "a", "after a token68; the first copy of a parameter")
        check(MCPBearerChallenge("Bearer") != nil && MCPBearerChallenge("Bearer")?.scope == nil, "a bare Bearer challenge")
        check(MCPBearerChallenge(#"Basic realm="x""#) == nil && MCPBearerChallenge("") == nil && MCPBearerChallenge(nil) == nil,
              "no Bearer challenge")
    }

    static func addresses() throws {
        func strings(_ urls: [URL]) -> [String] { urls.map(\.absoluteString) }
        guard let endpoint = URL(string: "https://mcp.example.com/a/mcp?key=secret") else { throw Failure(message: "URL") }
        check(MCPOAuth.canonicalResource(URL(string: "HTTPS://MCP.Example.com:8443/tenant/mcp/?key=secret")!)
                == "https://mcp.example.com:8443/tenant/mcp", "canonical resource: lowercase, port kept, no trailing slash or query")
        check(MCPOAuth.canonicalResource(URL(string: "https://mcp.example.com/")!) == "https://mcp.example.com", "a root endpoint")
        check(strings(MCPOAuth.resourceMetadataURLs(endpoint: endpoint, challenge: MCPBearerChallenge(#"Bearer resource_metadata="https://meta.example.com/prm""#)))
                == ["https://meta.example.com/prm", "https://mcp.example.com/.well-known/oauth-protected-resource/a/mcp",
                    "https://mcp.example.com/.well-known/oauth-protected-resource"],
              "resource metadata: the challenge's, then the endpoint's path, then the root; never the query")
        check(strings(MCPOAuth.resourceMetadataURLs(endpoint: endpoint, challenge: MCPBearerChallenge(#"Bearer resource_metadata="http://meta.example.com/prm""#)))
                == ["https://mcp.example.com/.well-known/oauth-protected-resource/a/mcp",
                    "https://mcp.example.com/.well-known/oauth-protected-resource"], "a challenge address that isn't HTTPS is skipped")
        check(strings(MCPOAuth.resourceMetadataURLs(endpoint: URL(string: "https://mcp.example.com/")!, challenge: nil))
                == ["https://mcp.example.com/.well-known/oauth-protected-resource"], "a root endpoint asks the root once")
        check(strings(MCPOAuth.authorizationServerMetadataURLs(issuer: URL(string: "https://higgsfield.ai/_clerk")!))
                == ["https://higgsfield.ai/.well-known/oauth-authorization-server/_clerk",
                    "https://higgsfield.ai/.well-known/openid-configuration/_clerk",
                    "https://higgsfield.ai/_clerk/.well-known/openid-configuration"],
              "an issuer with a path: RFC 8414 insertion, OpenID insertion, then OpenID after the path")
        check(strings(MCPOAuth.authorizationServerMetadataURLs(issuer: URL(string: "https://auth.example.com/")!))
                == ["https://auth.example.com/.well-known/oauth-authorization-server", "https://auth.example.com/.well-known/openid-configuration"],
              "an issuer without a path: both at the root")
        check(MCPOAuth.allowed("https://a.test/x") != nil && MCPOAuth.allowed("http://127.0.0.1:9/x") != nil
                && MCPOAuth.allowed("http://localhost/x") != nil, "HTTPS, and HTTP on the loopback address")
        check([MCPOAuth.allowed("http://a.test/x"), MCPOAuth.allowed("https://u:p@a.test/x"), MCPOAuth.allowed("https://a.test/x#f"),
               MCPOAuth.allowed("ftp://a.test/x"), MCPOAuth.allowed("not a url"), MCPOAuth.allowed(nil)].allSatisfy { $0 == nil },
              "plain HTTP elsewhere, user info, fragments and other schemes are refused")
        let mcp = URL(string: "https://mcp.example.com/tenant/mcp")!
        check(MCPOAuth.covers(URL(string: "https://mcp.example.com/tenant/mcp")!, mcp) && MCPOAuth.covers(URL(string: "https://MCP.example.com")!, mcp)
                && MCPOAuth.covers(URL(string: "https://mcp.example.com/tenant/")!, mcp), "resource metadata about this server or a path above it")
        check(!MCPOAuth.covers(URL(string: "https://other.example.com/tenant/mcp")!, mcp) && !MCPOAuth.covers(URL(string: "https://mcp.example.com/ten")!, mcp)
                && !MCPOAuth.covers(URL(string: "https://mcp.example.com:444/tenant/mcp")!, mcp), "another host, a partial segment or another port is another server")
    }

    static func requests() throws {
        let server = MCPOAuthServer(resource: "https://mcp.example.com/mcp", issuer: "https://auth.example.com",
                                    authorizationEndpoint: URL(string: "https://auth.example.com/authorize?tenant=a%20b")!,
                                    tokenEndpoint: URL(string: "https://auth.example.com/token")!, registrationEndpoint: nil,
                                    scope: "openid email", issParameter: false, tokenAuthMethods: nil)
        let attempt = ChatGPTSignInAttempt(state: "st_ate", nonce: "n", verifier: verifier, redirectURI: "http://127.0.0.1:4321/auth/callback")
        check(MCPOAuth.authorizeURL(server, clientID: "client+1", attempt: attempt)?.absoluteString
                == "https://auth.example.com/authorize?tenant=a%20b&response_type=code&client_id=client%2B1"
                + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
                + "&code_challenge_method=S256&state=st_ate&resource=https%3A%2F%2Fmcp.example.com%2Fmcp&scope=openid%20email",
              "the authorize URL keeps the endpoint's query and adds PKCE S256, state, resource and scope")
        let unscoped = MCPOAuthServer(resource: server.resource, issuer: nil, authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
                                      tokenEndpoint: server.tokenEndpoint, registrationEndpoint: nil, scope: nil, issParameter: false, tokenAuthMethods: nil)
        check(MCPOAuth.authorizeURL(unscoped, clientID: "c", attempt: attempt)?.query?.contains("scope=") == false, "no scope is asked without one")
        let register = MCPOAuth.registrationRequest(URL(string: "https://auth.example.com/register")!, redirectURI: attempt.redirectURI, scope: "openid")
        let body = ((try? JSONSerialization.jsonObject(with: register.httpBody ?? Data())) as? [String: Any]) ?? [:]
        check(register.httpMethod == "POST" && register.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && body["client_name"] as? String == "woowtech agent" && body["redirect_uris"] as? [String] == [attempt.redirectURI]
                && body["token_endpoint_auth_method"] as? String == "none" && body["scope"] as? String == "openid"
                && body["grant_types"] as? [String] == ["authorization_code", "refresh_token"] && body["response_types"] as? [String] == ["code"],
              "registration: a public client named woowtech agent with the loopback redirect")
        func form(_ request: URLRequest) -> [String: String] {
            LoopbackCallbackServer.parseQuery(String(decoding: request.httpBody ?? Data(), as: UTF8.self)) ?? [:]
        }
        let exchange = MCPOAuth.exchangeRequest(server, client: MCPOAuthRegistration(id: "client+1"), code: "c/1", attempt: attempt)
        check(form(exchange) == ["grant_type": "authorization_code", "code": "c/1", "redirect_uri": attempt.redirectURI, "code_verifier": verifier,
                                 "resource": server.resource, "client_id": "client+1"]
                && exchange.value(forHTTPHeaderField: "Authorization") == nil && exchange.url == server.tokenEndpoint,
              "the exchange: code, redirect, verifier, resource and the public client's id")
        let post = MCPOAuth.exchangeRequest(server, client: MCPOAuthRegistration(id: "c", secret: "s", auth: "client_secret_post"),
                                            code: "x", attempt: attempt)
        check(form(post)["client_id"] == "c" && form(post)["client_secret"] == "s", "client_secret_post puts the secret in the form")
        let basic = MCPOAuth.exchangeRequest(server, client: MCPOAuthRegistration(id: "client+1", secret: "s:e/c", auth: "client_secret_basic"),
                                             code: "x", attempt: attempt)
        check(basic.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("client%2B1:s%3Ae%2Fc".utf8).base64EncodedString()
                && form(basic)["client_id"] == nil && form(basic)["client_secret"] == nil,
              "client_secret_basic: the form-encoded id and secret in Basic, nothing in the form")
        check(MCPOAuth.clientAuth(secret: "", registered: "client_secret_post", supported: nil) == "none"
                && MCPOAuth.clientAuth(secret: "s", registered: "client_secret_post", supported: nil) == "client_secret_post"
                && MCPOAuth.clientAuth(secret: "s", registered: nil, supported: ["client_secret_post"]) == "client_secret_post"
                && MCPOAuth.clientAuth(secret: "s", registered: nil, supported: nil) == "client_secret_basic",
              "a client without a secret is public; one with a secret uses what it was told, else basic")
        let session = MCPOAuthSession(clientId: "c", tokenEndpoint: "https://auth.example.com/token", resource: server.resource,
                                      accessToken: "at", refreshToken: "rt/1")
        let refresh = MCPOAuth.refreshRequest(session, endpoint: server.tokenEndpoint)
        check(form(refresh) == ["grant_type": "refresh_token", "refresh_token": "rt/1", "resource": server.resource, "client_id": "c"],
              "a refresh names the resource and no scope")
    }

    static func callbacks() {
        let attempt = ChatGPTSignInAttempt(state: "s1", nonce: "n", verifier: verifier, redirectURI: "r")
        func server(issuer: String? = "https://auth.example.com", iss: Bool = false) -> MCPOAuthServer {
            MCPOAuthServer(resource: "r", issuer: issuer, authorizationEndpoint: URL(string: "https://a.test/a")!,
                           tokenEndpoint: URL(string: "https://a.test/t")!, registrationEndpoint: nil, scope: nil, issParameter: iss,
                           tokenAuthMethods: nil)
        }
        func failure(_ params: [String: String], _ server: MCPOAuthServer = server()) -> MCPOAuthError? {
            do { _ = try MCPOAuth.readCallback(params, attempt: attempt, server: server); return nil }
            catch { return error as? MCPOAuthError }
        }
        check((try? MCPOAuth.readCallback(["state": "s1", "code": "c"], attempt: attempt, server: server())) == "c", "the code of this sign-in")
        check(failure(["state": "other", "code": "c"]) == MCPOAuthError(.mismatch, code: "state_mismatch")
                && failure(["state": "other", "error": "access_denied"]) == MCPOAuthError(.mismatch, code: "state_mismatch")
                && failure(["code": "c"]) == MCPOAuthError(.mismatch, code: "state_mismatch"),
              "another sign-in's state is refused before anything else")
        check(failure(["state": "s1", "code": "c", "iss": "https://evil.example"]) == MCPOAuthError(.mismatch, code: "iss_mismatch")
                && failure(["state": "s1", "code": "c"], server(iss: true)) == MCPOAuthError(.mismatch, code: "iss_missing")
                && failure(["state": "s1", "code": "c", "iss": "x"], server(issuer: nil)) == MCPOAuthError(.mismatch, code: "iss_mismatch"),
              "RFC 9207: another issuer, or none from a server that promised one")
        check((try? MCPOAuth.readCallback(["state": "s1", "code": "c", "iss": "https://auth.example.com"], attempt: attempt,
                                          server: server(iss: true))) == "c", "the server's own issuer")
        check(failure(["state": "s1", "error": "access_denied"]) == MCPOAuthError(.denied, code: "access_denied")
                && failure(["state": "s1"]) == MCPOAuthError(.exchange, code: "no_code"), "a refusal, and a callback without a code")
    }

    static func tokenAnswers() {
        func result(_ status: Int, _ body: String) -> MCPOAuth.TokenResult { MCPOAuth.tokenResult(status: status, body: Data(body.utf8)) }
        check(result(200, #"{"access_token":"at","token_type":"bearer","refresh_token":"rt","expires_in":"600"}"#)
                == .ok(MCPOAuth.Tokens(accessToken: "at", refreshToken: "rt", expiresIn: 600)), "a full answer, any case of Bearer")
        check(result(200, #"{"access_token":"at"}"#) == .ok(MCPOAuth.Tokens(accessToken: "at", refreshToken: nil, expiresIn: nil)),
              "no lifetime or refresh token")
        check(result(200, #"{"access_token":"a t"}"#) == .failed("no usable access_token") && result(200, "nope") == .failed("no usable access_token"),
              "a token that can't go into a header, or no JSON")
        check(result(200, #"{"access_token":"at","token_type":"DPoP"}"#) == .rejected("unsupported_token_type"), "only Bearer tokens")
        check(result(400, #"{"error":"invalid_grant"}"#) == .rejected("invalid_grant") && result(401, "<html>") == .rejected("http_401"),
              "refusals keep the server's code")
        check(result(503, "") == .failed("server 503"), "a 5xx is no answer, not a refusal")
        check(MCPOAuth.expiry(3600, nowMs: clock) == clock + 3_600_000 && MCPOAuth.expiry(nil, nowMs: clock) == MCPOAuth.noExpiry
                && MCPOAuth.expiry(Int64.max / 10, nowMs: clock) == MCPOAuth.noExpiry, "the expiry, and none without a lifetime")
    }

    static func sessions() throws {
        let session = MCPOAuthSession(clientId: "c", clientSecret: "s", clientAuth: "client_secret_post", userClient: true,
                                      tokenEndpoint: "https://a.test/t", resource: "https://m.test/mcp", accessToken: "at",
                                      refreshToken: "rt", expiresAtMs: clock)
        check(try JSONDecoder().decode(MCPOAuthSession.self, from: JSONEncoder().encode(session)) == session && session.status == .signedIn,
              "a sign-in round-trips through JSON")
        let empty = try JSONDecoder().decode(MCPOAuthSession.self, from: Data("{}".utf8))
        check(empty == MCPOAuthSession() && empty.status == .signedOut && empty.clientAuth == "none", "an empty item is OAuth, not signed in")
        let ran = session.signedOut()
        check(ran.status == .expired && ran.clientId == "c" && ran.tokenEndpoint == session.tokenEndpoint && ran.accessToken.isEmpty
                && ran.refreshToken.isEmpty && ran.expiresAtMs == 0, "a sign-in that ran out keeps its client: sign in again")
        check(session.signedOutByUser() == .withUserClient(id: "c", secret: "s")
                && MCPOAuthSession(clientId: "registered", tokenEndpoint: "t", accessToken: "a").signedOutByUser() == MCPOAuthSession(),
              "signing out keeps only a client the user entered")
    }

    /// The server's item in MCPSettings: its own account in the one MCP service, gone with the server.
    static func storage() throws {
        let items = MCPMemoryItems()
        let directory = MCPServerDirectory(items: items)
        let oauth = try JSONEncoder().encode(MCPOAuthSession())
        let record = try directory.add(name: "OAuth", endpoint: "https://mcp.example.com/mcp", token: nil, oauth: oauth, to: [])
        let other = try directory.add(name: "Token", endpoint: "https://other.example.com/mcp", token: "fixed-token-123", to: [record])
        let prefix = "server." + record.id.uuidString + "."
        check(Set(items.values.keys).isSuperset(of: [prefix + "endpoint", prefix + "oauth"]) && items.values[prefix + "token"] == nil,
              "an OAuth server keeps its sign-in in its own account and no token")
        check(try directory.store(for: record).loadOAuth() == oauth && directory.store(for: other).loadOAuth() == nil,
              "the other server has no sign-in")
        let remaining = try directory.remove(record, from: [record, other])
        check(!items.values.keys.contains { $0.hasPrefix(prefix) } && remaining.map(\.id) == [other.id]
                && (try? directory.store(for: other).loadToken()) == "fixed-token-123", "deleting the server deletes its sign-in only")
        let legacy = MCPSettingsStore(items: items)
        try legacy.save(endpoint: "https://legacy.example.com/mcp")
        try legacy.save(oauth: oauth)
        try legacy.remove()
        check(items.values["oauth"] == nil && items.values["endpoint"] == nil, "the first server's sign-in goes with it")
        _ = try directory.add(name: "Again", endpoint: "https://mcp.example.com/mcp", token: nil, oauth: oauth, to: remaining)
        try directory.removeAll()
        check(items.values.isEmpty, "a reset of the service (fresh install, UI tests) removes every sign-in")
        let failing = MCPMemoryItems()
        failing.failWrites = true
        check((try? MCPServerDirectory(items: failing).add(name: "A", endpoint: "https://a.example.com/mcp", token: nil, oauth: oauth, to: [])) == nil
                && failing.values.isEmpty, "a failed write leaves no sign-in behind")
        check(MCPSettingsStore.accounts.contains("oauth"), "the sign-in is one of a server's accounts")
        check((try? MCPSettingsStore.validateClient(" client-1 ")) == "client-1" && (try? MCPSettingsStore.validateClient("", optional: true)) == ""
                && (try? MCPSettingsStore.validateClient("")) == nil && (try? MCPSettingsStore.validateClient("a\nb")) == nil
                && (try? MCPSettingsStore.validateClient("權杖")) == nil, "a client the user enters is one line of printable ASCII")
    }

    // MARK: - Discovery against fake servers

    static func discovery() async throws {
        let http = MCPOAuthHTTP.shared
        func discover(_ configure: (inout FakeAuthorization.Options) -> Void) async throws -> (FakeAuthorization, Result<MCPOAuthServer, Error>) {
            let (fake, server) = try await FakeAuthorization.loopback(configure)
            defer { server.stop() }
            do { return (fake, .success(try await MCPOAuth.discover(endpoint: URL(string: fake.endpoint)!, http: http))) }
            catch { return (fake, .failure(error)) }
        }
        let wellKnownPath = "/.well-known/oauth-protected-resource/mcp", wellKnownRoot = "/.well-known/oauth-protected-resource"
        let insertion = "/.well-known/oauth-authorization-server/_clerk", openIDInsertion = "/.well-known/openid-configuration/_clerk"
        let openIDAfter = "/_clerk/.well-known/openid-configuration"

        // (a) The 401 names the resource metadata; nothing else is asked.
        let (fromChallenge, found) = try await discover { $0.protectedPaths = ["/meta/protected", wellKnownPath, wellKnownRoot] }
        let server = try found.get()
        check(fromChallenge.paths == ["/mcp", "/meta/protected", insertion], "the challenge's resource metadata first, then RFC 8414 path insertion")
        check(fromChallenge.requests("/mcp").first?.method == "POST" && fromChallenge.requests("/mcp").first?.bearer == nil,
              "the probe is an MCP request without a token")
        check(server.resource == fromChallenge.endpoint && server.scope == "openid email offline_access"
                && server.registrationEndpoint?.absoluteString == fromChallenge.base.value + "/register"
                && server.authorizationEndpoint.absoluteString == fromChallenge.issuer + "/authorize"
                && server.tokenEndpoint.absoluteString == fromChallenge.issuer + "/token" && server.issuer == fromChallenge.issuer,
              "the endpoints, the registration endpoint, the resource and the challenge's scope")

        // (b) No resource_metadata: the well-known address with the endpoint's path.
        let (fromPath, _) = try await discover { $0.challengePath = nil; $0.protectedPaths = [wellKnownPath, wellKnownRoot] }
        check(fromPath.paths == ["/mcp", wellKnownPath, insertion], "without resource_metadata: the path's well-known, not the root's")
        // (c) Only at the root.
        let (fromRoot, rooted) = try await discover { $0.challengePath = nil; $0.protectedPaths = [wellKnownRoot] }
        check(fromRoot.paths == ["/mcp", wellKnownPath, wellKnownRoot, insertion] && (try? rooted.get()) != nil, "then the root")
        // A challenge naming a missing document, and a well-known address that redirects: on to the next.
        let (missing, _) = try await discover { $0.challengePath = "/meta/gone"; $0.protectedPaths = [wellKnownRoot] }
        check(missing.paths == ["/mcp", "/meta/gone", wellKnownPath, wellKnownRoot, insertion], "a missing document goes on to the path and the root")
        let (redirected, _) = try await discover {
            $0.challengePath = nil; $0.protectedPaths = ["/meta/protected", wellKnownRoot]; $0.redirectPaths = [wellKnownPath: "/meta/protected"]
        }
        check(redirected.paths == ["/mcp", wellKnownPath, wellKnownRoot, insertion], "metadata is only a 200 answer: a redirect is not followed")

        // Authorization server metadata, in the spec's order for an issuer with a path.
        let (trap, trapped) = try await discover { $0.metadataPaths = [openIDAfter: false] }
        check(trap.paths == ["/mcp", "/meta/protected", insertion, openIDInsertion, openIDAfter]
                && (try? trapped.get())?.registrationEndpoint == nil,
              "Higgsfield's trap: only OpenID after the path, which names no registration endpoint")
        let (both, bothFound) = try await discover { $0.metadataPaths = [insertion: true, openIDAfter: false] }
        check(both.paths.last == insertion && (try? bothFound.get())?.registrationEndpoint != nil,
              "RFC 8414 path insertion comes first, so the copy that names the registration endpoint wins")
        let (openID, _) = try await discover { $0.metadataPaths = [openIDInsertion: true, openIDAfter: false] }
        check(openID.paths == ["/mcp", "/meta/protected", insertion, openIDInsertion], "OpenID with path insertion second")
        let (plain, plainFound) = try await discover {
            $0.issuerPath = ""; $0.metadataPaths = ["/.well-known/openid-configuration": true]
        }
        check(plain.paths == ["/mcp", "/meta/protected", "/.well-known/oauth-authorization-server", "/.well-known/openid-configuration"]
                && (try? plainFound.get()) != nil, "an issuer without a path: both at the root, in order")
        let (legacy, legacyFound) = try await discover {
            $0.challengePath = nil; $0.protectedPaths = []; $0.issuerPath = ""; $0.metadataPaths = ["/.well-known/oauth-authorization-server": true]
        }
        check(legacy.paths == ["/mcp", wellKnownPath, wellKnownRoot, "/.well-known/oauth-authorization-server"]
                && (try? legacyFound.get())?.resource == legacy.endpoint,
              "no resource metadata at all: the server's own origin is the authorization server (2025-03-26)")

        // Scope: the challenge's, else scopes_supported, else none.
        let (_, scoped) = try await discover { $0.challengeScope = nil; $0.scopesSupported = ["mcp:read", "mcp:write"] }
        check((try? scoped.get())?.scope == "mcp:read mcp:write", "without the challenge's scope, scopes_supported")
        let (_, unscoped) = try await discover { $0.challengeScope = nil }
        check((try? unscoped.get()) != nil && (try? unscoped.get())?.scope == nil, "no scope at all asks for none")
        let (unnamed, named) = try await discover { $0.resource = "" }
        check((try? named.get())?.resource == unnamed.endpoint, "metadata without a resource uses the endpoint's canonical address")

        // What can't be used.
        let (_, elsewhere) = try await discover { $0.resource = "https://other.example.com/mcp" }
        check((try? elsewhere.get()) == nil && (elsewhere.failureReason == .insecure), "metadata about another server is not used")
        let (_, insecure) = try await discover { $0.authorizationServer = "http://auth.example.com/as" }
        check(insecure.failureReason == .insecure, "an authorization server that isn't HTTPS is refused")
        let (_, noPKCE) = try await discover { $0.challengeMethods = ["plain"] }
        check(noPKCE.failureReason == .setup, "an authorization server without S256 is refused")
        let (_, nothing) = try await discover { $0.metadataPaths = [:] }
        check(nothing.failureReason == .setup, "no authorization server metadata")
    }

    // MARK: - Whole sign-ins against fake servers

    /// One sign-in through `MCPOAuth.signIn`, the browser following the page; `state` replaces the callback's.
    static func signIn(_ fake: FakeAuthorization, userClient: MCPOAuthRegistration? = nil, state: String? = nil,
                       timeout: TimeInterval = 10) async -> (Result<MCPOAuthSession, Error>, page: String?, opened: Bool) {
        guard let listener = try? await LoopbackCallbackServer.open() else { return (.failure(Failure(message: "listener")), nil, false) }
        defer { listener.close() }
        let browsing = Box<Task<String?, Never>?>(nil)
        do {
            let session = try await MCPOAuth.signIn(
                endpoint: URL(string: fake.endpoint)!, userClient: userClient, listener: listener, http: .shared,
                openBrowser: { url in browsing.value = Task { await Browser.follow(url, state: state) } },
                page: { failure in failure.map { "failed: \($0.reason.rawValue)" } ?? "signed in" },
                timeout: timeout, finishTimeout: 5, nowMs: { clock })
            return (.success(session), await browsing.value?.value, browsing.value != nil)
        } catch {
            return (.failure(error), await browsing.value?.value, browsing.value != nil)
        }
    }

    static func signIns() async throws {
        let (fake, server) = try await FakeAuthorization.loopback()
        defer { server.stop() }
        let (result, page, _) = await signIn(fake)
        let session = try result.get()
        guard let authorize = fake.requests(fake.options.value.issuerPath + "/authorize").first?.query,
              let exchange = fake.requests(fake.options.value.issuerPath + "/token").first?.form,
              let registration = fake.requests("/register").first?.json else { throw Failure(message: "the sign-in's requests") }
        let redirect = (registration["redirect_uris"] as? [String])?.first
        check(authorize["response_type"] == "code" && authorize["code_challenge_method"] == "S256" && authorize["client_id"] == session.clientId
                && authorize["redirect_uri"] == redirect && authorize["resource"] == fake.endpoint
                && authorize["scope"] == "openid email offline_access" && authorize["state"]?.count == 43,
              "the authorize page: the registered client, PKCE S256, state, the resource and the scope")
        check(exchange["grant_type"] == "authorization_code" && exchange["client_id"] == session.clientId && exchange["redirect_uri"] == redirect
                && exchange["resource"] == fake.endpoint && exchange["client_secret"] == nil,
              "the exchange: the same client, redirect and resource")
        check(PKCE.challenge(exchange["code_verifier"] ?? "") == authorize["code_challenge"], "the exchange proves the authorize page's challenge")
        check(session.clientId.hasPrefix("client-") && session.clientSecret.isEmpty && session.clientAuth == "none" && !session.userClient
                && session.tokenEndpoint == fake.issuer + "/token" && session.resource == fake.endpoint
                && session.accessToken == fake.current.value && fake.refreshTokens.value.contains(session.refreshToken)
                && session.expiresAtMs == clock + 3_600_000 && session.status == .signedIn,
              "the sign-in: the registered client, the token endpoint, the resource and the tokens")
        check(page == "200 signed in", "the browser's page comes after the exchange")

        // A client the user registered, for a server that registers no apps (Higgsfield's trap).
        let (entered, enteredServer) = try await FakeAuthorization.loopback { $0.metadataPaths = ["/_clerk/.well-known/openid-configuration": false] }
        defer { enteredServer.stop() }
        let refused = await signIn(entered)
        check(refused.0.failureReason == .noRegistration && !refused.opened && entered.requests("/register").isEmpty,
              "no registration endpoint and no client: the page asks for one, nothing opens")
        let withClient = try await signIn(entered, userClient: MCPOAuthRegistration(id: "user-client")).0.get()
        check(withClient.clientId == "user-client" && withClient.userClient && withClient.clientAuth == "none"
                && entered.requests("/register").isEmpty && entered.requests("/_clerk/token").first?.form["client_id"] == "user-client",
              "the user's client is used as it is, without registering")
        let (confidential, confidentialServer) = try await FakeAuthorization.loopback {
            $0.metadataPaths = ["/.well-known/oauth-authorization-server/_clerk": false]; $0.authMethods = ["client_secret_basic", "client_secret_post"]
        }
        defer { confidentialServer.stop() }
        let secret = try await signIn(confidential, userClient: MCPOAuthRegistration(id: "secret-client", secret: "s:e/c")).0.get()
        let basic = confidential.requests("/_clerk/token").first
        check(secret.clientAuth == "client_secret_basic" && basic?.headers["authorization"]?.hasPrefix("Basic ") == true
                && basic?.form["client_secret"] == nil, "a client with a secret authenticates with HTTP Basic")

        // The callback of another sign-in is answered 400 and exchanges nothing.
        let (mismatch, mismatchServer) = try await FakeAuthorization.loopback()
        defer { mismatchServer.stop() }
        let started = Date()
        let other = await signIn(mismatch, state: "another-sign-in", timeout: 1)
        check(other.page?.hasPrefix("400") == true && mismatch.requests("/_clerk/token").isEmpty, "another state gets 400 and no exchange")
        check(other.0.failureReason == .timedOut && Date().timeIntervalSince(started) < 5, "the wait goes on until the timeout")

        // RFC 9207, a refusal, and an exchange the server refuses.
        let (iss, issServer) = try await FakeAuthorization.loopback { $0.issParameter = true }
        defer { issServer.stop() }
        let issuer = iss.issuer
        iss.options.update { $0.iss = issuer }
        check((try? await signIn(iss).0.get()) != nil, "the authorization server's own iss")
        iss.options.update { $0.iss = "https://evil.example" }
        let wrongIss = await signIn(iss)
        check(wrongIss.0.oauthError == MCPOAuthError(.mismatch, code: "iss_mismatch") && wrongIss.page == "200 failed: mismatch",
              "another iss is refused, and the browser says so")
        iss.options.update { $0.iss = nil }
        check(await signIn(iss).0.oauthError == MCPOAuthError(.mismatch, code: "iss_missing"), "a promised iss that is missing")
        let tokensBefore = iss.requests("/_clerk/token").count
        iss.options.update { $0.issParameter = false; $0.denied = "access_denied" }
        let denied = await signIn(iss)
        check(denied.0.oauthError == MCPOAuthError(.denied, code: "access_denied") && iss.requests("/_clerk/token").count == tokensBefore,
              "a refusal on the authorize page exchanges nothing")
        let (bad, badServer) = try await FakeAuthorization.loopback()
        defer { badServer.stop() }
        bad.options.update { $0.metadataPaths = ["/.well-known/oauth-authorization-server/_clerk": false] }
        let unknown = await signIn(bad, userClient: MCPOAuthRegistration(id: "not-registered"))
        check(unknown.0.failureReason == .denied, "an authorize page that refuses the client")

        // Cancelling waits for nothing.
        let (waiting, waitingServer) = try await FakeAuthorization.loopback()
        defer { waitingServer.stop() }
        let task = Task { await signIn(waiting, state: "never", timeout: 30) }
        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        let cancelled = await task.value
        if case .failure(let error) = cancelled.0 { check(error is CancellationError, "cancelling a sign-in throws CancellationError") }
        else { check(false, "cancelling a sign-in does not sign in") }
    }

    // MARK: - Refreshes

    static func refreshes() async throws {
        let (fake, server) = try await FakeAuthorization.loopback()
        defer { server.stop() }
        fake.clients.update { $0["client-1"] = "" }
        fake.refreshTokens.value = ["rt-seed"]
        let seed = MCPOAuthSession(clientId: "client-1", tokenEndpoint: fake.issuer + "/token", resource: fake.endpoint,
                                   accessToken: "at-old", refreshToken: "rt-seed", expiresAtMs: clock + 3_600_000)
        guard case .refreshed(let next) = try await MCPOAuth.refresh(seed, http: .shared, nowMs: { clock }) else {
            throw Failure(message: "a refresh works")
        }
        let form = fake.requests("/_clerk/token").last?.form ?? [:]
        check(form == ["grant_type": "refresh_token", "refresh_token": "rt-seed", "resource": fake.endpoint, "client_id": "client-1"],
              "a refresh sends the refresh token, the resource and the client")
        check(next.accessToken == fake.current.value && next.refreshToken != "rt-seed" && fake.refreshTokens.value == [next.refreshToken]
                && next.expiresAtMs == clock + 3_600_000 && next.clientId == "client-1",
              "the rotated refresh token replaces the old one")
        if case .rejected(let terminal) = try await MCPOAuth.refresh(seed, http: .shared, nowMs: { clock }) {
            check(terminal, "the old refresh token is dead: invalid_grant is terminal")
        } else { check(false, "a used refresh token is refused") }
        fake.options.update { $0.rotates = false; $0.expiresIn = nil }
        if case .refreshed(let kept) = try await MCPOAuth.refresh(next, http: .shared, nowMs: { clock }) {
            check(kept.refreshToken == next.refreshToken && kept.expiresAtMs == MCPOAuth.noExpiry,
                  "an answer without a refresh token keeps the old one; without a lifetime the token has none")
        } else { check(false, "a refresh without rotation works") }
        fake.options.update { $0.refreshRefused = .json(400, #"{"error":"invalid_client"}"#) }
        if case .rejected(let terminal) = try await MCPOAuth.refresh(next, http: .shared, nowMs: { clock }) {
            check(!terminal, "invalid_client keeps the tokens")
        } else { check(false, "a refused client is a refusal") }
        fake.options.update { $0.refreshRefused = .json(503, "") }
        if case .failed = try await MCPOAuth.refresh(next, http: .shared, nowMs: { clock }) {} else { check(false, "a 5xx is no answer") }
        var elsewhere = next
        elsewhere.tokenEndpoint = "http://auth.example.com/token"
        if case .rejected(let terminal) = try await MCPOAuth.refresh(elsewhere, http: .shared, nowMs: { clock }) {
            check(terminal, "a token endpoint that isn't HTTPS gets nothing")
        } else { check(false, "an insecure token endpoint is refused") }

        // The gate: early, after a 401, one at a time; a dead sign-in signs out and keeps the client.
        fake.options.value = FakeAuthorization.Options()
        fake.refreshTokens.value = ["rt-gate"]
        let stored = Box<MCPOAuthSession?>(MCPOAuthSession(clientId: "client-1", tokenEndpoint: fake.issuer + "/token",
                                                           resource: fake.endpoint, accessToken: "at-gate", refreshToken: "rt-gate",
                                                           expiresAtMs: clock + 3_600_000))
        let gate = MCPOAuth.tokenGate(http: .shared, load: { stored.value }, save: { _, after in stored.value = after }, nowMs: { clock })
        let before = fake.requests("/_clerk/token").count
        check(try await gate.accessToken(rejected: nil) == "at-gate" && fake.requests("/_clerk/token").count == before,
              "a token far from expiry is used as it is")
        stored.value?.expiresAtMs = clock + 30_000
        let early = try await gate.accessToken(rejected: nil)
        check(early == fake.current.value && early != "at-gate" && stored.value?.accessToken == early, "a token a minute from expiry is refreshed first")
        let rejected = try await gate.accessToken(rejected: early)
        check(rejected != early && stored.value?.accessToken == rejected, "a token the server refused is refreshed")
        let count = fake.requests("/_clerk/token").count
        check(try await gate.accessToken(rejected: early) == rejected && fake.requests("/_clerk/token").count == count,
              "a token another call already replaced is not refreshed again")
        stored.value?.expiresAtMs = 0
        async let one = gate.accessToken(rejected: nil)
        async let two = gate.accessToken(rejected: nil)
        let both = try await [one, two]
        check(both[0] == both[1] && fake.requests("/_clerk/token").count == count + 1, "two calls at once share one refresh")
        stored.value?.expiresAtMs = 0
        fake.options.update { $0.refreshRefused = .json(400, #"{"error":"invalid_grant"}"#) }
        check(await error { _ = try await gate.accessToken(rejected: nil) } as? MCPError == .signInRequired
                && stored.value?.status == .expired && stored.value?.clientId == "client-1",
              "a dead refresh token: sign in again; the client stays")
        let asked = fake.requests("/_clerk/token").count
        check(await error { _ = try await gate.accessToken(rejected: nil) } as? MCPError == .signInRequired
                && fake.requests("/_clerk/token").count == asked, "signed out asks nothing")
    }

    // MARK: - A client that refreshes once after a 401

    static func retries() async throws {
        let (fake, server) = try await FakeAuthorization.loopback()
        defer { server.stop() }
        let host = "mcp-retry.fixture.invalid"
        let mcp = Box<[FakeRequest]>([])
        FakeHTTPS.register(host) { request in
            mcp.update { $0.append(request) }
            return fake.handle(FakeRequest(method: request.method, path: "/mcp", query: request.query, headers: request.headers, body: request.body))
        }
        defer { FakeHTTPS.remove(host) }
        let endpoint = URL(string: "https://\(host)/mcp")!
        fake.clients.update { $0["client-1"] = "" }
        fake.refreshTokens.value = ["rt-1"]
        fake.current.value = "at-current"
        let stored = Box<MCPOAuthSession?>(MCPOAuthSession(clientId: "client-1", tokenEndpoint: fake.issuer + "/token",
                                                           resource: fake.endpoint, accessToken: "at-stale", refreshToken: "rt-1",
                                                           expiresAtMs: clock + 3_600_000))
        let gate = MCPOAuth.tokenGate(http: .shared, load: { stored.value }, save: { _, after in stored.value = after }, nowMs: { clock })
        func client() -> MCPClient { MCPClient(endpoint: endpoint, configuration: FakeHTTPS.configuration(), credential: .oauth(gate)) }
        let refreshes = { fake.requests("/_clerk/token").count }

        let first = client()
        let info = try await first.initialize()
        let calls = mcp.value
        check(info.protocolVersion == "2025-03-26" && calls.count == 3, "a refused initialize, the same once more, and the notification")
        check(calls[0].bearer == "at-stale" && calls[1].bearer == stored.value?.accessToken && calls[2].bearer == stored.value?.accessToken
                && calls[1].bearer != "at-stale", "the request after the 401 carries the refreshed token")
        check(calls[0].json["id"] as? String == calls[1].json["id"] as? String && calls[1].json["method"] as? String == "initialize",
              "the refused request is sent once more as it was")
        check(refreshes() == 1 && fake.requests("/_clerk/token").first?.form["refresh_token"] == "rt-1"
                && stored.value?.refreshToken != "rt-1" && fake.refreshTokens.value == [stored.value?.refreshToken ?? ""],
              "one refresh, its rotated refresh token saved")
        let tools = try await first.listTools()
        check(tools.map(\.name) == ["echo"] && refreshes() == 1, "later requests use the refreshed token")

        // The server still refuses the refreshed token: one refresh, then sign in again.
        fake.options.update { $0.refusesAll = true }
        let sent = mcp.value.count
        check(await error { try await first.ping() } as? MCPError == .signInRequired && refreshes() == 2 && mcp.value.count == sent + 2,
              "a second 401 after one refresh needs a new sign-in, and nothing more is sent")
        fake.options.update { $0.refusesAll = false }

        // A token about to expire is refreshed before anything is sent.
        stored.value?.expiresAtMs = clock + 30_000
        let early = mcp.value.count
        _ = try await client().initialize()
        check(mcp.value[early...].allSatisfy { $0.bearer == fake.current.value } && refreshes() == 3, "refreshed before connecting: no 401")

        // A refused refresh is a sign-in to do again, before any request.
        stored.value?.expiresAtMs = 0
        fake.options.update { $0.refreshRefused = .json(400, #"{"error":"invalid_grant"}"#) }
        let none = mcp.value.count
        check(await error { _ = try await client().initialize() } as? MCPError == .signInRequired && mcp.value.count == none
                && stored.value?.status == .expired, "a refused refresh: sign in again, and the server gets nothing")
        // No answer from the authorization server is a connection failure, not a sign-in to redo.
        stored.value = MCPOAuthSession(clientId: "client-1", tokenEndpoint: fake.issuer + "/token", resource: fake.endpoint,
                                       accessToken: "at-x", refreshToken: "rt-x", expiresAtMs: 0)
        fake.options.update { $0.refreshRefused = .json(503, "") }
        check(await error { _ = try await client().initialize() } as? MCPError == .transportFailure && stored.value?.refreshToken == "rt-x",
              "an authorization server that does not answer keeps the sign-in")
        fake.options.update { $0.refreshRefused = nil }

        // A fixed token is never refreshed. A server that names its OAuth sign-in asks for one instead;
        // any other 401 stays an HTTP 401. A 403 for a missing scope is not a sign-in yet (step-up is a TODO).
        let fixed = MCPClient(endpoint: endpoint, configuration: FakeHTTPS.configuration(), token: "fixed-token")
        let anonymous = MCPClient(endpoint: endpoint, configuration: FakeHTTPS.configuration(), credential: nil)
        let before = refreshes()
        let refusedFixed = await error { _ = try await fixed.initialize() } as? MCPError
        let refusedNone = await error { _ = try await anonymous.initialize() } as? MCPError
        check(refusedFixed == .signInRequired && refusedNone == .signInRequired && refreshes() == before,
              "a server that names its OAuth sign-in refuses a fixed token or none: sign in with OAuth")
        fake.options.update { $0.challengePath = nil }
        check(await error { _ = try await fixed.initialize() } as? MCPError == .httpStatus(statusCode: 401) && refreshes() == before,
              "a fixed token's other 401 stays an HTTP 401")
        fake.options.update { $0.challengePath = "/meta/protected" }
        fake.options.update { $0.insufficientScope = true }
        stored.value = MCPOAuthSession(clientId: "client-1", tokenEndpoint: fake.issuer + "/token", resource: fake.endpoint,
                                       accessToken: fake.current.value, refreshToken: "rt-unused", expiresAtMs: clock + 3_600_000)
        check(await error { _ = try await client().initialize() } as? MCPError == .httpStatus(statusCode: 403) && refreshes() == before,
              "insufficient_scope is reported as a 403 without a refresh")
        let told = String(decoding: try JSONEncoder().encode(MCPConversationRunner.failureResult(MCPError.signInRequired)), as: UTF8.self)
        check(MCPExecutionDiagnostic.failed(MCPError.signInRequired).category == .other
                && told.contains("sign in to this server in the app's MCP server settings")
                && told.contains("not run"), "a tool call that needs a sign-in says so to the model")
    }

    // MARK: - The server page

    @MainActor static func wait(_ condition: () -> Bool, _ what: String) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(nanoseconds: 25_000_000) }
        guard condition() else { throw Failure(message: "timed out waiting: " + what) }
    }

    @MainActor static func serverPage() async throws {
        let host = "mcp-page.fixture.invalid"
        let fake = FakeAuthorization(base: "https://" + host)
        FakeHTTPS.register(host) { fake.handle($0) }
        defer { FakeHTTPS.remove(host) }
        let items = MCPMemoryItems()
        let directory = MCPServerDirectory(items: items)
        let record = try directory.add(name: "Higgs", endpoint: fake.endpoint, token: nil,
                                       oauth: try JSONEncoder().encode(MCPOAuthSession()), to: [])
        let store = directory.store(for: record)
        let item = MCPOAuthItem(repository: store)
        let session = MCPSession(repository: store, allowsNetwork: true,
                                 tokenClientFactory: { MCPClient(endpoint: $0, configuration: FakeHTTPS.configuration(), credential: $1) },
                                 oauthHTTP: MCPOAuthHTTP(configuration: FakeHTTPS.configuration()))
        let pages: @Sendable (AppText?) -> String = { $0 == nil ? "signed in" : "failed" }
        check(session.authMode == .oauth && session.authDraft == .oauth && session.signInStatus == .signedOut
                && session.statusMessage == .mcpNotSignedIn && !session.canConnect && session.canSignIn,
              "an OAuth server before signing in: 尚未登入, nothing to connect")

        let browser = PageBrowser()
        session.signIn(browser: browser, page: pages)
        check(session.isSigningIn && !session.canSave && !session.canSignIn, "one sign-in at a time; nothing else is saved meanwhile")
        try await wait({ !session.isSigningIn }, "the page's sign-in")
        let saved = try item.load()
        check(session.signInStatus == .signedIn && session.noticeText == .mcpSignedInNotice && session.errorText == nil
                && session.statusMessage == .mcpSavedStatus && session.canConnect, "signed in: 已登入, ready to connect")
        check(saved?.accessToken == fake.current.value && saved?.resource == fake.endpoint && items.values.keys.contains("server." + record.id.uuidString + ".oauth"),
              "the tokens are in the server's own Keychain item")
        check(browser.opened.count == 1 && browser.closes == 1, "the page opened once and was closed after the sign-in")
        try await wait({ browser.page != nil }, "the browser's page")
        check(browser.page == "200 signed in", "the browser was told")

        session.connect()
        try await wait({ !session.isBusy }, "connecting")
        check(session.phase == .connected && session.toolNames == ["echo"], "the signed-in server connects with its token")

        // The sign-in runs out: the server refuses the token and the refresh token is dead.
        fake.options.update { $0.refusesAll = true; $0.refreshRefused = .json(400, #"{"error":"invalid_grant"}"#) }
        session.disconnect()
        session.connect()
        try await wait({ !session.isBusy }, "connecting with a dead sign-in")
        check(session.phase == .signInRequired && session.statusMessage == .mcpSignInRequired
                && session.errorText == .mcpSignInRequiredError && session.signInStatus == .expired,
              "需要重新登入 in the status line, not a connection failure")
        check((try? item.load())?.accessToken == "" && (try? item.load())?.tokenEndpoint.isEmpty == false, "the dead tokens are gone")

        // Signing in again clears it.
        fake.options.update { $0.refusesAll = false; $0.refreshRefused = nil }
        session.signIn(browser: browser, page: pages)
        try await wait({ !session.isSigningIn }, "signing in again")
        check(session.phase == .saved && session.signInStatus == .signedIn && session.statusMessage == .mcpSavedStatus, "signed in again")

        // Signing out clears the tokens and the registration.
        session.signOut()
        check(try item.load() == MCPOAuthSession() && session.signInStatus == .signedOut && session.noticeText == .mcpSignedOutNotice
                && session.statusMessage == .mcpNotSignedIn && !session.canConnect, "登出 leaves no token on this device")

        // Closing the page before signing in cancels, and the listener closes.
        let holding = PageBrowser()
        holding.follows = false
        session.signIn(browser: holding, page: pages)
        try await wait({ !holding.opened.isEmpty }, "the page opening")
        let redirect = URLComponents(url: holding.opened[0], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "redirect_uri" }?.value
        holding.personCloses()
        check(!session.isSigningIn && session.noticeText == .accountFailDenied && session.signInStatus == .signedOut, "已取消登入, nothing saved")
        var closed = false
        for _ in 0..<20 where !closed {
            closed = (try? await URLSession(configuration: .ephemeral).data(from: URL(string: (redirect ?? "") + "?state=x")!)) == nil
            if !closed { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        check(closed, "the loopback listener is closed")

        // A server that registers no apps: the page asks for a client, and the client is kept on sign-out.
        fake.options.update { $0.metadataPaths = ["/_clerk/.well-known/openid-configuration": false] }
        session.signIn(browser: browser, page: pages)
        try await wait({ !session.isSigningIn }, "a sign-in without registration")
        check(session.errorText == .mcpSignInFailNoRegistration && session.needsUserClient, "no registration endpoint: enter a client")
        session.clientIDDraft = "user-client"
        session.signIn(browser: browser, page: pages)
        try await wait({ !session.isSigningIn }, "a sign-in with the user's client")
        check(session.signInStatus == .signedIn && session.hasUserClient && (try? item.load())?.clientId == "user-client"
                && session.clientIDDraft.isEmpty, "登入 saves the client first and signs in with it")
        session.signOut()
        check(try item.load() == .withUserClient(id: "user-client", secret: ""), "signing out keeps the user's client")

        // The way of signing in, chosen on the page.
        session.authDraft = .token
        check(!session.canSave, "a fixed token is chosen with the token")
        session.tokenDraft = "fixed-token-123"
        session.saveEndpoint()
        check(session.authMode == .token && (try? store.loadOAuth()) == nil && (try? store.loadToken()) == "fixed-token-123",
              "a fixed token replaces the sign-in")
        session.authDraft = .oauth
        session.saveEndpoint()
        check(session.authMode == .oauth && (try? store.loadToken()) == nil && (try? item.load()) == MCPOAuthSession(),
              "OAuth replaces the token")
        session.authDraft = .none
        session.saveEndpoint()
        check(session.authMode == .none && (try? store.loadToken()) == nil && (try? store.loadOAuth()) == nil, "nothing at all")
        session.connect()
        try await wait({ !session.isBusy }, "connecting an OAuth server without signing in")
        check(session.phase == .failed && session.errorText == .mcpOAuthRequired && session.statusMessage == .mcpFailedStatus,
              "a server that wants OAuth, reached without it: the page says to choose OAuth 登入")

        // Another endpoint is another server: its sign-in goes.
        fake.options.value = FakeAuthorization.Options()
        session.authDraft = .oauth
        session.saveEndpoint()
        session.signIn(browser: browser, page: pages)
        try await wait({ !session.isSigningIn }, "a sign-in before moving the endpoint")
        check(session.signInStatus == .signedIn, "signed in before moving the endpoint")
        session.endpointDraft = "https://other.fixture.invalid/mcp"
        session.saveEndpoint()
        check(try item.load() == MCPOAuthSession() && session.signInStatus == .signedOut && session.authMode == .oauth,
              "a different endpoint drops the old server's sign-in")
        _ = try directory.remove(record, from: [record])
        check(items.values.keys.allSatisfy { !$0.hasPrefix("server.") }, "deleting the server deletes its sign-in")
    }
}

extension Result where Failure == Error {
    var failureReason: MCPOAuthFailure? { oauthError?.reason }
    var oauthError: MCPOAuthError? {
        if case .failure(let error) = self { return error as? MCPOAuthError }
        return nil
    }
}
