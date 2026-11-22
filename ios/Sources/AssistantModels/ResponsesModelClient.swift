import Foundation

/// The model calls of the account sign-ins, made the way the Play build makes them
/// (core/model/ResponsesModel.kt): `POST {base}/responses`, always streamed, never stored
/// (`store:false`), the whole context in `input` every time. The system prompt goes in
/// `instructions`; a later system message becomes a developer message. Temperature and output
/// limits are not sent: the ChatGPT plan's route refuses them, so a configuration's
/// maxOutputTokens is left out here.
///
/// No chat path sends native tools or structured output: tools, skills, MCP and web tasks all
/// run through structured text commands the host parses. So there are no `tools`, and no
/// `include` of encrypted reasoning, which only tool-call replays need.
///
/// It keeps HTTPChatModelClient's behavior: text deltas with the ModelStreamHandoff backpressure,
/// images only for a model that sees them, cancellation, 120 s without data and 10 minutes per
/// request, and an output-limit cut that hands over its text before `truncatedResponse`. A 401
/// gets one fresh token and one more try, in the plain calls only: the reference-bound calls
/// allow no automatic retry, so there the token is refreshed for the next request instead.
/// Meters every call exactly once, like HTTPChatModelClient.
public struct ResponsesModelClient: StructuredStreamingChatModelClient, ReferenceDispatchBoundStreamingChatModelClient {
    private let session: URLSession
    private let timeoutNanoseconds: UInt64
    private let usageSink: (any ModelUsageSink)?
    private let accounts: any ModelAccountTokenProviding
    private static let maximumTimeout: UInt64 = 600_000_000_000
    static let maximumErrorBodyBytes = 16 * 1024

    public init(accounts: any ModelAccountTokenProviding, usageSink: (any ModelUsageSink)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        self.init(session: URLSession(configuration: configuration), accounts: accounts, usageSink: usageSink)
    }

    public init(session: URLSession, accounts: any ModelAccountTokenProviding, usageSink: (any ModelUsageSink)? = nil) {
        self.init(session: session, timeoutNanoseconds: Self.maximumTimeout, accounts: accounts, usageSink: usageSink)
    }

    /// Shorter deadlines let tests exercise timeouts; never more than 10 minutes.
    init(session: URLSession, timeoutNanoseconds: UInt64, accounts: any ModelAccountTokenProviding,
         usageSink: (any ModelUsageSink)? = nil) {
        self.session = session
        self.timeoutNanoseconds = min(timeoutNanoseconds, Self.maximumTimeout)
        self.accounts = accounts
        self.usageSink = usageSink
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await complete(messages, configuration, retriesUnauthorized: true, onDispatch: {})
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                         onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        try await complete(messages, configuration, retriesUnauthorized: false, onDispatch: onDispatch)
    }

