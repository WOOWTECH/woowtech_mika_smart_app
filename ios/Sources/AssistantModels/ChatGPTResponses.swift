import Foundation

/// The model calls on a ChatGPT plan, made the way the Play build makes them (core/model/ResponsesModel.kt
/// @964d7bec): `POST {base}/responses`, always streamed, never stored (`store:false`), the whole context
/// in `input` every time, the system prompt in `instructions` and the conversation's system messages as
/// developer messages. Temperature and output limits are not sent: the plan's route refuses them.
/// iOS asks for text only (its tools run through a structured text command), so there are no `tools`.
/// Validation prototype: no model client uses it yet.
public enum ResponsesRequest {
    public static let encryptedReasoning = "reasoning.encrypted_content"
    /// Play's stand-in for an image the model cannot see.
    public static let imageOmitted = "[screenshot omitted: the current model cannot see images]"

    public struct Message: Equatable, Sendable {
        public enum Role: String, Sendable { case system, user, assistant }
        public let role: Role
        public let text: String
        /// `data:` URLs; sent only when the model can see images.
        public let images: [String]

        public init(role: Role, text: String, images: [String] = []) {
            self.role = role; self.text = text; self.images = images
        }
    }

    /// `reasoning.effort` only when the user chose one; `include` asks for the encrypted reasoning
    /// that tool-call replays need (Play sends it and drops it if refused).
    public static func body(model: String, instructions: String, messages: [Message], vision: Bool,
                            reasoningEffort: String? = nil, includeReasoning: Bool = false) -> [String: Any] {
        var body: [String: Any] = ["model": model, "input": messages.compactMap { item($0, vision: vision) },
                                   "store": false, "stream": true]
        if !instructions.isEmpty { body["instructions"] = instructions }
        if let reasoningEffort { body["reasoning"] = ["effort": reasoningEffort] }
        if includeReasoning { body["include"] = [encryptedReasoning] }
        return body
    }

    static func item(_ message: Message, vision: Bool) -> [String: Any]? {
        if message.role == .assistant {
            guard !message.text.isEmpty else { return nil }
            return ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": message.text]]]
        }
        var content: [[String: Any]] = []
        if !message.text.isEmpty { content.append(["type": "input_text", "text": message.text]) }
        for image in message.images {
            content.append(vision ? ["type": "input_image", "image_url": image] : ["type": "input_text", "text": imageOmitted])
        }
        guard !content.isEmpty else { return nil }
        return ["type": "message", "role": message.role == .system ? "developer" : "user", "content": content]
    }

    /// The token's header is the only one added here; `headers` (User-Agent) go on every request.
    public static func urlRequest(base: URL, token: String?, body: [String: Any],
                                  headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let token, !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// An HTTP error body's `error.code` (or `type`), `message` and `param`; or a bare `detail`.
    static func errorBody(_ body: Data) -> (code: String?, message: String, param: String?)? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any] {
            return ((error["code"] as? String) ?? (error["type"] as? String), (error["message"] as? String) ?? "",
                    error["param"] as? String)
        }
        return (root["detail"] as? String).map { (nil, $0, nil) }
    }

    /// A 400 that refused `include` is sent again without it (Play).
    static func refusedInclude(status: Int, body: Data) -> Bool {
        status == 400 && (errorBody(body)?.param == "include" || String(decoding: body, as: UTF8.self).contains(encryptedReasoning))
    }
}

extension ChatGPTModelError {
    /// The codes in `response.failed`, `error` events and HTTP error bodies (Play ResponsesModel.errorOf).
    /// Nil for a code it doesn't know.
    static func of(code: String?, message: String, param: String?, chatGPTPlan: Bool, model: String) -> ChatGPTModelError? {
        switch code ?? "" {
        case "subscription_sharing_usage_limit_exceeded": return .limitReached
        case "subscription_sharing_user_not_eligible": return .notEligible(String(message.prefix(200)))
        // The plan is briefly unavailable: keep the sign-in, try again later.
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return .server(503)
        case "subscription_sharing_unsupported_capability":
            return .badResponse("the server does not support " + (param ?? "part of the request") + said(message, code))
        case "subscription_sharing_route_not_supported": return .badResponse("the server does not support this route" + said(message, code))
        case "subscription_sharing_invalid_user", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            return .auth
        case "context_length_exceeded": return .contextTooLong
        case "insufficient_quota": return .quotaExceeded
        case "rate_limit_exceeded": return chatGPTPlan ? .limitReached : .rateLimited(retryAfterMs: nil)
        case "model_not_found": return .modelNotFound(model)
        case "server_error": return .server(500)
        default: return nil
        }
    }

