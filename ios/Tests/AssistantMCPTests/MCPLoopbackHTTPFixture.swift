#if !MCP_SMOKE
import Foundation
import Network
@testable import AssistantMCP

/// Real TCP/HTTP, bound exclusively to IPv4 loopback. No URLProtocol interception,
/// TLS exceptions, credentials, external server, or production endpoint changes.
final class MCPLoopbackHTTPFixture: @unchecked Sendable {
    enum Reply: Sendable {
        case toolError, malformedIsError, oversizedResponse, largeToolError
        case http(Int), rpc(Int), holdBeforeHeaders, holdSSE, disconnect, ok
    }
    enum Failure: Error { case startup, malformedRequest, missingRequest }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "MCP.loopback.fixture")
    private let replies: [Reply]
    // Connections and the start continuation are confined to queue.
    private var connections: [NWConnection] = []
    private var starting: CheckedContinuation<URL, Error>?
    private let lock = NSLock()
    private var methods: [String] = []
    private var responseWrites = 0
    private var responseBytes = 0

    init(_ replies: [Reply]) throws {
        self.replies = replies
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    var receivedMethods: [String] {
        lock.lock(); defer { lock.unlock() }
        return methods
    }

    // Successful local send completions, not evidence of client consumption.
    var completedResponseWrites: (count: Int, byteCount: Int) {
        lock.lock(); defer { lock.unlock() }
        return (responseWrites, responseBytes)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.starting = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self, let pending = self.starting else { return }
                    switch state {
                    case .ready:
                        self.starting = nil
                        guard let port = self.listener.port,
                              let url = URL(string: "http://127.0.0.1:\(port.rawValue)/mcp") else {
                            pending.resume(throwing: Failure.startup); return
                        }
                        pending.resume(returning: url)
                    case .failed, .cancelled:
                        self.starting = nil
                        pending.resume(throwing: Failure.startup)
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.connections.append(connection)
                    connection.start(queue: self.queue)
                    self.read(connection, data: Data())
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, let pending = self.starting else { return }
                    self.starting = nil
                    self.listener.cancel()
                    pending.resume(throwing: Failure.startup)
                }
            }
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func hasReceived(_ count: Int, includingResponse: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return methods.count >= count && (!includingResponse || responseWrites >= count)
    }

    func waitForRequests(_ count: Int, includingResponse: Bool = false) async throws {
        for _ in 0..<500 {
            if hasReceived(count, includingResponse: includingResponse) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure.missingRequest
    }

    private func read(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, done, error in
            guard let self else { connection.cancel(); return }
            var bytes = data
            bytes.append(chunk ?? Data())
            guard bytes.count <= 65_536 else { connection.cancel(); return }
            if let split = bytes.range(of: Data("\r\n\r\n".utf8)),
               let headers = String(data: bytes[..<split.lowerBound], encoding: .utf8) {
                let length = headers.components(separatedBy: "\r\n").compactMap { line -> Int? in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                    return Int(parts[1].trimmingCharacters(in: .whitespaces))
                }.first
                guard let length, (1...32_768).contains(length) else { connection.cancel(); return }
                if bytes.count >= split.upperBound + length {
                    do {
                        let body = bytes.subdata(in: split.upperBound..<(split.upperBound + length))
                        let request = try JSONDecoder().decode(JSONValue.self, from: body)
                        guard let method = request["method"]?.stringValue,
                              ["tools/call", "resources/read", "ping"].contains(method) else {
                            throw Failure.malformedRequest
                        }
                        // Count only a completely received HTTP request, independently
                        // of the runner's .executing event or dispatch log.
                        self.lock.lock()
                        let index = self.methods.count
                        self.methods.append(method)
                        self.lock.unlock()
                        guard index < self.replies.count else { connection.cancel(); return }
                        try self.respond(self.replies[index], request: request, connection: connection)
                    } catch { connection.cancel() }
                    return
                }
            }
            guard error == nil, !done else { connection.cancel(); return }
            self.read(connection, data: bytes)
        }
    }

    private func respond(_ reply: Reply, request: JSONValue, connection: NWConnection) throws {
        var status = 200
        var envelope: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": request["id"] ?? .null]
        switch reply {
        case .holdBeforeHeaders: return
        case .oversizedResponse:
            let length = MCPHTTPTransport.maximumResponseBytes + 1
            // Supply one body byte so header-limit coverage does not depend on
            // bytes(for:) yielding before any body delivery. No oversized body
            // is allocated, and the connection stays open until cancellation.
            send(Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(length)\r\nConnection: close\r\n\r\n{".utf8),
                 on: connection, close: false)
            return
        case .holdSSE:
            send(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n: waiting\n\n".utf8),
                 on: connection, close: false)
            return
        case .disconnect:
            // Close after a partial body: the request was fully received, but
            // there is no complete JSON-RPC result or evidence of rollback.
            send(Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 4096\r\nConnection: close\r\n\r\n{".utf8),
                 on: connection)
            return
        case .http(let code): status = code
        case .rpc(let code):
            envelope["error"] = .object(["code": .number(Decimal(code)), "message": .string("PRIVATE_FIXTURE_BODY")])
        case .toolError, .malformedIsError, .largeToolError:
            let flag: JSONValue
            if case .malformedIsError = reply { flag = .string("false") } else { flag = .bool(true) }
            let text: String
            if case .largeToolError = reply {
                text = String(repeating: "x", count: MCPConversationRunner.keptResultCharacters + 1024)
            } else { text = "FIXTURE_TOOL_REFUSAL" }
            envelope["result"] = .object(["isError": flag, "content": .array([.object([
                "type": .string("text"), "text": .string(text)
            ])]), "structuredContent": .object(["code": .number(401)]),
                "diagnostic": .object(["category": .string("http"), "code": .number(401), "outcomeUnknown": .bool(false)])])
        case .ok:
            envelope["result"] = .object(["isError": .bool(false), "content": .array([]), "contents": .array([]),
                "diagnostic": .object(["category": .string("rpc"), "code": .number(-32603), "outcomeUnknown": .bool(true)])])
        }
        let body = status == 200 ? try JSONEncoder().encode(JSONValue.object(envelope)) : Data("PRIVATE_FIXTURE_BODY".utf8)
        var data = Data("HTTP/1.1 \(status) Fixture\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(body)
        send(data, on: connection)
    }

    private func send(_ bytes: Data, on connection: NWConnection, close: Bool = true) {
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            if let self, error == nil {
                self.lock.lock()
                self.responseWrites += 1
                self.responseBytes += bytes.count
                self.lock.unlock()
            }
            if close { connection.cancel() }
        })
    }
}
#endif