    /// Yields text deltas, like HTTPChatModelClient.stream.
    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        stream(messages, configuration, retriesUnauthorized: true, onDispatch: {}, onProducerFinished: {})
    }

    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                       onDispatch: @escaping @Sendable () -> Void,
                       onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        stream(messages, configuration, retriesUnauthorized: false, onDispatch: onDispatch, onProducerFinished: onProducerFinished)
    }

    private func complete(_ messages: [ModelMessage], _ configuration: ModelConfiguration, retriesUnauthorized: Bool,
                          onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        let sink = ResponsesSink(continuation: nil)
        do {
            let usage = try await bounded {
                try await self.exchange(messages, configuration, retriesUnauthorized: retriesUnauthorized,
                                        onDispatch: onDispatch, sink: sink, meter: meter)
            }
            meter.succeeded(usage)
            return sink.collected
        } catch {
            meter.failed()
            throw Self.sanitized(error)
        }
    }

    private func stream(_ messages: [ModelMessage], _ configuration: ModelConfiguration, retriesUnauthorized: Bool,
                        onDispatch: @escaping @Sendable () -> Void,
                        onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        let meter = ModelUsageMeter(sink: usageSink, configuration: configuration)
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(ModelStreamHandoff.queuedDeltas)) { continuation in
            let worker = Task {
                let sink = ResponsesSink(continuation: continuation)
                do {
                    let usage = try await bounded {
                        try await self.exchange(messages, configuration, retriesUnauthorized: retriesUnauthorized,
                                                onDispatch: onDispatch, sink: sink, meter: meter)
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

    /// One call: the token, the request and its answer; a 401 at most twice when allowed.
    private func exchange(_ messages: [ModelMessage], _ configuration: ModelConfiguration, retriesUnauthorized: Bool,
                          onDispatch: @escaping @Sendable () -> Void, sink: ResponsesSink,
                          meter: ModelUsageMeter) async throws -> ModelTokenUsage? {
        guard let route = configuration.account else { throw HTTPChatModelError.invalidConfiguration }
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw HTTPChatModelError.invalidConfiguration }
        let body = try ResponsesRequest.body(model: model, messages: messages, vision: configuration.vision)
        var rejected: String?
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let token = try await accounts.accessToken(for: route, rejected: rejected)
            let request = try ResponsesRequest.urlRequest(configuration: configuration, token: token, body: body)
            try Task.checkCancellation()
            meter.dispatching()
            let (bytes, response) = try await session.bytes(for: request, delegate: RejectModelRedirects(onDispatch: onDispatch))
            defer { bytes.task.cancel() }
            // A response proves this request has started even when URLSession
            // omitted the body-progress delegate callback.
            onDispatch()
            guard let http = response as? HTTPURLResponse else { throw HTTPChatModelError.invalidResponse }
            let status = http.statusCode
            if (300..<400).contains(status) { throw HTTPChatModelError.redirectRejected }
            if status == 401 {
                if retriesUnauthorized && attempt == 0 {
                    rejected = token
                    continue
                }
                // No resend here; the next request gets a fresh token.
                if !retriesUnauthorized { _ = try? await accounts.accessToken(for: route, rejected: token) }
                throw ModelAccountError.unauthorized(route.kind)
            }
            guard (200..<300).contains(status) else {
                // Only a short error body is read for its code; it never reaches a prompt, the UI or a log.
                let data = try await Self.collect(bytes, limit: Self.maximumErrorBodyBytes)
                throw ResponsesFailure.http(status: status, body: data ?? Data(), kind: route.kind)
            }
            let parser: ResponsesEventParser
            switch http.mimeType?.lowercased() {
            case "text/event-stream":
                parser = try await withTaskCancellationHandler {
                    var parser = ResponsesEventParser(kind: route.kind)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let delta = try parser.append(byte) { try sink.add(delta) }
                        if parser.ended { break }
                    }
                    if !parser.ended { try parser.endOfStream() }
                    return parser
                } onCancel: {
                    bytes.task.cancel()
                }
            case "application/json":
                // The server answered with the whole response object instead of a stream.
                guard let data = try await Self.collect(bytes, limit: ResponsesEventParser.maximumResponseBytes) else {
                    throw HTTPChatModelError.responseTooLarge
                }
                parser = try ResponsesEventParser.whole(data, kind: route.kind)
            default:
                throw HTTPChatModelError.invalidResponse
            }
            bytes.task.cancel()
            try Task.checkCancellation()
            let outcome = parser.outcome()
            switch outcome.end {
            case .complete:
                try sink.add(outcome.unstreamed)
                try await sink.flush()
            case .truncated:
                // The output limit cut the reply: its text so far still reaches the reader first.
                try sink.add(outcome.unstreamed)
                try await sink.flush()
                throw HTTPChatModelError.truncatedResponse
            case .cut, .incomplete:
                throw HTTPChatModelError.incompleteResponse
            case .refused:
                throw ModelAccountError.contentRefused
            case .empty:
                throw HTTPChatModelError.invalidResponse
            }
            try Task.checkCancellation()
            return outcome.usage
        }
        throw ModelAccountError.unauthorized(route.kind)
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

    /// The body up to `limit` bytes; nil when it is longer.
    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data? {
        try await withTaskCancellationHandler {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { return nil }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } onCancel: {
            bytes.task.cancel()
        }
    }

    static func sanitized(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if error is ModelAccountError || error is HTTPChatModelError || error is ModelAttachmentError { return error }
        if let network = error as? URLError {
            if network.code == .cancelled { return CancellationError() }
            if network.code == .timedOut { return HTTPChatModelError.timedOut }
            return HTTPChatModelError.transportFailure
        }
        if error is DecodingError { return HTTPChatModelError.invalidResponse }
        return HTTPChatModelError.transportFailure
    }
}

/// Text on its way to the reader: collected for complete, handed on with backpressure for stream.
/// Used by one producer task at a time.
final class ResponsesSink: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var waiting = ""
    private(set) var collected = ""

    init(continuation: AsyncThrowingStream<String, Error>.Continuation?) { self.continuation = continuation }

    func add(_ text: String) throws {
        guard !text.isEmpty else { return }
        guard let continuation else {
            collected += text
            return
        }
        waiting += text
        if try ModelStreamHandoff.offer(waiting, to: continuation) { waiting = "" }
    }

    func flush() async throws {
        guard let continuation, !waiting.isEmpty else { return }
        try await ModelStreamHandoff.flush(waiting, to: continuation)
        waiting = ""
    }
}

