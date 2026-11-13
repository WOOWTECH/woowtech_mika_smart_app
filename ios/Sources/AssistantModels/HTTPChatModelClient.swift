import Foundation

/// Meters every request it makes (ModelUsageScope, `usageSink`) exactly once,
/// so wrappers and runners above it never count a reply again.
public struct HTTPChatModelClient: StructuredStreamingChatModelClient, ReferenceDispatchBoundStreamingChatModelClient {
    private let session: URLSession
    private let timeoutNanoseconds: UInt64
    private let usageSink: (any ModelUsageSink)?
    private static let maximumTimeout: UInt64 = 90_000_000_000
    private static let declinedUsageOptions = DeclinedUsageOptions()

    public init(usageSink: (any ModelUsageSink)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        self.init(session: URLSession(configuration: configuration), usageSink: usageSink)
    }

    public init(session: URLSession, usageSink: (any ModelUsageSink)? = nil) {
        self.init(session: session, timeoutNanoseconds: Self.maximumTimeout, usageSink: usageSink)
    }

    // Shorter deadlines let deterministic tests exercise timeouts; never exceeds 90s.
    init(session: URLSession, timeoutNanoseconds: UInt64, usageSink: (any ModelUsageSink)? = nil) {
        self.session = session
        self.timeoutNanoseconds = min(timeoutNanoseconds, Self.maximumTimeout)
        self.usageSink = usageSink
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await complete(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: {})
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                         onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        do {
            let request = try Self.request(messages: messages, configuration: configuration, apiKey: apiKey, stream: false)
            let reply: Reply = try await bounded {
                try Task.checkCancellation()
                meter.dispatching()
                let (bytes, response) = try await session.bytes(for: request, delegate: RejectModelRedirects(onDispatch: onDispatch))
                defer { bytes.task.cancel() }
                try Self.validate(response, stream: false)
                return try await withTaskCancellationHandler {
                    var data = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard data.count < ChatSSEParser.maximumResponseBytes else {
                            throw HTTPChatModelError.responseTooLarge
                        }
                        data.append(byte)
                    }
                    try Task.checkCancellation()
                    return try Self.completion(data)
                } onCancel: {
                    bytes.task.cancel()
                }
            }
            meter.succeeded(reply.usage)
            return reply.text
        } catch {
            meter.failed()
            throw Self.sanitized(error)
        }
    }

    /// Yields text deltas (not accumulated text). Slow consumers fail rather than lose text.
    /// Asks for usage unless this endpoint and model refused that option; the
    /// refusal ends this stream, and only the host may send it again.
    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: {}, onProducerFinished: {})
    }

    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                       onDispatch: @escaping @Sendable () -> Void,
                       onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let worker = Task {
                do {
                    let option = Self.usageOptionKey(configuration)
                    let includeUsage = !Self.declinedUsageOptions.contains(option)
                    let request = try Self.request(messages: messages, configuration: configuration, apiKey: apiKey,
                                                   stream: true, includeUsage: includeUsage)
                    let usage: ModelTokenUsage? = try await bounded {
                        try Task.checkCancellation()
                        meter.dispatching()
                        let (bytes, response) = try await session.bytes(for: request, delegate: RejectModelRedirects(onDispatch: onDispatch))
                        defer { bytes.task.cancel() }
                        // A response proves this request has started even when
                        // URLSession omitted the body-progress delegate callback.
                        onDispatch()
                        if let http = response as? HTTPURLResponse {
                            if (200..<300).contains(http.statusCode), http.mimeType?.lowercased() == "application/json" {
                                // A complete-only endpoint ignored stream=true. Use its
                                // already returned response; never send a second request.
                                let reply = try await withTaskCancellationHandler {
                                    var data = Data()
                                    for try await byte in bytes {
                                        try Task.checkCancellation()
                                        guard data.count < ChatSSEParser.maximumResponseBytes else { throw HTTPChatModelError.responseTooLarge }
                                        data.append(byte)
                                    }
                                    try Task.checkCancellation()
                                    return try Self.completion(data)
                                } onCancel: { bytes.task.cancel() }
                                guard case .enqueued = continuation.yield(reply.text) else { throw HTTPChatModelError.consumerTooSlow }
                                return reply.usage
                            }
                            if [400, 415, 422].contains(http.statusCode) {
                                // Classify only short, complete error bodies. The
                                // body never enters a prompt, UI or diagnostic.
                                let data = try await withTaskCancellationHandler {
                                    var data = Data()
                                    for try await byte in bytes {
                                        try Task.checkCancellation()
                                        guard data.count < 2048 else { throw HTTPChatModelError.httpStatus(http.statusCode) }
                                        data.append(byte)
                                    }
                                    try Task.checkCancellation()
                                    return data
                                } onCancel: { bytes.task.cancel() }
                                if Self.explicitlyRejectsStreaming(data) {
                                    throw HTTPStreamFallbackError.explicitUnsupported(http.statusCode)
                                }
                                if includeUsage && Self.namesUsageOption(data) {
                                    // Remember first: the host's one resend must not ask again.
                                    Self.declinedUsageOptions.insert(option)
                                    throw HTTPStreamFallbackError.usageOptionUnsupported(http.statusCode)
                                }
                                throw HTTPChatModelError.httpStatus(http.statusCode)
                            }
                        }
                        try Self.validate(response, stream: true)
                        return try await withTaskCancellationHandler {
                            var parser = ChatSSEParser()
                            for try await byte in bytes {
                                try Task.checkCancellation()
                                if let text = try parser.append(byte) {
                                    switch continuation.yield(text) {
                                    case .enqueued: break
                                    case .dropped: throw HTTPChatModelError.consumerTooSlow
                                    case .terminated: throw CancellationError()
                                    @unknown default: throw HTTPChatModelError.consumerTooSlow
                                    }
                                }
                                if parser.done { break }
                            }
                            try Task.checkCancellation()
                            try parser.finish()
                            return parser.usage
                        } onCancel: {
                            bytes.task.cancel()
                        }
                    }
                    // Recorded before the end, so a consumer that sees the end sees the count.
                    meter.succeeded(usage)
                    onProducerFinished()
                    continuation.finish()
                } catch {
                    meter.failed()
                    onProducerFinished()
                    continuation.finish(throwing: Self.sanitized(error))
                }
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw HTTPChatModelError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        }
    }

    static func request(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String, stream: Bool,
                        includeUsage: Bool = false) throws -> URLRequest {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !key.isEmpty, (1...8192).contains(configuration.maxOutputTokens),
              !apiKey.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              var parts = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw HTTPChatModelError.invalidConfiguration
        }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        parts.percentEncodedPath = path
        guard let endpoint = parts.url else { throw HTTPChatModelError.invalidConfiguration }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WoowAssistant/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try OpenAIChatRequest.body(model: model, messages: messages, stream: stream,
                                                      maxOutputTokens: configuration.maxOutputTokens,
                                                      vision: configuration.vision, includeUsage: includeUsage)
        return request
    }

    private static func validate(_ response: URLResponse, stream: Bool) throws {
        guard let response = response as? HTTPURLResponse else { throw HTTPChatModelError.invalidResponse }
        if (300..<400).contains(response.statusCode) { throw HTTPChatModelError.redirectRejected }
        guard (200..<300).contains(response.statusCode) else { throw HTTPChatModelError.httpStatus(response.statusCode) }
        let expected = stream ? "text/event-stream" : "application/json"
        guard response.mimeType?.lowercased() == expected else { throw HTTPChatModelError.invalidResponse }
    }

    private static func sanitized(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if error is HTTPStreamFallbackError { return error }
        if let known = error as? HTTPChatModelError { return known }
        if let known = error as? ModelAttachmentError { return known }
        if let network = error as? URLError {
            if network.code == .cancelled { return CancellationError() }
            if network.code == .timedOut { return HTTPChatModelError.timedOut }
            return HTTPChatModelError.transportFailure
        }
        if error is DecodingError { return HTTPChatModelError.invalidResponse }
        return HTTPChatModelError.transportFailure
    }

    private static func completion(_ data: Data) throws -> Reply {
        let response = try JSONDecoder().decode(Completion.self, from: data)
        guard let choice = response.choices.first, choice.finish_reason == "stop" else {
            throw HTTPChatModelError.incompleteResponse
        }
        guard !choice.message.content.isEmpty else { throw HTTPChatModelError.invalidResponse }
        return Reply(text: choice.message.content, usage: response.usage?.value)
    }

    /// In memory only: a relaunch asks this endpoint and model again.
    private static func usageOptionKey(_ configuration: ModelConfiguration) -> String {
        configuration.baseURL.absoluteString + "\n" + configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Some compatible endpoints stream but refuse stream_options, often with
    /// param null or a validation detail (FastAPI's extra_forbidden). Like
    /// Android's OpenAiCompatModel, any short error body naming it counts.
    private static func namesUsageOption(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains("stream_options") == true
    }

    private static func explicitlyRejectsStreaming(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let outer = try? RawCommandEnvelope.fields(in: text),
              let error = outer["error"], let detail = try? RawCommandEnvelope.fields(in: error),
              let codeRaw = detail["code"], let paramRaw = detail["param"],
              let code = try? JSONDecoder().decode(String.self, from: Data(codeRaw.utf8)),
              let param = try? JSONDecoder().decode(String.self, from: Data(paramRaw.utf8)),
              param == "stream" else { return false }
        return ["unsupported_parameter", "unsupported_value", "not_supported"].contains(code.lowercased())
    }

    private struct Reply: Sendable {
        let text: String
        let usage: ModelTokenUsage?
    }
    private struct Completion: Decodable {
        let choices: [Choice]
        let usage: OpenAIReportedUsage?
    }
    private struct Choice: Decodable {
        let message: ModelMessage
        let finish_reason: String?
    }
}

/// Endpoint and model pairs that refused stream_options in this process.
private final class DeclinedUsageOptions: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<String> = []
    func contains(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.contains(key) }
    func insert(_ key: String) { lock.lock(); defer { lock.unlock() }; keys.insert(key) }
}

final class RejectModelRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onDispatch: @Sendable () -> Void
    init(onDispatch: @escaping @Sendable () -> Void = {}) { self.onDispatch = onDispatch }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesSent > 0 { onDispatch() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
