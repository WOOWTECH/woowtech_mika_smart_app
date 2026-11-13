import Foundation
import Network

/// The sign-in callback listener (Play core/oauth/LoopbackCallback.kt @964d7bec): bound to 127.0.0.1
/// only, so nothing else on the network can reach it, on a port the system picks. The browser comes
/// back to `http://127.0.0.1:<port>/auth/callback?…`; the waiter finishes the sign-in first and only
/// then answers with a page, while the browser keeps waiting on that connection. Other paths get 404,
/// callbacks the waiter does not accept (another attempt's state) get 400 and the wait goes on. It
/// takes one callback; close it when done or abandoned.
///
/// iOS may take a suspended App's listening socket away (TN2277), for example while the user fetched
/// a code from another App during sign-in. `reopen()` listens again on the same port, which the
/// authorize request already named. Validation prototype: no screen uses it yet.
public final class LoopbackCallbackServer: @unchecked Sendable {
    public static let host = "127.0.0.1"
    public static let path = "/auth/callback"
    static let maximumRequestBytes = 16 * 1024
    static let readTimeout: TimeInterval = 5
    static let startTimeout: TimeInterval = 5

    private let queue = DispatchQueue(label: "io.woowtech.assistant.loopback-callback")
    // Everything below is touched on `queue` only.
    private var listener: NWListener?
    private var listenerFailed = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Each connection's read deadline, until its request line and headers are in.
    private var deadlines: [ObjectIdentifier: DispatchWorkItem] = [:]
    /// Callbacks that arrived before anyone waited (the browser can be quicker than the waiter).
    private var parked: [(NWConnection, Data)] = []
    private var waiter: Waiter?
    private var accepted = false
    private var closed = false
    private var boundPort: UInt16 = 0

    /// The port this listener was given; it never changes, also across `reopen()`.
    public var port: UInt16 { queue.sync { boundPort } }
    public var redirectURI: String { "http://\(Self.host):\(port)\(Self.path)" }
    /// False once the system took the socket away; then `reopen()`.
    public var isListening: Bool { queue.sync { listener != nil && !listenerFailed && !closed } }

    private init() {}

    /// Starts listening on 127.0.0.1; `port` 0 lets the system pick a free one.
    public static func open(port: UInt16 = 0) async throws -> LoopbackCallbackServer {
        let server = LoopbackCallbackServer()
        try await server.listen(on: port)
        return server
    }