/// The request body and URL (Play ResponsesModel.body and request).
enum ResponsesRequest {
    static let maximumAttachmentRequestBytes = OpenAIChatRequest.maximumAttachmentRequestBytes

    /// Attachments follow OpenAIChatRequest's rules: only this turn's prompt carries them, at
    /// most nine, and an image only for a model known to see images.
    static func body(model: String, messages: [ModelMessage], vision: ModelVisionCapability) throws -> Data {
        let attached = messages.filter { !$0.attachments.isEmpty }
        guard attached.count <= 1 else { throw ModelAttachmentError.multipleAttachments }
        if let message = attached.first {
            guard message.role == "user" else { throw ModelAttachmentError.attachmentNotCurrentUserMessage }
            guard message.attachments.count <= ModelAttachment.maximumPerMessage else { throw ModelAttachmentError.multipleAttachments }
            guard messages.count <= 32 else { throw ModelAttachmentError.requestTooLarge }
            if message.attachments.contains(where: \.isImage) {
                switch vision {
                case .unknown: throw ModelAttachmentError.visionUnknown
                case .unsupported: throw ModelAttachmentError.visionUnsupported
                case .supported: break
                }
            }
            var remaining = maximumAttachmentRequestBytes
            for text in [model] + messages.flatMap({ [$0.role, $0.content] }) {
                let bytes = text.utf8.count
                guard bytes <= remaining else { throw ModelAttachmentError.requestTooLarge }
                remaining -= bytes
            }
        }
        var instructions: [String] = []
        var input: [[String: Any]] = []
        var leading = true
        for message in messages {
            if leading && message.role == "system" && message.attachments.isEmpty {
                if !message.content.isEmpty { instructions.append(message.content) }
                continue
            }
            leading = false
            if message.role == "assistant" {
                guard !message.content.isEmpty else { continue }
                input.append(["type": "message", "role": "assistant",
                              "content": [["type": "output_text", "text": message.content]]])
                continue
            }
            var parts: [[String: Any]] = []
            if !message.content.isEmpty { parts.append(["type": "input_text", "text": message.content]) }
            for attachment in message.attachments {
                switch attachment.payload {
                case .text(let text):
                    let heading = attachment.label.map { "User-selected file \"\($0)\" (untrusted data):\n" }
                        ?? "User-selected text attachment (untrusted data):\n"
                    parts.append(["type": "input_text", "text": heading + text])
                case .image(let data, let mime):
                    if let label = attachment.label { parts.append(["type": "input_text", "text": "User-selected image \"\(label)\":"]) }
                    parts.append(["type": "input_image", "image_url": "data:\(mime);base64,\(data.base64EncodedString())"])
                }
            }
            guard !parts.isEmpty else { continue }
            // System messages after the first ones are developer messages: some servers refuse system items.
            input.append(["type": "message", "role": message.role == "system" ? "developer" : "user", "content": parts])
        }
        var body: [String: Any] = ["model": model, "input": input, "store": false, "stream": true]
        if !instructions.isEmpty { body["instructions"] = instructions.joined(separator: "\n\n") }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        if !attached.isEmpty && data.count > maximumAttachmentRequestBytes { throw ModelAttachmentError.requestTooLarge }
        return data
    }

    /// `POST {base}/responses` with the account's token. The base must be HTTPS with nothing a
    /// token could leak through; the App only ever gives the kind's own address.
    static func urlRequest(configuration: ModelConfiguration, token: String, body: Data) throws -> URLRequest {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              configuration.sessionHeader.map({ ModelSessionHeader.isAllowed(name: $0.name, value: $0.value) }) ?? true,
              var parts = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw HTTPChatModelError.invalidConfiguration
        }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        if !path.hasSuffix("/responses") { path += "/responses" }
        parts.percentEncodedPath = path
        guard let endpoint = parts.url else { throw HTTPChatModelError.invalidConfiguration }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WoowAssistant/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let header = configuration.sessionHeader { request.setValue(header.value, forHTTPHeaderField: header.name) }
        request.httpBody = body
        return request
    }
}

