import Foundation

/// Meters every request it makes (ModelUsageScope, `usageSink`) exactly once,
/// so wrappers and runners above it never count a reply again.
public struct HTTPChatModelClient: StructuredStreamingChatModelClient, ReferenceDispatchBoundStreamingChatModelClient {
    private let session: URLSession
    private let timeoutNanoseconds: UInt64
    private let usageSink: (any ModelUsageSink)?
    private let observeHTTPFailure: @Sendable (ModelHTTPFailureDiagnostic) -> Void
    /// A whole request, streamed or not, may take up to 10 minutes; one that stalls
    /// ends after 120 s without data (timeoutIntervalForRequest), like the Play
    /// build's model client (ProviderStore.kt: readTimeout 120 s, no call timeout).
    /// With no reply limit, a long answer streams for more than 90 s.
    private static let maximumTimeout: UInt64 = 600_000_000_000
    private static let declinedUsageOptions = DeclinedUsageOptions()

    public init(usageSink: (any ModelUsageSink)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        self.init(session: URLSession(configuration: configuration), usageSink: usageSink)
    }

    public init(session: URLSession, usageSink: (any ModelUsageSink)? = nil) {
        self.init(session: session, timeoutNanoseconds: Self.maximumTimeout, usageSink: usageSink)
    }

