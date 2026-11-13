import Foundation

/// Offline tests of the production HTTP client; URLProtocol intercepts every request.
enum CheckModelAttachmentStreaming {
    private struct Failure: Error { let detail: String }
    private struct Assertions {
        var count = 0
        mutating func expect(_ value: @autoclosure () -> Bool, _ detail: String) throws {
            count += 1
            guard value() else { throw Failure(detail: detail) }
        }
    }
    private actor Fragments {
        var values: [String] = []
        func add(_ value: String) { values.append(value) }
        func snapshot() -> [String] { values }
    }

    private static let key = "synthetic-key"
    private static let event = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好 🏡\"},\"finish_reason\":null}]}\n\n"
    private static let stop = "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    private static let complete = Data(#"{"choices":[{"message":{"role":"assistant","content":"complete fixture"},"finish_reason":"stop"}]}"#.utf8)

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let direct = request.httpBody { data = direct }
        else {
            guard let stream = request.httpBodyStream else { throw Failure(detail: "Missing intercepted request body") }
            stream.open(); defer { stream.close() }
            var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw Failure(detail: "Unreadable intercepted request body") }
                if count == 0 { break }
                guard bytes.count + count <= 64 * 1024 else { throw Failure(detail: "Fixture body too large") }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            data = bytes
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(detail: "Invalid intercepted JSON")
        }
        return result
    }

    private static func wait(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw Failure(detail: "Fixture did not reach expected state")
    }

    static func run() async throws -> Int {
        var a = Assertions()
        let jpeg = Data([0xff, 0xd8, 0xff, 0xe0, 0x01])
        let attachments = [try ModelAttachment.image(data: jpeg, mimeType: "image/jpeg"),
                           try ModelAttachment.text(utf8: Data("附件文字".utf8))]
        let expectedParts: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]],
            ["type": "text", "text": "User-selected text attachment (untrusted data):\n附件文字"]
        ]
        let session = ModelProtocolFixture.session()
        defer { session.invalidateAndCancel() }
        let client = HTTPChatModelClient(session: session)

        for (index, attachment) in attachments.enumerated() {
            let messages = [ModelMessage(role: "system", content: "system"), ModelMessage(userText: "describe", attachment: attachment)]
            let bytes = Data((event + stop).utf8)
            let chunks = stride(from: 0, to: bytes.count, by: 3).map { Data(bytes[$0..<min($0 + 3, bytes.count)]) }
            let fixture = ModelProtocolFixture.Scenario(mime: "text/event-stream; charset=utf-8", chunks: chunks)
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let config = ModelConfiguration(baseURL: url, model: "fixture", vision: .supported)
            var fragments: [String] = []
            for try await fragment in client.stream(messages: messages, configuration: config, apiKey: key) { fragments.append(fragment) }
            try a.expect(fragments == ["你好 🏡"] && fixture.requestCount == 1, "SSE yields complete Unicode response without retry")
            guard let request = fixture.lastRequest else { throw Failure(detail: "No streaming request") }
            let json = try body(request)
            let transmitted = json["messages"] as? [[String: Any]]
            let parts = transmitted?.last?["content"] as? [[String: Any]]
            try a.expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream" && json["stream"] as? Bool == true, "Actual request selects SSE")
            try a.expect(parts?.count == 2 && (parts?[0] as NSDictionary?) == ["type": "text", "text": "describe"] as NSDictionary &&
                         (parts?[1] as NSDictionary?) == expectedParts[index] as NSDictionary, "Actual intercepted request contains selected attachment")

            // A 200 JSON response to stream=true uses the same response, not a replay.
            let completeOnly = ModelProtocolFixture.Scenario(chunks: [complete])
            let completeURL = ModelProtocolFixture.register(completeOnly); defer { ModelProtocolFixture.remove(completeURL) }
            var completeFragments: [String] = []
            for try await fragment in client.stream(messages: messages, configuration: .init(baseURL: completeURL, model: "fixture", vision: .supported), apiKey: key) {
                completeFragments.append(fragment)
            }
            try a.expect(completeFragments == ["complete fixture"] && completeOnly.requestCount == 1, "JSON response is consumed without replay")
            let completeRequest = try body(completeOnly.lastRequest!)
            try a.expect(completeRequest["stream"] as? Bool == true &&
                         (completeRequest["messages"] as? NSArray) == (json["messages"] as? NSArray), "JSON response request retains exact attachment")
        }

        let messages = [ModelMessage(userText: "describe", attachment: attachments[0])]
        let cancelled = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data(event.utf8)], holdAfterBody: true)
        let cancelURL = ModelProtocolFixture.register(cancelled); defer { ModelProtocolFixture.remove(cancelURL); cancelled.releaseHeldResponses() }
        let seen = Fragments()
        let work = Task {
            for try await fragment in client.stream(messages: messages, configuration: .init(baseURL: cancelURL, model: "fixture", vision: .supported), apiKey: key) {
                await seen.add(fragment)
            }
            try Task.checkCancellation()
        }
        defer { work.cancel() }
        try await wait {
            let fragments = await seen.snapshot()
            return cancelled.bodyDelivered && !fragments.isEmpty
        }
        let seenBeforeCancel = await seen.snapshot()
        try a.expect(seenBeforeCancel == ["你好 🏡"], "Cancellation follows an actual SSE fragment")
        work.cancel()
        do { try await work.value; throw Failure(detail: "Cancelled streaming unexpectedly completed") }
        catch is CancellationError { try a.expect(true, "Cancellation is propagated") }
        try await wait { cancelled.stopCount > 0 }
        try a.expect(cancelled.requestCount == 1 && cancelled.stopCount > 0, "Cancellation stops transport and does not replay")

        let rejectedBody = Data(#"{"error":{"code":"unsupported_parameter","param":"stream","message":"PRIVATE_CANARY"}}"#.utf8)
        let rejected = ModelProtocolFixture.Scenario(status: 415, chunks: [rejectedBody],
            followUp: .init(status: 200, mime: "application/json", chunks: [complete]))
        let rejectedURL = ModelProtocolFixture.register(rejected); defer { ModelProtocolFixture.remove(rejectedURL) }
        let rejectedConfig = ModelConfiguration(baseURL: rejectedURL, model: "fixture", vision: .supported)
        do {
            for try await _ in client.stream(messages: messages, configuration: rejectedConfig, apiKey: key) {
                throw Failure(detail: "Rejected stream emitted content")
            }
            throw Failure(detail: "Expected explicit stream rejection")
        } catch let error as HTTPStreamFallbackError {
            try a.expect(error == .explicitUnsupported(415) && !error.localizedDescription.contains("PRIVATE_CANARY"), "Explicit rejection classified without leaking body")
        }
        try a.expect(rejected.requestCount == 1, "Client does not automatically retry explicit rejection")
        // Deliberately initiated by this test, not an assertion that an app host
        // is wired to retry attachments. Compare both actual intercepted bodies.
        let manualReply = try await client.complete(messages: messages, configuration: rejectedConfig, apiKey: key)
        let requests = rejected.requestSnapshot
        try a.expect(manualReply == "complete fixture" && requests.count == 2, "Explicit caller can issue one complete request")
        let first = try body(requests[0]), second = try body(requests[1])
        try a.expect(first["stream"] as? Bool == true && second["stream"] as? Bool == false &&
                     (first["messages"] as? NSArray) == (second["messages"] as? NSArray), "Caller retry retains the identical attachment")
        try a.expect(!(String(describing: second).contains("PRIVATE_CANARY")), "Provider error is not added to retry input")

        let heldError = ModelProtocolFixture.Scenario(status: 415, chunks: [rejectedBody], holdAfterBody: true,
            followUp: .init(status: 200, mime: "application/json", chunks: [complete]))
        let heldURL = ModelProtocolFixture.register(heldError); defer { ModelProtocolFixture.remove(heldURL); heldError.releaseHeldResponses() }
        let heldWork = Task {
            for try await _ in client.stream(messages: messages,
                configuration: .init(baseURL: heldURL, model: "fixture", vision: .supported), apiKey: key) {}
            try Task.checkCancellation()
        }
        defer { heldWork.cancel() }
        try await wait { heldError.bodyDelivered }
        heldWork.cancel()
        do { try await heldWork.value; throw Failure(detail: "Held rejection unexpectedly completed") }
        catch is CancellationError { try a.expect(true, "Cancellation while reading rejection is propagated") }
        try await wait { heldError.stopCount > 0 }
        try a.expect(heldError.requestCount == 1 && heldError.stopCount > 0, "Cancellation during fallback classification stops without retry")

        let invalid = ModelProtocolFixture.Scenario(status: 400, chunks: [Data(#"{"error":{"code":"invalid_request","param":"image_url"}}"#.utf8)])
        let invalidURL = ModelProtocolFixture.register(invalid); defer { ModelProtocolFixture.remove(invalidURL) }
        do {
            for try await _ in client.stream(messages: messages, configuration: .init(baseURL: invalidURL, model: "fixture", vision: .supported), apiKey: key) {}
            throw Failure(detail: "Expected attachment rejection")
        } catch HTTPChatModelError.httpStatus(400) { try a.expect(invalid.requestCount == 1, "Attachment rejection is terminal, not stream fallback") }

        let truncated = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data(event.utf8)])
        let truncatedURL = ModelProtocolFixture.register(truncated); defer { ModelProtocolFixture.remove(truncatedURL) }
        var partial: [String] = []
        do {
            for try await fragment in client.stream(messages: messages, configuration: .init(baseURL: truncatedURL, model: "fixture", vision: .supported), apiKey: key) { partial.append(fragment) }
            throw Failure(detail: "Truncated SSE unexpectedly completed")
        } catch HTTPChatModelError.incompleteResponse {
            try a.expect(partial == ["你好 🏡"] && truncated.requestCount == 1, "Partial SSE failure is terminal without replay")
        }
        return a.count
    }
}