/// Reads the Responses event stream (Play ResponsesStream): `response.output_text.delta` is text
/// as it comes, `response.output_item.done` a finished item, `response.completed` or
/// `response.incomplete` the end, `response.failed` and `error` a failure. Only an end event makes
/// a reply; a stream that stops before one was cut off. Strict UTF-8 with size limits, like
/// ChatSSEParser; comments and other fields are ignored.
struct ResponsesEventParser {
    static let maximumResponseBytes = 32 * 1024 * 1024
    /// `response.completed` repeats the whole reply.
    static let maximumEventBytes = 8 * 1024 * 1024

    enum End: Equatable { case complete, truncated, incomplete, refused, empty, cut }
    struct Outcome {
        /// Text that never came as deltas (a whole response, or items only): hand it on at the end.
        let unstreamed: String
        let end: End
        let usage: ModelTokenUsage?
    }

    let kind: ModelAccountKind
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var totalBytes = 0
    private var eventBytes = 0
    private var skipLF = false
    private var firstLine = true
    private var receivedText = false
    private var sawItems = false
    private var itemText = ""
    private var refused = false
    private var incomplete = false
    private var incompleteReason: String?
    private(set) var ended = false
    private(set) var usage: ModelTokenUsage?

    init(kind: ModelAccountKind) { self.kind = kind }

    /// One byte of the body; the new text when a delta arrived.
    mutating func append(_ byte: UInt8) throws -> String? {
        totalBytes += 1
        eventBytes += 1
        guard totalBytes <= Self.maximumResponseBytes, eventBytes <= Self.maximumEventBytes else {
            throw HTTPChatModelError.responseTooLarge
        }
        if skipLF {
            skipLF = false
            if byte == 10 { return nil }
        }
        guard byte == 13 || byte == 10 else {
            line.append(byte)
            return nil
        }
        skipLF = byte == 13
        return try finishLine()
    }

    /// The body ended without a blank line after the last event: that event still counts when
    /// it is complete; a half-sent one is a cut, not an unreadable answer.
    mutating func endOfStream() throws {
        if !line.isEmpty {
            guard let text = String(bytes: line, encoding: .utf8) else { throw HTTPChatModelError.invalidResponse }
            line.removeAll()
            field(text)
        }
        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll()
        guard (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) != nil else { return }
        _ = try dispatch(payload)
    }

    private mutating func finishLine() throws -> String? {
        guard var text = String(bytes: line, encoding: .utf8) else { throw HTTPChatModelError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if firstLine {
            firstLine = false
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        }
        if text.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); eventBytes = 0 }
            guard !dataLines.isEmpty else { return nil }
            return try dispatch(dataLines.joined(separator: "\n"))
        }
        field(text)
        return nil
    }

    private mutating func field(_ text: String) {
        if text.hasPrefix(":") { return }
        let split = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard split[0] == "data" else { return }
        var value = split.count == 2 ? String(split[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        dataLines.append(value)
    }

    private mutating func dispatch(_ payload: String) throws -> String? {
        guard !ended, payload != "[DONE]" else { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
            throw HTTPChatModelError.invalidResponse
        }
        switch root["type"] as? String {
        case "response.output_text.delta":
            guard let delta = root["delta"] as? String, !delta.isEmpty else { return nil }
            receivedText = true
            return delta
        case "response.output_item.done":
            if let item = root["item"] as? [String: Any] {
                sawItems = true
                absorb(item)
            }
        case "response.completed":
            finish(root["response"] as? [String: Any], incomplete: false)
        case "response.incomplete":
            finish(root["response"] as? [String: Any], incomplete: true)
        case "response.failed":
            throw ResponsesFailure.stream((root["response"] as? [String: Any])?["error"] as? [String: Any], kind: kind)
        case "error":
            throw ResponsesFailure.stream((root["error"] as? [String: Any]) ?? root, kind: kind)
        default:
            break
        }
        return nil
    }

    private mutating func absorb(_ item: [String: Any]) {
        guard item["type"] as? String == "message" else { return }
        for case let part as [String: Any] in (item["content"] as? [Any]) ?? [] {
            switch part["type"] as? String {
            case "output_text": itemText += (part["text"] as? String) ?? ""
            case "refusal": refused = true
            default: break
            }
        }
    }

    private mutating func finish(_ response: [String: Any]?, incomplete flag: Bool) {
        ended = true
        let response = response ?? [:]
        incomplete = flag || response["status"] as? String == "incomplete"
        incompleteReason = (response["incomplete_details"] as? [String: Any])?["reason"] as? String
        usage = Self.usageReport(response["usage"])
        if !sawItems, let output = response["output"] as? [Any] {
            for case let item as [String: Any] in output { absorb(item) }
        }
    }

    /// The whole response object a server sent instead of a stream.
    static func whole(_ data: Data, kind: ModelAccountKind) throws -> ResponsesEventParser {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HTTPChatModelError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] { throw ResponsesFailure.stream(error, kind: kind) }
        var parser = ResponsesEventParser(kind: kind)
        parser.finish(root, incomplete: root["status"] as? String == "incomplete")
        return parser
    }

    func outcome() -> Outcome {
        guard ended else { return Outcome(unstreamed: "", end: .cut, usage: nil) }
        let unstreamed = receivedText ? "" : itemText
        let hasText = receivedText || !itemText.isEmpty
        let end: End
        if incomplete {
            switch incompleteReason ?? "" {
            case "max_output_tokens": end = .truncated
            case "content_filter" where !hasText: end = .refused
            default: end = .incomplete
            }
        } else if !hasText {
            end = refused ? .refused : .empty
        } else {
            end = .complete
        }
        return Outcome(unstreamed: unstreamed, end: end, usage: end == .complete ? usage : nil)
    }

    /// `response.usage`; cached input and reasoning output are parts of input and output.
    static func usageReport(_ raw: Any?) -> ModelTokenUsage? {
        guard let usage = raw as? [String: Any] else { return nil }
        func count(_ value: Any?) -> Int? {
            guard let number = ChatGPTSignIn.int64(value), number >= 0, number <= Int64(Int32.max) else { return nil }
            return Int(number)
        }
        let input = count(usage["input_tokens"])
        let output = count(usage["output_tokens"])
        let cached = count((usage["input_tokens_details"] as? [String: Any])?["cached_tokens"])
        let reasoning = count((usage["output_tokens_details"] as? [String: Any])?["reasoning_tokens"])
        return ModelTokenUsage(inputTokens: input, outputTokens: output, totalTokens: count(usage["total_tokens"]),
                               cachedInputTokens: cached.flatMap { $0 <= (input ?? .max) ? $0 : nil },
                               reasoningTokens: reasoning.flatMap { $0 <= (output ?? .max) ? $0 : nil })
    }
}