    /// An unsuccessful HTTP answer (Play ResponsesModel.httpError): the body's code first, then the status.
    /// On a plan, 403 means the account may not use it this way and 429 is the plan's limit; neither is retried.
    static func http(status: Int, body: Data, retryAfter: String?, chatGPTPlan: Bool, model: String) -> ChatGPTModelError {
        let error = ResponsesRequest.errorBody(body)
        if let error, let known = of(code: error.code, message: error.message, param: error.param, chatGPTPlan: chatGPTPlan, model: model) {
            return known
        }
        switch status {
        case 401: return .auth
        case 403: return chatGPTPlan ? .notEligible(String((error?.message ?? "").prefix(200))) : .auth
        case 429: return chatGPTPlan ? .limitReached : .rateLimited(retryAfterMs: retryAfter.flatMap { Int64($0) }.map { $0 * 1000 })
        case 402: return .quotaExceeded
        case 404: return .modelNotFound(model)
        case 500...599: return .server(status)
        default: return .badResponse("HTTP \(status)")
        }
    }

    private static func said(_ message: String, _ code: String?) -> String {
        let text = message.isEmpty ? (code ?? "") : message
        return text.isEmpty ? "" : " (" + String(text.prefix(200)) + ")"
    }
}

/// A finished reply; `thinking` is the reasoning summary, if the model gave one.
public struct ResponsesReply: Equatable, Sendable {
    public enum Stop: Equatable, Sendable { case endTurn, maxTokens, other }
    public let text: String
    public let thinking: String
    public let usage: ResponsesUsage?
    public let stop: Stop
}

/// `response.usage`: cached input and reasoning output are parts of input and output, not extra.
public struct ResponsesUsage: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let cachedInput: Int
    public let reasoning: Int
}

/// Reads the Responses event stream (Play ResponsesStream): `response.output_text.delta` is text as it
/// comes, `response.output_item.done` a finished item, `response.completed` or `response.incomplete`
/// the end, `response.failed` and `error` a failure. Only an end event makes a reply; a stream that
/// stops before it was cut off.
public struct ResponsesEventStream {
    static let maximumEventBytes = 4 * 1024 * 1024
    let chatGPTPlan: Bool
    let model: String
    private var line: [UInt8] = []
    private var data: [String] = []
    private var skipLF = false
    private var eventBytes = 0
    private var visible = ""
    private var items: [[String: Any]] = []
    private var ending: [String: Any]?
    private var incomplete = false
    /// An end event arrived; nothing after it matters.
    public var finished: Bool { ending != nil }

    public init(chatGPTPlan: Bool, model: String) { self.chatGPTPlan = chatGPTPlan; self.model = model }

    /// One byte of the body; the new text when a delta arrived.
    public mutating func append(_ byte: UInt8) throws -> String? {
        eventBytes += 1
        guard eventBytes <= Self.maximumEventBytes else { throw ChatGPTModelError.badResponse("event too large") }
        if skipLF {
            skipLF = false
            if byte == 10 { return nil }
        }
        guard byte == 10 || byte == 13 else {
            line.append(byte)
            return nil
        }
        skipLF = byte == 13
        guard let text = String(bytes: line, encoding: .utf8) else { throw ChatGPTModelError.badResponse("stream is not UTF-8") }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty { return try dispatch() }
        if text.hasPrefix("data:") {
            var value = text.dropFirst(5)
            if value.hasPrefix(" ") { value = value.dropFirst() }
            data.append(String(value))
        }
        return nil
    }

    /// The body ended: a pending event still counts, then the reply.
    public mutating func end() throws -> ResponsesReply {
        if !line.isEmpty, let text = String(bytes: line, encoding: .utf8), text.hasPrefix("data:") {
            var value = text.dropFirst(5)
            if value.hasPrefix(" ") { value = value.dropFirst() }
            data.append(String(value))
        }
        line = []
        _ = try dispatch()
        return try reply()
    }

    private mutating func dispatch() throws -> String? {
        defer { data = []; eventBytes = 0 }
        guard !data.isEmpty, ending == nil else { return nil }
        let payload = data.joined(separator: "\n")
        if payload == "[DONE]" { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
            throw ChatGPTModelError.badResponse("stream event is not JSON")
        }
        switch root["type"] as? String {
        case "response.output_text.delta":
            guard let delta = root["delta"] as? String, !delta.isEmpty else { return nil }
            visible += delta
            return delta
        case "response.output_item.done":
            if let item = root["item"] as? [String: Any] { items.append(item) }
        case "response.completed":
            ending = (root["response"] as? [String: Any]) ?? [:]
        case "response.incomplete":
            ending = (root["response"] as? [String: Any]) ?? [:]
            incomplete = true
        case "response.failed":
            throw failure((root["response"] as? [String: Any])?["error"] as? [String: Any])
        case "error":
            throw failure((root["error"] as? [String: Any]) ?? root)
        default:
            break
        }
        return nil
    }

