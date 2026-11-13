import Foundation

/// Token usage through the real transport and parser. ModelProtocolFixture
/// intercepts every request; nothing reaches a network or a provider.
private struct Failure: Error { let message: String }

private final class EventLog: ModelUsageSink, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ModelUsageEvent] = []
    func record(_ event: ModelUsageEvent) { lock.lock(); defer { lock.unlock() }; values.append(event) }
    var events: [ModelUsageEvent] { lock.lock(); defer { lock.unlock() }; return values }
}

private actor Fragments {
    private var values: [String] = []
    func add(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

/// The request body exactly as it was before usage was requested.
private struct LegacyBody: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
    let max_tokens: Int
}

@MainActor @main struct CheckModelTokenUsage {
    typealias Snapshot = ModelUsageTally.Snapshot
    typealias Scenario = ModelProtocolFixture.Scenario
    static let key = "synthetic-key-only"
    static let messages = [ModelMessage(role: "user", content: "fixture")]
    static let text = #"data: {"choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":null}]}"# + "\n\n"
    static let stop = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\n"
    static let done = "data: [DONE]\n\n"
    static let all = #"{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19,"prompt_tokens_details":{"cached_tokens":4},"completion_tokens_details":{"reasoning_tokens":3}}"#
    static let allUsage = ModelTokenUsage(inputTokens: 12, outputTokens: 7, totalTokens: 19, cachedInputTokens: 4, reasoningTokens: 3)
    static let allCounted = Snapshot(replies: 1, input: 12, output: 7, cached: 4)
    static let refusal = Data(#"{"error":{"code":"unsupported_parameter","param":"stream_options","message":"PRIVATE_CANARY"}}"#.utf8)
    static var checks = 0

    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw Failure(message: message) }
    }
    static func json(_ usage: String?) -> Data {
        Data((#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]"# +
              (usage.map { ",\"usage\":" + $0 } ?? "") + "}").utf8)
    }
    static func event(_ usage: String) -> String { "data: {\"choices\":[],\"usage\":" + usage + "}\n\n" }
    static func sse(_ text: String) -> Scenario { .init(mime: "text/event-stream", chunks: [Data(text.utf8)]) }
    static func body(_ request: URLRequest?) throws -> Data {
        guard let request else { throw Failure(message: "missing intercepted request") }
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw Failure(message: "missing request body") }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0, data.count + count <= 64 * 1024 else { throw Failure(message: "invalid request body") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    static func object(_ request: URLRequest?) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: body(request)) as? [String: Any] else {
            throw Failure(message: "invalid request JSON")
        }
        return value
    }
    static func asksUsage(_ request: URLRequest?) throws -> Bool {
        try (object(request)["stream_options"] as? [String: Bool]) == ["include_usage": true]
    }
    static func same(_ error: Error, _ expected: Error) -> Bool {
        if let a = error as? HTTPStreamFallbackError, let b = expected as? HTTPStreamFallbackError { return a == b }
        if let a = error as? HTTPChatModelError, let b = expected as? HTTPChatModelError { return a == b }
        return false
    }
    /// Synchronous scopes: only the synchronous withValue applies, on any compiler.
    static func within<T>(_ tally: ModelUsageTally, _ operation: () throws -> T) rethrows -> T {
        try ModelUsageScope.$tally.withValue(tally, operation: operation)
    }
    static func unmetered<T>(_ operation: () throws -> T) rethrows -> T {
        try ModelUsageScope.$metered.withValue(false, operation: operation)
    }
    static func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        throw Failure(message: "fixture timed out")
    }

    static func main() async {
        do {
            try requestBodies()
            try await usageValuesAndScope()
            try await transport()
            print("PASS model usage: \(checks) assertions; intercepted HTTP only")
        } catch let failure as Failure {
            print("FAIL: \(failure.message)"); exit(1)
        } catch {
            print("FAIL: unexpected \(type(of: error))"); exit(1)
        }
    }

    /// Only a stream asks for usage, and nothing else in the body changes.
    /// JSONEncoder's key order varies between runs, so "unchanged" means the
    /// same JSON object, the same length and no stream_options bytes at all.
    static func requestBodies() throws {
        let option = #","stream_options":{"include_usage":true}"#.utf8.count
        func dictionary(_ data: Data?) throws -> NSMutableDictionary {
            guard let data, let value = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
                throw Failure(message: "invalid body JSON")
            }
            return NSMutableDictionary(dictionary: value)
        }
        func legacy(_ stream: Bool) throws -> Data {
            try JSONEncoder().encode(LegacyBody(model: "fixture", messages: [.init(role: "user", content: "fixture")],
                                                stream: stream, max_tokens: 1024))
        }
        func encoded(stream: Bool, usage: Bool) throws -> Data {
            try OpenAIChatRequest.body(model: "fixture", messages: messages, stream: stream, maxOutputTokens: 1024,
                                       vision: .unknown, includeUsage: usage)
        }
        func unchanged(_ data: Data?, _ expected: Data) throws -> Bool {
            try dictionary(data) == dictionary(expected) && data?.count == expected.count &&
                !String(decoding: data ?? Data(), as: UTF8.self).contains("stream_options")
        }
        func asking(_ data: Data?, _ expected: Data) throws -> Bool {
            let object = try dictionary(data)
            guard object["stream_options"] as? NSDictionary == ["include_usage": true] else { return false }
            object.removeObject(forKey: "stream_options")
            return try object == dictionary(expected) && data?.count == expected.count + option
        }
        try check(try unchanged(encoded(stream: true, usage: false), legacy(true)) &&
                  unchanged(encoded(stream: false, usage: false), legacy(false)), "without usage the body is unchanged")
        try check(try unchanged(encoded(stream: false, usage: true), legacy(false)), "a non-stream request never asks for usage")
        try check(try asking(encoded(stream: true, usage: true), legacy(true)), "a stream adds only stream_options.include_usage")
        let configuration = ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture", vision: .supported)
        try check(try unchanged(HTTPChatModelClient.request(messages: messages, configuration: configuration, apiKey: key,
                                                            stream: true).httpBody, legacy(true)),
                  "the request builder defaults to the legacy body")
        let attachment = try ModelAttachment.text(utf8: Data("synthetic attachment".utf8))
        let attached = [ModelMessage(userText: "question", attachment: attachment)]
        let plain = try HTTPChatModelClient.request(messages: attached, configuration: configuration, apiKey: key, stream: true)
        let withUsage = try HTTPChatModelClient.request(messages: attached, configuration: configuration, apiKey: key,
                                                        stream: true, includeUsage: true)
        let wire = try object(withUsage)["messages"] as? [[String: Any]]
        try check(try asking(withUsage.httpBody, body(plain)) && (wire?.first?["content"] as? [Any])?.count == 2,
                  "the usage option keeps the attachment wire shape")
    }

    static func usageValuesAndScope() async throws {
        try check(ModelTokenUsage() == nil && ModelTokenUsage(inputTokens: -1) == nil &&
                  ModelTokenUsage(inputTokens: 3, cachedInputTokens: 4) == nil &&
                  ModelTokenUsage(outputTokens: 1, reasoningTokens: 2) == nil, "invalid reports are not usage")
        try check(ModelTokenUsage(inputTokens: 0)?.isReported == true && ModelTokenUsage(totalTokens: 19)?.isReported == false,
                  "only an input count makes a report")
        let tally = ModelUsageTally()
        tally.record(ModelTokenUsage(inputTokens: 10, cachedInputTokens: 2))
        tally.record(ModelTokenUsage(totalTokens: 19))
        tally.record(nil)
        tally.record(ModelTokenUsage(inputTokens: .max, outputTokens: .max))
        let sealed = tally.seal()
        tally.record(ModelTokenUsage(inputTokens: 1, outputTokens: 1))
        try check(sealed == Snapshot(replies: 4, unreported: 2, input: .max, output: .max, cached: 2),
                  "missing output is 0, total alone is unreported, sums saturate")
        try check(tally.seal() == sealed, "a sealed tally ignores later replies")

        // Child tasks inherit the scope; detached tasks and unmetered calls do not count.
        let scoped = ModelUsageTally(), one = ModelTokenUsage(inputTokens: 1, outputTokens: 1)
        ModelUsageScope.reply(one)
        await ModelUsageScope.$tally.withValue(scoped) {
            ModelUsageScope.reply(one)
            await Task { ModelUsageScope.reply(one) }.value
            async let child: Void = ModelUsageScope.reply(one)
            await child
            await Task.detached { ModelUsageScope.reply(one) }.value
            unmetered { ModelUsageScope.reply(one) }
        }
        try check(scoped.seal() == Snapshot(replies: 3, input: 3, output: 3), "the scope follows child tasks only")

        // The parser keeps the last usable report; odd usage values still parse.
        var parser = ChatSSEParser()
        for byte in Data((text + event("5") + stop + event(all) + event("{}") + done).utf8) { _ = try parser.append(byte) }
        try parser.finish()
        try check(parser.usage == allUsage, "SSE keeps the last usable report")
    }

    static func transport() async throws {
        let session = ModelProtocolFixture.session()
        defer { session.invalidateAndCancel() }
        let log = EventLog()
        let client = HTTPChatModelClient(session: session, usageSink: log)
        var expectedEvents = 0
        func lastEvent() throws -> ModelUsageEvent {
            expectedEvents += 1
            let events = log.events
            guard events.count == expectedEvents, let last = events.last else { throw Failure(message: "one event per request") }
            return last
        }
        var urls: [ObjectIdentifier: URL] = [:]
        func url(_ fixture: Scenario) -> URL {
            if let known = urls[ObjectIdentifier(fixture)] { return known }
            let registered = ModelProtocolFixture.register(fixture)
            urls[ObjectIdentifier(fixture)] = registered
            return registered
        }
        defer { urls.values.forEach(ModelProtocolFixture.remove) }

        // Non-stream usage.
        func complete(_ usage: String?, purpose: ModelUsagePurpose = .other) async throws -> (ModelUsageEvent, Snapshot) {
            let fixture = Scenario(chunks: [json(usage)])
            let tally = ModelUsageTally()
            let reply = try await ModelUsageScope.$tally.withValue(tally) {
                try await ModelUsageScope.$purpose.withValue(purpose) {
                    try await client.complete(messages: messages, configuration: .init(baseURL: url(fixture), model: " fixture "), apiKey: key)
                }
            }
            try check(reply == "ok" && fixture.requestCount == 1, "complete sends once")
            try check(try object(fixture.lastRequest)["stream_options"] == nil, "complete never asks for usage")
            let event = try lastEvent()
            try check(event.baseURL == url(fixture) && event.model == "fixture" && event.purpose == purpose && event.dispatched,
                      "the event names the endpoint, model and purpose")
            return (event, tally.seal())
        }
        let full = try await complete(all, purpose: .memory)
        try check(full.0.usage == allUsage && full.1 == allCounted, "complete keeps every field")
        for absent in [nil, "null", "\"7\"", #"{"prompt_tokens":-1,"completion_tokens":true,"total_tokens":"7"}"#] {
            let result = try await complete(absent)
            try check(result.0.usage == nil && result.1 == Snapshot(replies: 1, unreported: 1), "missing or malformed usage is unknown, not zero")
        }
        let totalOnly = try await complete(#"{"total_tokens":19}"#)
        try check(totalOnly.0.usage == ModelTokenUsage(totalTokens: 19) && totalOnly.1 == Snapshot(replies: 1, unreported: 1),
                  "total_tokens alone is unreported")
        let noOutput = try await complete(#"{"prompt_tokens":10}"#)
        try check(noOutput.0.usage?.outputTokens == nil && noOutput.1 == Snapshot(replies: 1, input: 10), "a missing output counts 0")
        let noInput = try await complete(#"{"completion_tokens":0}"#)
        try check(noInput.0.usage?.outputTokens == 0 && noInput.0.usage?.inputTokens == nil && noInput.1 == Snapshot(replies: 1, unreported: 1),
                  "an explicit zero differs from unreported, and output alone is unreported")
        let hitMiss = try await complete(#"{"prompt_cache_hit_tokens":2,"prompt_cache_miss_tokens":5}"#)
        try check(hitMiss.0.usage?.inputTokens == 7 && hitMiss.0.usage?.cachedInputTokens == 2 &&
                  hitMiss.1 == Snapshot(replies: 1, input: 7, cached: 2), "cache hit plus miss is the input")
        let larger = try await complete(#"{"prompt_tokens":10,"prompt_cache_hit_tokens":6,"prompt_tokens_details":{"cached_tokens":1}}"#)
        try check(larger.0.usage?.cachedInputTokens == 6, "the larger cache-hit field counts, as on Android")
        let inconsistent = try await complete(#"{"prompt_tokens":3,"completion_tokens":2,"prompt_tokens_details":{"cached_tokens":9},"completion_tokens_details":{"reasoning_tokens":8}}"#)
        try check(inconsistent.0.usage?.cachedInputTokens == nil && inconsistent.0.usage?.reasoningTokens == nil &&
                  inconsistent.1 == Snapshot(replies: 1, input: 3, output: 2), "cached above input and reasoning above output are unknown")
        let overflow = try await complete(#"{"prompt_cache_hit_tokens":9223372036854775807,"prompt_cache_miss_tokens":1}"#)
        try check(overflow.0.usage?.inputTokens == nil && overflow.1 == Snapshot(replies: 1, unreported: 1), "cache addition cannot overflow")

        // Stream usage: asked for, parsed, and recorded before the stream ends.
        func stream(_ fixture: Scenario, model: String = "fixture",
                    purpose: ModelUsagePurpose = .other) async throws -> (String, ModelUsageEvent, Snapshot) {
            let tally = ModelUsageTally()
            var result = ""
            try await ModelUsageScope.$tally.withValue(tally) {
                try await ModelUsageScope.$purpose.withValue(purpose) {
                    for try await delta in client.stream(messages: messages, configuration: .init(baseURL: url(fixture), model: model),
                                                         apiKey: key) { result += delta }
                }
            }
            return (result, try lastEvent(), tally.seal())
        }
        let final = sse(text + stop + event(all) + done)
        let streamed = try await stream(final, purpose: .chat)
        try check(streamed.0 == "ok" && streamed.1.usage == allUsage && streamed.1.purpose == .chat && streamed.2 == allCounted,
                  "SSE usage in its own final event")
        try check(final.requestCount == 1 && (try object(final.lastRequest))["stream"] as? Bool == true &&
                  (try asksUsage(final.lastRequest)), "a stream asks for usage by default")
        let inStop = try await stream(sse(text + #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":1}}"# + "\n\n" + done))
        try check(inStop.2 == Snapshot(replies: 1, input: 3, output: 1), "usage in the finishing chunk")
        let running = try await stream(sse(#"data: {"choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":null}],"usage":{"prompt_tokens":3,"completion_tokens":1}}"# + "\n\n" + stop + event(all) + done))
        try check(running.2 == allCounted, "the last report wins")
        let unreported = try await stream(sse(text + stop + done))
        try check(unreported.0 == "ok" && unreported.1.usage == nil && unreported.1.dispatched &&
                  unreported.2 == Snapshot(replies: 1, unreported: 1), "a successful stream without usage is unreported")
        let jsonReply = Scenario(chunks: [json(all)])
        let jsonStreamed = try await stream(jsonReply)
        try check(jsonStreamed.0 == "ok" && jsonReply.requestCount == 1 && jsonStreamed.2 == allCounted,
                  "a JSON reply to a stream keeps its usage without a second request")

        // A refused usage option: its own error, remembered, never resent here.
        func refused(_ fixture: Scenario, model: String = "fixture") async throws -> Error {
            let tally = ModelUsageTally()
            do {
                try await ModelUsageScope.$tally.withValue(tally) {
                    for try await _ in client.stream(messages: messages, configuration: .init(baseURL: url(fixture), model: model),
                                                     apiKey: key) {}
                }
            } catch {
                let event = try lastEvent()
                try check(event.usage == nil && event.dispatched && tally.seal() == Snapshot(), "a failed request is never a reply")
                return error
            }
            throw Failure(message: "refused stream completed")
        }
        let sseReply = Scenario.Reply(status: 200, mime: "text/event-stream", chunks: [Data((text + stop + event(all) + done).utf8)])
        let refusing = Scenario(status: 400, chunks: [refusal], followUp: sseReply)
        let error = try await refused(refusing)
        try check(same(error, HTTPStreamFallbackError.usageOptionUnsupported(400)) && !error.localizedDescription.contains("PRIVATE_CANARY"),
                  "a refused option is its own content-free error")
        try check(refusing.requestCount == 1 && (try asksUsage(refusing.lastRequest)), "the client never resends")
        let resent = try await stream(refusing)
        try check(resent.0 == "ok" && refusing.requestCount == 2 && (try object(refusing.lastRequest))["stream_options"] == nil &&
                  resent.2 == allCounted, "the host's resend leaves the option out and still reads usage")
        _ = try await stream(refusing, model: "other-model")
        try check(refusing.requestCount == 3 && (try asksUsage(refusing.lastRequest)), "the refusal is remembered per endpoint and model")
        for (status, body) in [(400, #"{"error":{"code":null,"param":"stream_options.include_usage"}}"#),
                               (422, #"{"detail":[{"type":"extra_forbidden","loc":["body","stream_options"],"msg":"Extra inputs are not permitted"}]}"#),
                               (415, #"{"error":{"message":"Unrecognized request argument supplied: stream_options","param":null}}"#)] {
            let fixture = Scenario(status: status, chunks: [Data(body.utf8)])
            let error = try await refused(fixture)
            try check(same(error, HTTPStreamFallbackError.usageOptionUnsupported(status)) && fixture.requestCount == 1,
                      "an error naming stream_options is a refused option (\(status))")
        }
        let twice = Scenario(status: 400, chunks: [refusal], followUp: .init(status: 400, mime: "application/json", chunks: [refusal]))
        _ = try await refused(twice)
        let again = try await refused(twice)
        try check(same(again, HTTPChatModelError.httpStatus(400)) && twice.requestCount == 2 &&
                  (try object(twice.lastRequest))["stream_options"] == nil, "once declined, the same error is an ordinary failure")
        let others: [(Int, String, Error)] = [
            (400, #"{"error":{"code":"unsupported_parameter","param":"stream"}}"#, HTTPStreamFallbackError.explicitUnsupported(400)),
            (400, #"{"error":{"code":"invalid_request","param":"messages"}}"#, HTTPChatModelError.httpStatus(400)),
            (429, #"{"error":{"param":"stream_options"}}"#, HTTPChatModelError.httpStatus(429)),
            (400, #"{"error":{"param":"stream_options"}}"# + String(repeating: " ", count: 2048), HTTPChatModelError.httpStatus(400))
        ]
        for (status, body, expected) in others {
            let fixture = Scenario(status: status, chunks: [Data(body.utf8)], followUp: sseReply)
            let error = try await refused(fixture)
            try check(same(error, expected), "other refusals keep their meaning (\(status))")
            _ = try await stream(fixture)
            try check(fixture.requestCount == 2 && (try asksUsage(fixture.lastRequest)), "and they are not remembered (\(status))")
        }

        // Cut, failed, timed-out and cancelled requests never reach a tally.
        func failure(_ operation: () async throws -> Void) async throws -> (Error, Snapshot) {
            let tally = ModelUsageTally()
            do { try await ModelUsageScope.$tally.withValue(tally) { try await operation() } }
            catch { return (error, tally.seal()) }
            throw Failure(message: "failure completed")
        }
        let truncated = sse(text + stop + event(all))
        let cut = try await failure {
            for try await _ in client.stream(messages: messages, configuration: .init(baseURL: url(truncated), model: "fixture"), apiKey: key) {}
        }
        var last = try lastEvent()
        try check(same(cut.0, HTTPChatModelError.incompleteResponse) && cut.1 == Snapshot() && last.usage == nil && last.dispatched,
                  "usage before a missing DONE is not recorded; the sink sees the cut request")
        let server = Scenario(status: 500, chunks: [json(all)])
        let failed = try await failure {
            _ = try await client.complete(messages: messages, configuration: .init(baseURL: url(server), model: "fixture"), apiKey: key)
        }
        last = try lastEvent()
        try check(same(failed.0, HTTPChatModelError.httpStatus(500)) && failed.1 == Snapshot() && last.usage == nil && last.dispatched,
                  "a failed complete goes only to the sink")
        let invalid = try await failure {
            for try await _ in client.stream(messages: messages, configuration: .init(baseURL: url(server), model: " "), apiKey: key) {}
        }
        last = try lastEvent()
        try check(same(invalid.0, HTTPChatModelError.invalidConfiguration) && !last.dispatched && server.requestCount == 1,
                  "a request never handed to URLSession is not dispatched")
        let slow = Scenario(mime: "text/event-stream", chunks: [Data((text + stop + event(all)).utf8)], holdAfterBody: true)
        defer { slow.releaseHeldResponses() }
        let timed = HTTPChatModelClient(session: session, timeoutNanoseconds: 50_000_000, usageSink: log)
        let timeout = try await failure {
            for try await _ in timed.stream(messages: messages, configuration: .init(baseURL: url(slow), model: "fixture"), apiKey: key) {}
        }
        last = try lastEvent()
        try check(same(timeout.0, HTTPChatModelError.timedOut) && timeout.1 == Snapshot() && last.usage == nil, "a timed-out stream is not recorded")
        let held = Scenario(mime: "text/event-stream", chunks: [Data((text + stop + event(all)).utf8)], holdAfterBody: true)
        defer { held.releaseHeldResponses() }
        let heldTally = ModelUsageTally(), seen = Fragments(), heldURL = url(held)
        let work = within(heldTally) {
            Task {
                for try await fragment in client.stream(messages: messages, configuration: .init(baseURL: heldURL, model: "fixture"), apiKey: key) {
                    await seen.add(fragment)
                }
                try Task.checkCancellation()
            }
        }
        try await wait { await seen.snapshot() == ["ok"] && held.bodyDelivered }
        work.cancel()
        do { try await work.value; throw Failure(message: "cancelled stream completed") } catch is CancellationError {}
        try await wait { log.events.count == expectedEvents + 1 }
        last = try lastEvent()
        try check(heldTally.seal() == Snapshot() && last.usage == nil && held.requestCount == 1, "a cancelled stream is not recorded")
        let heldComplete = Scenario(chunks: [json(all)], holdAfterBody: true)
        defer { heldComplete.releaseHeldResponses() }
        let completeTally = ModelUsageTally(), heldCompleteURL = url(heldComplete)
        let pending = within(completeTally) {
            Task { try await client.complete(messages: messages, configuration: .init(baseURL: heldCompleteURL, model: "fixture"), apiKey: key) }
        }
        try await wait { heldComplete.bodyDelivered }
        pending.cancel()
        do { _ = try await pending.value; throw Failure(message: "cancelled complete returned") } catch is CancellationError {}
        last = try lastEvent()
        try check(completeTally.seal() == Snapshot() && last.usage == nil, "a cancelled complete is not recorded")

        // Unmetered requests, including the connection test, reach neither.
        let quiet = Scenario(chunks: [json(all)])
        let quietTally = ModelUsageTally(), quietURL = url(quiet)
        _ = try await ModelUsageScope.$tally.withValue(quietTally) {
            try await ModelUsageScope.$metered.withValue(false) {
                try await client.complete(messages: messages, configuration: .init(baseURL: quietURL, model: "fixture"), apiKey: key)
            }
        }
        let connection = ModelConnectionCheck(timeoutNanoseconds: 2_000_000_000)
        within(quietTally) {
            connection.start(client: client, configuration: .init(baseURL: quietURL, model: "fixture"), apiKey: key)
        }
        try await wait { connection.state != .testing }
        try check(connection.state == .passed && quiet.requestCount == 2, "the connection test still runs")
        try check(quietTally.seal() == Snapshot() && log.events.count == expectedEvents, "unmetered requests and connection tests are not usage")
    }
}
