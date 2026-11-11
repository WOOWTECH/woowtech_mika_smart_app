import Foundation

private struct Failure: Error { let message: String }
private actor EventBox {
    private var values: [ModelStreamWithUsageEvent] = []
    func append(_ value: ModelStreamWithUsageEvent) { values.append(value) }
    func snapshot() -> [ModelStreamWithUsageEvent] { values }
}

@main struct CheckModelTokenUsage {
    static let key = "synthetic-key-only"
    static let messages = [ModelMessage(role: "user", content: "fixture")]
    static let text = #"data: {"choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":null}]}"# + "\n\n"
    static let stop = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\n"
    static let done = "data: [DONE]\n\n"
    static func json(_ usage: String?) -> Data {
        Data((#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]"# +
              (usage.map { ",\"usage\":" + $0 } ?? "") + "}").utf8)
    }
    static func event(_ usage: String) -> String { "data: {\"choices\":[],\"usage\":" + usage + "}\n\n" }
    static func body(_ request: URLRequest?) throws -> [String: Any] {
        guard let request else { throw Failure(message: "missing intercepted request") }
        var data = request.httpBody ?? Data()
        if request.httpBody == nil {
            guard let stream = request.httpBodyStream else { throw Failure(message: "missing request body") }
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0, data.count + count <= 64 * 1024 else { throw Failure(message: "invalid request body") }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: "invalid request JSON") }
        return result
    }
    static func wait(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw Failure(message: "fixture timed out")
    }
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            checks += 1
            if !value() { throw Failure(message: message) }
        }
        let session = ModelProtocolFixture.session()
        defer { session.invalidateAndCancel() }
        let client = HTTPChatModelClient(session: session)
        func complete(_ body: Data) async throws -> ModelCompletionWithUsage {
            let fixture = ModelProtocolFixture.Scenario(chunks: [body])
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let result = try await client.completeWithUsage(messages: messages, configuration: .init(baseURL: url, model: "fixture"), apiKey: key)
            try check(fixture.requestCount == 1, "complete sends once")
            return result
        }
        let all = #"{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19,"prompt_tokens_details":{"cached_tokens":4},"completion_tokens_details":{"reasoning_tokens":3}}"#
        let success = try await complete(json(all))
        try check(success.text == "ok" && success.usage?.inputTokens == 12 && success.usage?.outputTokens == 7 &&
                  success.usage?.totalTokens == 19 && success.usage?.cachedInputTokens == 4 && success.usage?.reasoningTokens == 3, "complete retains reported fields")
        let missing = try await complete(json(nil)), nullUsage = try await complete(json("null"))
        let badUsage = try await complete(json(#"{"prompt_tokens":-1,"completion_tokens":true,"total_tokens":"7"}"#))
        try check(missing.usage == nil, "missing usage remains unknown")
        try check(nullUsage.usage == nil, "null usage remains unknown")
        try check(badUsage.usage == nil, "bad fields are not zero")
        let partial = try await complete(json(#"{"completion_tokens":0}"#))
        try check(partial.usage?.outputTokens == 0 && partial.usage?.inputTokens == nil && partial.usage?.totalTokens == nil, "explicit zero differs from unreported")
        let cache = try await complete(json(#"{"prompt_cache_hit_tokens":2,"prompt_cache_miss_tokens":5}"#))
        try check(cache.usage?.inputTokens == 7 && cache.usage?.cachedInputTokens == 2 && cache.usage?.outputTokens == nil, "cache hit/miss source")
        let inconsistent = try await complete(json(#"{"prompt_tokens":3,"completion_tokens":2,"prompt_tokens_details":{"cached_tokens":9},"completion_tokens_details":{"reasoning_tokens":8}}"#))
        try check(inconsistent.usage?.inputTokens == 3 && inconsistent.usage?.cachedInputTokens == nil && inconsistent.usage?.reasoningTokens == nil, "invalid subsets remain unknown")
        let overflow = try await complete(json(#"{"prompt_cache_hit_tokens":9223372036854775807,"prompt_cache_miss_tokens":1}"#))
        try check(overflow.usage?.inputTokens == nil, "cache addition cannot overflow")

        func stream(_ fixture: ModelProtocolFixture.Scenario, request: ModelStreamUsageRequest = .ifProvided) async throws -> [ModelStreamWithUsageEvent] {
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            var result: [ModelStreamWithUsageEvent] = []
            for try await event in client.streamWithUsage(messages: messages, configuration: .init(baseURL: url, model: "fixture"), apiKey: key, usageRequest: request) { result.append(event) }
            try check(fixture.requestCount == 1, "stream sends once")
            return result
        }
        let sse = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data((text + stop + event(all) + done).utf8)])
        let events = try await stream(sse, request: .requestOpenAICompatible)
        try check(events.count == 2 && events.first == .text("ok"), "text precedes terminal")
        guard case .completed(let usage) = events.last else { throw Failure(message: "missing terminal") }
        try check(usage == success.usage, "SSE usage matches complete")
        let sseBody = try body(sse.lastRequest)
        try check((sseBody["stream_options"] as? [String: Bool])?["include_usage"] == true, "explicit opt-in is on wire")
        let attachment = try ModelAttachment.text(utf8: Data("synthetic attachment".utf8))
        let attachedRequest = try HTTPChatModelClient.request(messages: [.init(userText: "question", attachment: attachment)],
            configuration: .init(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture"),
            apiKey: key, stream: true, includeUsage: true)
        let attachedBody = try body(attachedRequest)
        let wire = attachedBody["messages"] as? [[String: Any]]
        try check((attachedBody["stream_options"] as? [String: Bool])?["include_usage"] == true &&
                  (wire?.first?["content"] as? [[String: String]])?.count == 2, "usage opt-in preserves attachment wire shape")
        let noUsage = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data((text + stop + done).utf8)])
        let unknown = try await stream(noUsage)
        try check(unknown.last == .completed(usage: nil), "successful missing SSE usage is unknown")
        let defaultBody = try body(noUsage.lastRequest)
        try check(defaultBody["stream_options"] == nil, "default request remains unchanged")
        let fallback = ModelProtocolFixture.Scenario(chunks: [json(all)])
        let fallbackEvents = try await stream(fallback)
        try check(fallbackEvents == [.text("ok"), .completed(usage: success.usage)], "JSON stream fallback preserves usage without retry")

        let truncated = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data((text + stop + event(all)).utf8)])
        let truncatedURL = ModelProtocolFixture.register(truncated); defer { ModelProtocolFixture.remove(truncatedURL) }
        var sawCompletion = false
        do {
            for try await value in client.streamWithUsage(messages: messages, configuration: .init(baseURL: truncatedURL, model: "fixture"), apiKey: key) {
                if case .completed = value { sawCompletion = true }
            }
            throw Failure(message: "truncated stream accepted")
        } catch HTTPChatModelError.incompleteResponse { }
        try check(!sawCompletion, "usage before truncated DONE is not published")

        let held = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data((text + stop + event(all)).utf8)], holdAfterBody: true)
        let heldURL = ModelProtocolFixture.register(held); defer { ModelProtocolFixture.remove(heldURL) }
        let box = EventBox()
        let work = Task {
            do {
                for try await value in client.streamWithUsage(messages: messages, configuration: .init(baseURL: heldURL, model: "fixture"), apiKey: key) {
                    await box.append(value)
                }
            } catch { }
        }
        try await wait { await box.snapshot().contains(.text("ok")) && held.bodyDelivered }
        work.cancel(); await work.value
        held.releaseHeldResponses()
        let cancelledEvents = await box.snapshot()
        try check(cancelledEvents == [.text("ok")], "cancelled stream publishes no terminal usage")
        try await wait { held.stopCount > 0 }
        try check(held.requestCount == 1, "cancel does not retry")

        let heldComplete = ModelProtocolFixture.Scenario(chunks: [json(all)], holdAfterBody: true)
        let heldCompleteURL = ModelProtocolFixture.register(heldComplete); defer { ModelProtocolFixture.remove(heldCompleteURL) }
        let pendingComplete = Task {
            try await client.completeWithUsage(messages: messages, configuration: .init(baseURL: heldCompleteURL, model: "fixture"), apiKey: key)
        }
        try await wait { heldComplete.bodyDelivered }
        pendingComplete.cancel()
        do { _ = try await pendingComplete.value; throw Failure(message: "cancelled completion returned usage") }
        catch is CancellationError { }
        heldComplete.releaseHeldResponses()
        try await wait { heldComplete.stopCount > 0 }
        try check(heldComplete.requestCount == 1, "cancelled completion has no result and no retry")
        let after = try await complete(json(nil))
        try check(after.usage == nil, "later request cannot reuse earlier usage")

        let rejected = ModelProtocolFixture.Scenario(status: 400, chunks: [Data(#"{"error":{"code":"unsupported_parameter","param":"stream_options"}}"#.utf8)])
        do { _ = try await stream(rejected, request: .requestOpenAICompatible); throw Failure(message: "unsupported option accepted") }
        catch HTTPChatModelError.httpStatus(400) { }
        try check(rejected.requestCount == 1, "unsupported usage option never triggers retry")
        print("PASS model usage: \(checks) assertions; intercepted HTTP only")
    }
}