/// The error codes in `response.failed`, `error` events and HTTP error bodies (Play
/// ResponsesModel.errorOf and httpError). Only the code and status decide; the provider's words
/// never leave this file.
enum ResponsesFailure {
    static func known(code: String?, kind: ModelAccountKind) -> Error? {
        switch code ?? "" {
        case "subscription_sharing_usage_limit_exceeded": return ModelAccountError.planLimitReached
        case "subscription_sharing_user_not_eligible": return ModelAccountError.planNotEligible
        // The plan is briefly unavailable: keep the sign-in, try again later.
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return HTTPChatModelError.httpStatus(503)
        case "subscription_sharing_unsupported_capability", "subscription_sharing_route_not_supported":
            return HTTPChatModelError.invalidResponse
        case "subscription_sharing_invalid_user", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            return ModelAccountError.unauthorized(kind)
        case "context_length_exceeded": return ModelAccountError.contextTooLong
        case "insufficient_quota": return HTTPChatModelError.httpStatus(402)
        case "rate_limit_exceeded": return kind == .chatGPT ? ModelAccountError.planLimitReached : HTTPChatModelError.httpStatus(429)
        case "model_not_found": return HTTPChatModelError.httpStatus(404)
        case "server_error": return HTTPChatModelError.httpStatus(500)
        default: return nil
        }
    }

    static func stream(_ error: [String: Any]?, kind: ModelAccountKind) -> Error {
        known(code: (error?["code"] as? String) ?? (error?["type"] as? String), kind: kind) ?? HTTPChatModelError.invalidResponse
    }

    /// The body's code first, then the status. On the ChatGPT plan 403 means the account may not
    /// use it this way and 429 is the plan's limit; for an xAI sign-in 403 means the subscription
    /// tier cannot use this interface. None of these is retried.
    static func http(status: Int, body: Data, kind: ModelAccountKind) -> Error {
        let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = root?["error"] as? [String: Any]
        if let known = known(code: (error?["code"] as? String) ?? (error?["type"] as? String), kind: kind) { return known }
        switch status {
        case 401: return ModelAccountError.unauthorized(kind)
        case 403: return kind == .xai ? ModelAccountError.planNotAllowed(kind) : ModelAccountError.planNotEligible
        case 429: return kind == .chatGPT ? ModelAccountError.planLimitReached : HTTPChatModelError.httpStatus(429)
        default: return HTTPChatModelError.httpStatus(status)
        }
    }
}