    // Shorter deadlines let deterministic tests exercise timeouts; never exceeds 10 minutes.
    init(session: URLSession, timeoutNanoseconds: UInt64, usageSink: (any ModelUsageSink)? = nil,
         observeHTTPFailure: @escaping @Sendable (ModelHTTPFailureDiagnostic) -> Void = { $0.log() }) {
        self.session = session
        self.timeoutNanoseconds = min(timeoutNanoseconds, Self.maximumTimeout)
        self.usageSink = usageSink
        self.observeHTTPFailure = observeHTTPFailure
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await complete(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: {})
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                         onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        do {
            let request = try Self.request(messages: messages, configuration: configuration, apiKey: apiKey, stream: false)
            let reply: Reply = try await bounded { diagnosticDeadline in
                try Task.checkCancellation()
                meter.dispatching()
                let (bytes, response) = try await session.bytes(for: request, delegate: RejectModelRedirects(onDispatch: onDispatch))
                defer { bytes.task.cancel() }
                try await diagnoseHTTPFailure(response, bytes: bytes, deadline: diagnosticDeadline)
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

    /// Yields text deltas (not accumulated text). A reader that falls behind gets the
    /// text that waited joined into later deltas (ModelStreamHandoff), never a failure
    /// and never a loss; the response size limit still bounds what can wait.
    /// Asks for usage unless this endpoint and model refused that option; the
    /// refusal ends this stream, and only the host may send it again.
    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: {}, onProducerFinished: {})
    }

    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                       onDispatch: @escaping @Sendable () -> Void,
                       onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(ModelStreamHandoff.queuedDeltas)) { continuation in
            let worker = Task {
                do {
                    let option = Self.usageOptionKey(configuration)
                    let includeUsage = !Self.declinedUsageOptions.contains(option)
                    let request = try Self.request(messages: messages, configuration: configuration, apiKey: apiKey,
                                                   stream: true, includeUsage: includeUsage)
                    let usage: ModelTokenUsage? = try await bounded { diagnosticDeadline in
                        try Task.checkCancellation()
                        meter.dispatching()
                        let (bytes, response) = try await session.bytes(for: request, delegate: RejectModelRedirects(onDispatch: onDispatch))
                        defer { bytes.task.cancel() }
                        // A response proves this request has started even when
                        // URLSession omitted the body-progress delegate callback.
                        onDispatch()
                        try await diagnoseHTTPFailure(response, bytes: bytes, deadline: diagnosticDeadline)
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
                            var waiting = ""
                            do {
                                for try await byte in bytes {
                                    try Task.checkCancellation()
                                    if let text = try parser.append(byte) {
                                        waiting += text
                                        if try ModelStreamHandoff.offer(waiting, to: continuation) { waiting = "" }
                                    }
                                    if parser.done { break }
                                }
                            } catch HTTPChatModelError.truncatedResponse {
                                // [DONE] after a cut: the text so far still reaches the reader first.
                                bytes.task.cancel()
                                try await ModelStreamHandoff.flush(waiting, to: continuation)
                                throw HTTPChatModelError.truncatedResponse
                            }
                            // The request is over; a slow reader still gets the text that
                            // waited, before the end or a cut reply's truncatedResponse.
                            bytes.task.cancel()
                            try await ModelStreamHandoff.flush(waiting, to: continuation)
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

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable (ModelHTTPDiagnosticDeadline) async throws -> T) async throws -> T {
        let diagnosticDeadline = ModelHTTPDiagnosticDeadline()
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation(diagnosticDeadline) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                try Task.checkCancellation()
                throw diagnosticDeadline.errorAtDeadline
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
        // Only a custom service saved without a key may go without one. A signed-in
        // account's request belongs to Responses (ModelProviderClient), never here.
        guard configuration.account == nil, !model.isEmpty, !key.isEmpty || !configuration.requiresKey, configuration.maxOutputTokens.map({ (1...8192).contains($0) }) ?? true,
              !apiKey.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              configuration.sessionHeader.map({ ModelSessionHeader.isAllowed(name: $0.name, value: $0.value) }) ?? true,
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
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WoowAssistant/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        if let header = configuration.sessionHeader { request.setValue(header.value, forHTTPHeaderField: header.name) }
        request.httpBody = try OpenAIChatRequest.body(model: model, messages: messages, stream: stream,
                                                      maxOutputTokens: configuration.maxOutputTokens,
                                                      vision: configuration.vision, includeUsage: includeUsage)
        return request
    }

    private func diagnoseHTTPFailure(_ response: URLResponse, bytes: URLSession.AsyncBytes,
                                     deadline: ModelHTTPDiagnosticDeadline) async throws {
        guard let http = response as? HTTPURLResponse,
              let diagnostic = ModelHTTPFailureDiagnostic(response: http) else { return }
        if http.statusCode == 429 { deadline.record429() }
        // Publish headers first, so a stalled/truncated body cannot erase the actual status.
        observeHTTPFailure(diagnostic)
        if http.statusCode == 429 {
            let body = try await ModelHTTPFailureBody.collect(bytes)
            observeHTTPFailure(diagnostic.classifying(body))
        }
        // The existing validator/fallback logic still throws exactly the same typed error.
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
            throw response.choices.first?.finish_reason == "length"
                ? HTTPChatModelError.truncatedResponse : HTTPChatModelError.incompleteResponse
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

/// Hands streamed text to a reader without failing or losing any when it falls behind.
/// The 2026-11-16 iPad test failed a long reply with consumerTooSlow: each delta redrew
/// the growing reply, so the reader fell more than 256 deltas behind a fast stream.
/// Text that does not fit in the queue waits and goes out joined with the next delta.
public enum ModelStreamHandoff {
    /// Small, so a reader that falls behind soon gets joined text instead of a long backlog.
    public static let queuedDeltas = 16

    /// False when the queue is full: keep the text and offer it again joined with more.
    public static func offer(_ text: String, to continuation: AsyncThrowingStream<String, Error>.Continuation) throws -> Bool {
        switch continuation.yield(text) {
        case .enqueued: return true
        case .dropped: return false
        case .terminated: throw CancellationError()
        @unknown default: return false
        }
    }

    /// Waits for room for the text that is still waiting; cancellation ends the wait.
    public static func flush(_ text: String, to continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        guard !text.isEmpty else { return }
        while try !offer(text, to: continuation) { try await Task.sleep(nanoseconds: 10_000_000) }
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
