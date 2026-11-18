import Foundation
@testable import AssistantModels

/// Every request is intercepted, including unknown hosts, so these tests cannot reach a network:
/// a host without a registered server fails at once. Each test registers its own `.invalid` host.
final class AccountProtocolFixture: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var mime: String = "application/json"
        var chunks: [Data]

        static func json(_ status: Int, _ body: String) -> Reply { Reply(status: status, chunks: [Data(body.utf8)]) }
        static func events(_ events: [String]) -> Reply {
            Reply(status: 200, mime: "text/event-stream", chunks: events.map { Data($0.utf8) })
        }
    }

    struct Seen: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data

        var form: [String: String] { LoopbackCallbackServer.parseQuery(String(decoding: body, as: UTF8.self)) ?? [:] }
        var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:] }
        func header(_ name: String) -> String? {
            headers.first { $0.key.lowercased() == name.lowercased() }?.value
        }
    }

    /// One fake host: answers in order from `replies`, or from `handler` when set.
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var queued: [Reply]
        private var log: [Seen] = []
        private let handler: (@Sendable (Seen) -> Reply)?
        let host: String

        init(host: String, replies: [Reply], handler: (@Sendable (Seen) -> Reply)?) {
            self.host = host; self.queued = replies; self.handler = handler
        }

        var base: URL { URL(string: "https://\(host)")! }
        var requests: [Seen] { lock.lock(); defer { lock.unlock() }; return log }

        func enqueue(_ replies: [Reply]) { lock.lock(); queued += replies; lock.unlock() }

        func answer(_ seen: Seen) -> Reply {
            lock.lock()
            log.append(seen)
            let next = queued.isEmpty ? nil : queued.removeFirst()
            lock.unlock()
            if let next { return next }
            return handler?(seen) ?? .json(599, "{}")
        }
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var servers: [String: Server] = [:]
    }
    private static let registry = Registry()

    static func register(_ replies: [Reply] = [], handler: (@Sendable (Seen) -> Reply)? = nil) -> Server {
        let server = Server(host: "account-\(UUID().uuidString.lowercased()).invalid", replies: replies, handler: handler)
        registry.lock.lock()
        registry.servers[server.host] = server
        registry.lock.unlock()
        return server
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountProtocolFixture.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    static func http() -> URLSessionAccountHTTP { URLSessionAccountHTTP(session: session()) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.registry.lock.lock()
        let server = Self.registry.servers[request.url?.host ?? ""]
        Self.registry.lock.unlock()
        guard let server, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let seen = Seen(method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:],
                        body: Self.body(of: request))
        let reply = server.answer(seen)
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": reply.mime]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A token provider standing in for the App's: hands out "token-1", then a new
/// one each time a caller says the last one was refused.
final class FakeAccountTokens: ModelAccountTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current = 1
    private var calls: [String?] = []
    let failure: Error?

    init(failure: Error? = nil) { self.failure = failure }

    /// The `rejected` argument of every call, in order.
    var rejections: [String?] { lock.lock(); defer { lock.unlock() }; return calls }

    func accessToken(for route: ModelAccountRoute, rejected: String?) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        calls.append(rejected)
        if let failure { throw failure }
        if rejected == "token-\(current)" { current += 1 }
        return "token-\(current)"
    }
}
