import Foundation

struct MCPHTTPReply: Sendable {
    let result: JSONValue?
    let sessionID: String?
    let byteCount: Int
}

final class MCPHTTPTransport: @unchecked Sendable {
    static let maximumResponseBytes = 4 * 1024 * 1024
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        // Configuration is copied by URLSession. Even injected test configurations
        // cannot enable credential, cookie, cache or redirect persistence here.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest, expectedID: String?, deadline: ContinuousClock.Instant) async throws -> MCPHTTPReply {
        do {
            return try await withThrowingTaskGroup(of: MCPHTTPReply.self) { group in
                group.addTask { try await self.receive(request, expectedID: expectedID) }
                group.addTask {
                    try await ContinuousClock().sleep(until: deadline)
                    throw MCPError.timedOut
                }
                defer { group.cancelAll() }
                guard let reply = try await group.next() else { throw MCPError.cancelled }
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw MCPError.timedOut }
                return reply
            }
        } catch let refused as MCPAuthorizationFailure where !Task.isCancelled {
            throw refused
        } catch { throw MCPError.sanitized(error) }
    }

    private func receive(_ request: URLRequest, expectedID: String?) async throws -> MCPHTTPReply {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request, delegate: MCPRejectRedirects())
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse }
        if (300..<400).contains(http.statusCode) { throw MCPError.redirectRejected }
        // A refused token is its own failure with the server's challenge (RFC 6750 §3): a 401, and a 403
        // for a scope the token lacks. Nothing else of the answer is read.
        if http.statusCode == 401 || http.statusCode == 403 {
            let challenge = MCPBearerChallenge(http.value(forHTTPHeaderField: "WWW-Authenticate"))
            if http.statusCode == 401 || challenge?.error == "insufficient_scope" {
                throw MCPAuthorizationFailure(status: http.statusCode, challenge: challenge)
            }
        }
        guard (200..<300).contains(http.statusCode) else { throw MCPError.httpStatus(statusCode: http.statusCode) }
        guard response.expectedContentLength <= Int64(Self.maximumResponseBytes) else { throw MCPError.responseTooLarge }
        let sessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id")
        if let sessionID = sessionID {
            guard !sessionID.isEmpty, sessionID.utf8.count <= 4096,
                  sessionID.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else { throw MCPError.invalidResponse }
        }
        let isSSE = http.mimeType?.lowercased() == "text/event-stream"
        if expectedID == nil {
            guard http.statusCode == 202 else { throw MCPError.invalidResponse }
        } else {
            guard http.statusCode == 200, isSSE || http.mimeType?.lowercased() == "application/json" else {
                throw MCPError.invalidResponse
            }
        }
        return try await withTaskCancellationHandler {
            var data = Data()
            var count = 0
            var parser = MCPSSEParser(expectedID: expectedID ?? "")
            for try await byte in bytes {
                try Task.checkCancellation()
                count += 1
                guard count <= Self.maximumResponseBytes else { throw MCPError.responseTooLarge }
                guard expectedID != nil else { throw MCPError.invalidResponse }
                if isSSE {
                    if let result = try parser.append(byte) {
                        return MCPHTTPReply(result: result, sessionID: sessionID, byteCount: count)
                    }
                } else { data.append(byte) }
            }
            try Task.checkCancellation()
            if let expectedID = expectedID {
                guard !isSSE, let result = try MCPRPCResponse.result(data, expectedID: expectedID) else {
                    throw MCPError.invalidResponse
                }
                return MCPHTTPReply(result: result, sessionID: sessionID, byteCount: count)
            }
            return MCPHTTPReply(result: nil, sessionID: sessionID, byteCount: count)
        } onCancel: { bytes.task.cancel() }
    }
}

/// A `WWW-Authenticate` header's Bearer challenge (RFC 6750 §3, RFC 9728 §5.1): where the server
/// describes its sign-in, the scope it wants and why it refused. Other schemes are skipped.
struct MCPBearerChallenge: Equatable, Sendable {
    var resourceMetadata: String?
    var scope: String?
    var error: String?

    /// Nil when there is no Bearer challenge. Parameters follow RFC 9110 §11.2 (a token or a quoted
    /// string, names in any case); an unquoted URL is read to the next comma or space, like Android.
    init?(_ header: String?) {
        guard let header else { return nil }
        let bytes = Array(header.utf8)
        var index = 0
        var bearer = false
        var found = false
        var params: [String: String] = [:]
        func isToken(_ byte: UInt8) -> Bool {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"): return true
            default: return Array("!#$%&'*+-.^_`|~".utf8).contains(byte)
            }
        }
        func skipSpaces() { while index < bytes.count, bytes[index] == 32 || bytes[index] == 9 { index += 1 } }
        while index < bytes.count {
            while index < bytes.count, [32, 9, UInt8(ascii: ",")].contains(bytes[index]) { index += 1 }
            let start = index
            while index < bytes.count, isToken(bytes[index]) { index += 1 }
            guard index > start else { index += 1; continue }
            let name = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
            skipSpaces()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else {
                // A token without "=" starts the next challenge.
                if bearer { break }
                bearer = name == "bearer"
                found = found || bearer
                continue
            }
            index += 1
            skipSpaces()
            var value = Data()
            if index < bytes.count, bytes[index] == UInt8(ascii: "\"") {
                index += 1
                while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                    if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count { index += 1 }
                    value.append(bytes[index])
                    index += 1
                }
                index += 1
            } else {
                while index < bytes.count, ![32, 9, UInt8(ascii: ",")].contains(bytes[index]) {
                    value.append(bytes[index])
                    index += 1
                }
            }
            if bearer, params[name] == nil { params[name] = String(decoding: value, as: UTF8.self) }
        }
        guard found else { return nil }
        resourceMetadata = params["resource_metadata"]
        scope = params["scope"]
        error = params["error"]
    }
}

/// The server refused the request's token (RFC 6750 §3.1): a 401, or a 403 for a scope the token
/// lacks. MCPClient refreshes an OAuth sign-in once after a 401, and a 401 that names the server's
/// OAuth sign-in asks for one; anything else is `.httpStatus`.
struct MCPAuthorizationFailure: Error, Sendable {
    let status: Int
    let challenge: MCPBearerChallenge?
}

final class MCPRejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