    /// Listens again on the same port after the system took the socket away. The old socket is
    /// released first; binding is tried a few times while the system lets go of the port.
    public func reopen() async throws {
        let port: UInt16 = await withCheckedContinuation { continuation in
            queue.async {
                let port = self.boundPort
                guard let old = self.listener else { return continuation.resume(returning: port) }
                self.listener = nil
                let released = StartState()
                @Sendable func resume() {
                    guard !released.started else { return }
                    released.started = true
                    continuation.resume(returning: port)
                }
                old.stateUpdateHandler = { state in
                    if case .cancelled = state { resume() }
                }
                old.cancel()
                self.queue.asyncAfter(deadline: .now() + 1) { resume() }
            }
        }
        var attempt = 0
        while true {
            do {
                return try await listen(on: port)
            } catch {
                attempt += 1
                guard attempt < 10, !(error is CancellationError) else { throw error }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// Stops listening and drops every connection; a pending wait ends with nil. Not on the listener's queue.
    public func close() {
        queue.sync {
            closed = true
            listener?.cancel()
            listener = nil
            for connection in connections.values { connection.cancel() }
            connections = [:]
            for deadline in deadlines.values { deadline.cancel() }
            deadlines = [:]
            for (connection, _) in parked { connection.cancel() }
            parked = []
            if let waiter { finish(waiter, with: nil) }
        }
    }

    /// Waits up to `timeout` for the callback; nil when it timed out, was cancelled or closed.
    /// `page` runs once, for the first accepted callback; what it returns is the browser's page.
    public func waitForCallback(timeout: TimeInterval,
                                accept: @escaping @Sendable ([String: String]) -> Bool = { _ in true },
                                page: @escaping @Sendable ([String: String]) async -> String) async -> [String: String]? {
        let waiter = Waiter(accept: accept, page: page)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
                queue.async { self.install(waiter, continuation, timeout: timeout) }
            }
        } onCancel: {
            queue.async { self.finish(waiter, with: nil) }
        }
    }

    // MARK: - Listening

    private func listen(on requested: UInt16) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(Self.host),
                                                     port: requested == 0 ? .any : NWEndpoint.Port(rawValue: requested)!)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters)
        let start = StartState()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            @Sendable func resume(_ error: Error?) {
                guard !start.started else { return }
                start.started = true
                if let error {
                    listener.cancel()
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self else { return resume(CancellationError()) }
                    if self.closed { return resume(CancellationError()) }
                    self.listener = listener
                    self.listenerFailed = false
                    self.boundPort = listener.port?.rawValue ?? requested
                    resume(nil)
                case .waiting(let error), .failed(let error):
                    if !start.started { return resume(error) }
                    if let self, self.listener === listener { self.listenerFailed = true }
                case .cancelled:
                    resume(CancellationError())
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.startTimeout) {
                resume(NWError.posix(.ETIMEDOUT))
            }
        }
    }

    /// Touched on `queue` only.
    private final class StartState: @unchecked Sendable { var started = false }

    private func accept(_ connection: NWConnection) {
        guard !closed else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[id] = nil
                self?.deadlines.removeValue(forKey: id)?.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
        let deadline = DispatchWorkItem { connection.cancel() }
        deadlines[id] = deadline
        queue.asyncAfter(deadline: .now() + Self.readTimeout, execute: deadline)
        receive(connection, Data())
    }

    /// Reads the request line and headers (the body, if any, is ignored).
    private func receive(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let id = ObjectIdentifier(connection)
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) ?? buffer.range(of: Data("\n\n".utf8)) {
                self.deadlines.removeValue(forKey: id)?.cancel()
                self.route(connection, head: buffer.subdata(in: buffer.startIndex..<end.lowerBound))
            } else if error != nil || buffer.count > Self.maximumRequestBytes {
                self.deadlines.removeValue(forKey: id)?.cancel()
                connection.cancel()
            } else if isComplete {
                self.deadlines.removeValue(forKey: id)?.cancel()
                if buffer.isEmpty { connection.cancel() } else { self.route(connection, head: buffer) }
            } else {
                self.receive(connection, buffer)
            }
        }
    }

    private func route(_ connection: NWConnection, head: Data) {
        let text = String(decoding: head, as: UTF8.self)
        let requestLine = text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let target = parts.count > 1 ? parts[1] : ""
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard parts.first == "GET", path == Self.path else {
            return respond(connection, 404, "Not Found", "text/plain", "Not Found")
        }
        // Only one callback is taken.
        if accepted { return respond(connection, 400, "Bad Request", "text/plain", "Bad Request") }
        guard let waiter else {
            parked.append((connection, head))
            return
        }
        let query = target.firstIndex(of: "?").map { String(target[target.index(after: $0)...]) } ?? ""
        // A malformed escape (a lone %) means it isn't this sign-in's callback either.
        guard let params = Self.parseQuery(query), waiter.accept(params) else {
            return respond(connection, 400, "Bad Request", "text/plain", "Bad Request")
        }
        accepted = true
        waiter.pageTask = Task {
            let html = await waiter.page(params)
            self.queue.async {
                guard !waiter.done else { return connection.cancel() }
                // The wait ends once the page is out, so closing the listener next can't cut it off.
                self.respond(connection, 200, "OK", "text/html; charset=utf-8", html) { self.finish(waiter, with: params) }
            }
        }
    }

    /// `sent` runs on the queue once the answer is handed over (or failed), before the connection closes.
    private func respond(_ connection: NWConnection, _ status: Int, _ reason: String, _ type: String, _ body: String,
                         sent: (@Sendable () -> Void)? = nil) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, isComplete: true, completion: .contentProcessed { _ in
            sent?()
            connection.cancel()
        })
    }

    // MARK: - The one waiter

    private final class Waiter: @unchecked Sendable {
        let accept: @Sendable ([String: String]) -> Bool
        let page: @Sendable ([String: String]) async -> String
        var continuation: CheckedContinuation<[String: String]?, Never>?
        var pageTask: Task<Void, Never>?
        var done = false

        init(accept: @escaping @Sendable ([String: String]) -> Bool, page: @escaping @Sendable ([String: String]) async -> String) {
            self.accept = accept; self.page = page
        }
    }

    private func install(_ waiter: Waiter, _ continuation: CheckedContinuation<[String: String]?, Never>, timeout: TimeInterval) {
        // Cancelled before it got here, closed, or another wait is running: nothing to wait for.
        guard !waiter.done, !closed, self.waiter == nil, !accepted else {
            waiter.done = true
            return continuation.resume(returning: nil)
        }
        waiter.continuation = continuation
        self.waiter = waiter
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            // Once a callback is accepted its page decides; the deadline is only for the browser.
            guard let self, !self.accepted else { return }
            self.finish(waiter, with: nil)
        }
        let early = parked
        parked = []
        for (connection, head) in early { route(connection, head: head) }
    }

    private func finish(_ waiter: Waiter, with result: [String: String]?) {
        guard !waiter.done else { return }
        waiter.done = true
        waiter.pageTask?.cancel()
        if self.waiter === waiter { self.waiter = nil }
        waiter.continuation?.resume(returning: result)
        waiter.continuation = nil
    }

    /// Play `parseQuery` (java.net.URLDecoder): `+` is a space; nil for a malformed escape.
    static func parseQuery(_ query: String) -> [String: String]? {
        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = decode(parts[0]), let value = decode(parts.count > 1 ? parts[1] : "") else { return nil }
            params[key] = value
        }
        return params
    }

    private static func decode(_ text: Substring) -> String? {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