    private func failure(_ error: [String: Any]?) -> ChatGPTModelError {
        let code = error?["code"] as? String
        let message = (error?["message"] as? String) ?? ""
        return ChatGPTModelError.of(code: code, message: message, param: error?["param"] as? String,
                                    chatGPTPlan: chatGPTPlan, model: model)
            ?? .badResponse([code, String(message.prefix(200))].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// The server answered with the whole response object instead of a stream.
    public static func reply(fromBody body: Data, chatGPTPlan: Bool, model: String) throws -> ResponsesReply {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw ChatGPTModelError.badResponse("the answer is not JSON")
        }
        var stream = ResponsesEventStream(chatGPTPlan: chatGPTPlan, model: model)
        if let error = root["error"] as? [String: Any] { throw stream.failure(error) }
        stream.ending = root
        stream.incomplete = root["status"] as? String == "incomplete"
        return try stream.reply()
    }

    func reply() throws -> ResponsesReply {
        guard let response = ending else { throw ChatGPTModelError.streamCut }
        let output = items.isEmpty ? ((response["output"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []) : items
        var thinking = ""
        var text = ""
        var refusal = false
        for item in output {
            switch item["type"] as? String {
            case "reasoning":
                for case let summary as [String: Any] in (item["summary"] as? [Any]) ?? [] {
                    thinking += (summary["text"] as? String) ?? ""
                }
            case "message":
                for case let content as [String: Any] in (item["content"] as? [Any]) ?? [] {
                    switch content["type"] as? String {
                    case "output_text": text += (content["text"] as? String) ?? ""
                    case "refusal": refusal = true
                    default: break
                    }
                }
            default:
                break
            }
        }
        if text.isEmpty, !visible.isEmpty { text = visible }
        let reason = (response["incomplete_details"] as? [String: Any])?["reason"] as? String
        if refusal && text.isEmpty { throw ChatGPTModelError.contentRefused }
        if incomplete && reason == "content_filter" && text.isEmpty { throw ChatGPTModelError.contentRefused }
        let stop: ResponsesReply.Stop = !incomplete ? .endTurn : reason == "max_output_tokens" ? .maxTokens : .other
        return ResponsesReply(text: text, thinking: thinking, usage: Self.usage(response["usage"]), stop: stop)
    }

    static func usage(_ value: Any?) -> ResponsesUsage? {
        guard let usage = value as? [String: Any], let input = ChatGPTSignIn.int64(usage["input_tokens"]).map({ Int($0) }) else {
            return nil
        }
        let cached = ChatGPTSignIn.int64((usage["input_tokens_details"] as? [String: Any])?["cached_tokens"]).map { Int($0) } ?? 0
        let output = ChatGPTSignIn.int64(usage["output_tokens"]).map { Int($0) } ?? 0
        let reasoning = ChatGPTSignIn.int64((usage["output_tokens_details"] as? [String: Any])?["reasoning_tokens"]).map { Int($0) } ?? 0
        return ResponsesUsage(input: input, output: output, cachedInput: min(cached, input), reasoning: min(max(reasoning, 0), output))
    }
}

/// One call on the plan (Play ResponsesModel.completeStreaming): a 401 gets a fresh token once, a 400
/// that refused `include` is sent again without it, anything else ends the call.
public struct ChatGPTResponsesClient: Sendable {
    let session: URLSession
    let base: URL
    let token: @Sendable (_ fresh: Bool) async throws -> String
    let headers: [String: String]

    public init(session: URLSession = URLSession(configuration: .ephemeral), base: URL = ChatGPTSignIn.apiBase,
                headers: [String: String] = [:], token: @escaping @Sendable (_ fresh: Bool) async throws -> String) {
        self.session = session; self.base = base; self.headers = headers; self.token = token
    }

    public func complete(model: String, instructions: String, messages: [ResponsesRequest.Message], vision: Bool,
                         reasoningEffort: String? = nil, includeReasoning: Bool = false,
                         onDelta: @Sendable (String) -> Void = { _ in }) async throws -> ResponsesReply {
        var include = includeReasoning
        var fresh = false
        while true {
            let body = ResponsesRequest.body(model: model, instructions: instructions, messages: messages, vision: vision,
                                             reasoningEffort: reasoningEffort, includeReasoning: include)
            let bearer = try await token(fresh)
            let request = try ResponsesRequest.urlRequest(base: base, token: bearer, body: body, headers: headers)
            let answer: (URLSession.AsyncBytes, URLResponse)
            do {
                answer = try await session.bytes(for: request)
            } catch {
                try Task.checkCancellation()
                throw ChatGPTModelError.network(String(describing: type(of: error)))
            }
            let (bytes, response) = answer
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            do {
                if (200...299).contains(status) {
                    if http?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true {
                        return try ResponsesEventStream.reply(fromBody: try await collect(bytes), chatGPTPlan: true, model: model)
                    }
                    var stream = ResponsesEventStream(chatGPTPlan: true, model: model)
                    for try await byte in bytes {
                        if let delta = try stream.append(byte) { onDelta(delta) }
                        if stream.finished { break }
                    }
                    return try stream.end()
                }
                let errorBody = try await collect(bytes)
                if status == 401 && !fresh {
                    fresh = true
                    continue
                }
                if include && ResponsesRequest.refusedInclude(status: status, body: errorBody) {
                    include = false
                    continue
                }
                throw ChatGPTModelError.http(status: status, body: errorBody, retryAfter: http?.value(forHTTPHeaderField: "Retry-After"),
                                             chatGPTPlan: true, model: model)
            } catch let error as ChatGPTModelError {
                throw error
            } catch {
                try Task.checkCancellation()
                throw ChatGPTModelError.network(String(describing: type(of: error)))
            }
        }
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 1024 * 1024 { break }
        }
        return data
    }
}
