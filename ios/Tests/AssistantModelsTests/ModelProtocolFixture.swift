import Foundation

/// All requests are intercepted, including unknown hosts: this fixture cannot use the network.
final class ModelProtocolFixture: URLProtocol {
    final class Scenario: @unchecked Sendable {
        struct Reply {
            let status: Int; let mime: String; let chunks: [Data]; let holdAfterBody: Bool
            init(status: Int, mime: String, chunks: [Data], holdAfterBody: Bool = false) {
                self.status = status; self.mime = mime; self.chunks = chunks; self.holdAfterBody = holdAfterBody
            }
        }
        let status: Int
        let mime: String
        let chunks: [Data]
        let followUp: Reply?
        let holdBeforeHeaders: Bool
        let holdAfterBody: Bool
        let failure: URLError?
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        private var stops = 0
        private var delivered = false
        private var heldFinishes: [() -> Void] = []

        init(status: Int = 200, mime: String = "application/json", chunks: [Data] = [],
             holdBeforeHeaders: Bool = false, holdAfterBody: Bool = false, failure: URLError? = nil,
             followUp: Reply? = nil) {
            self.status = status
            self.mime = mime
            self.chunks = chunks
            self.followUp = followUp
            self.holdBeforeHeaders = holdBeforeHeaders
            self.holdAfterBody = holdAfterBody
            self.failure = failure
        }

        func record(_ request: URLRequest) -> Int {
            lock.lock(); defer { lock.unlock() }
            requests.append(request); return requests.count - 1
        }
        func stop() { lock.lock(); defer { lock.unlock() }; stops += 1 }
        /// A visible delivery flag means a held response can already be
        /// released. Publish the callback and flag under the same lock.
        func didDeliver(heldFinish: (() -> Void)? = nil) {
            lock.lock(); defer { lock.unlock() }
            if let heldFinish { heldFinishes.append(heldFinish) }
            delivered = true
        }
        func releaseHeldResponses() {
            lock.lock()
            let finishes = heldFinishes
            heldFinishes.removeAll()
            lock.unlock()
            finishes.forEach { $0() }
        }
        var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
        var lastRequest: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }
        var requestSnapshot: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
        var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }
        var bodyDelivered: Bool { lock.lock(); defer { lock.unlock() }; return delivered }
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var scenarios: [String: Scenario] = [:]
    }
    private static let registry = Registry()
    private var scenario: Scenario?

    static func register(_ scenario: Scenario) -> URL {
        let host = "fixture-\(UUID().uuidString.lowercased()).invalid"
        registry.lock.lock()
        registry.scenarios[host] = scenario
        registry.lock.unlock()
        return URL(string: "https://\(host)/v1")!
    }

    static func remove(_ url: URL) {
        registry.lock.lock()
        registry.scenarios.removeValue(forKey: url.host ?? "")
        registry.lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelProtocolFixture.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.registry.lock.lock()
        scenario = Self.registry.scenarios[request.url?.host ?? ""]
        Self.registry.lock.unlock()
        guard let scenario = scenario, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let index = scenario.record(request)
        if let failure = scenario.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        if scenario.holdBeforeHeaders { return }
        let reply = index > 0 ? scenario.followUp ?? .init(status: scenario.status, mime: scenario.mime, chunks: scenario.chunks)
                              : .init(status: scenario.status, mime: scenario.mime, chunks: scenario.chunks)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if index > 0 && scenario.followUp != nil ? reply.holdAfterBody : scenario.holdAfterBody {
            scenario.didDeliver(heldFinish: { [weak self] in
                guard let self else { return }
                self.client?.urlProtocolDidFinishLoading(self)
            })
        } else {
            scenario.didDeliver()
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { scenario?.stop() }
}
