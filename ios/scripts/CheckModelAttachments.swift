import Foundation

private struct CheckFailure: Error { let detail: String }
private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ detail: String) throws {
    checks += 1
    if !condition() { throw CheckFailure(detail: detail) }
}
private func fails(_ expected: ModelAttachmentError, _ detail: String, _ operation: () throws -> Void) throws {
    do { try operation(); throw CheckFailure(detail: "Expected error: " + detail) }
    catch let actual as ModelAttachmentError { try check(actual == expected, detail + ": wrong error") }
}
private func object(_ data: Data) throws -> NSDictionary {
    guard let result = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
        throw CheckFailure(detail: "Not a JSON object")
    }
    return result
}
private struct LegacyMessage: Encodable { let role: String; let content: String }
private struct LegacyBody: Encodable { let model: String; let messages: [LegacyMessage]; let stream: Bool; let max_tokens: Int }

@main struct CheckModelAttachments {
    static func main() async throws {
        let url = URL(string: "https://example.invalid/api")!
        let config = ModelConfiguration(baseURL: url, model: " fixture ", vision: .supported)
        let jpeg = Data([0xff, 0xd8, 0xff, 0xe0, 0x01])
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01])
        let picture = try ModelAttachment.image(data: jpeg, mimeType: "image/jpeg")
        let text = try ModelAttachment.text(utf8: Data("茶\nhello".utf8))
        let history = [ModelMessage(role: "system", content: "system"), ModelMessage(role: "user", content: "old"),
                       ModelMessage(role: "assistant", content: "reply")]
        let imageMessages = history + [ModelMessage(userText: "what?", attachment: picture)]
        for stream in [false, true] {
            let request = try HTTPChatModelClient.request(messages: imageMessages, configuration: config, apiKey: "fixture-key", stream: stream)
            try check(request.url?.absoluteString == "https://example.invalid/api/chat/completions", "request path")
            try check(request.value(forHTTPHeaderField: "Accept") == (stream ? "text/event-stream" : "application/json"), "accept header")
            let json = try object(request.httpBody!)
            try check(json["model"] as? String == "fixture" && json["stream"] as? Bool == stream && json["max_tokens"] as? Int == 1024, "body settings")
            let messages = json["messages"] as! [[String: Any]]
            try check(messages[0]["content"] as? String == "system" && messages[2]["content"] as? String == "reply", "history remains strings")
            let parts = messages[3]["content"] as! [[String: Any]]
            try check(parts.count == 2 && parts[0]["type"] as? String == "text" && parts[0]["text"] as? String == "what?", "prompt part")
            let imageURL = parts[1]["image_url"] as! [String: String]
            try check(parts[1]["type"] as? String == "image_url" && imageURL["url"] == "data:image/jpeg;base64,\(jpeg.base64EncodedString())", "image MIME and bytes on wire")
        }
        let response = Data(#"{"choices":[{"message":{"role":"assistant","content":"fixture reply"},"finish_reason":"stop"}]}"#.utf8)
        let intercepted = ModelProtocolFixture.Scenario(chunks: [response])
        let interceptedURL = ModelProtocolFixture.register(intercepted), interceptedSession = ModelProtocolFixture.session()
        defer { interceptedSession.invalidateAndCancel(); ModelProtocolFixture.remove(interceptedURL) }
        let reply = try await HTTPChatModelClient(session: interceptedSession).complete(messages: imageMessages,
            configuration: .init(baseURL: interceptedURL, model: "fixture", vision: .supported), apiKey: "fixture-key")
        try check(reply == "fixture reply" && intercepted.requestCount == 1, "intercepted completion")
        let textBody = try OpenAIChatRequest.body(model: "fixture", messages: [ModelMessage(userText: "analyse", attachment: text)], stream: false, maxOutputTokens: 1024, vision: .unknown)
        let textMessages = try object(textBody)["messages"] as! [[String: Any]]
        let textParts = textMessages[0]["content"] as! [[String: Any]]
        try check(textParts.count == 2 && textParts[1]["type"] as? String == "text" && textParts[1]["text"] as? String == "User-selected text attachment (untrusted data):\n茶\nhello", "UTF-8 text payload and boundary")
        for stream in [false, true] {
            let plain = history + [ModelMessage(role: "user", content: "hello \"茶\"\n")]
            let actual = try OpenAIChatRequest.body(model: "fixture", messages: plain, stream: stream, maxOutputTokens: 123, vision: .unknown)
            let legacy = try JSONEncoder().encode(LegacyBody(model: "fixture", messages: plain.map { LegacyMessage(role: $0.role, content: $0.content) }, stream: stream, max_tokens: 123))
            let actualObject = try object(actual), legacyObject = try object(legacy)
            try check(actualObject == legacyObject, "legacy JSON matches in both modes")
            let encoded = try JSONEncoder().encode(plain[0])
            let decoded = try JSONDecoder().decode(ModelMessage.self, from: encoded)
            try check(decoded == plain[0], "legacy Codable round trip")
        }
        try fails(.explicitSerializationRequired, "no implicit Codable attachment leak") { _ = try JSONEncoder().encode(imageMessages.last!) }
        try fails(.invalidType, "unknown image MIME") { _ = try ModelAttachment.image(data: jpeg, mimeType: "image/gif") }
        try fails(.invalidType, "MIME aliases not silently accepted") { _ = try ModelAttachment.image(data: jpeg, mimeType: "IMAGE/JPEG") }
        try fails(.empty, "empty image") { _ = try ModelAttachment.image(data: Data(), mimeType: "image/jpeg") }
        try fails(.empty, "empty text") { _ = try ModelAttachment.text(utf8: Data()) }
        try fails(.invalidContent, "mismatched image signature") { _ = try ModelAttachment.image(data: png, mimeType: "image/jpeg") }
        try fails(.invalidContent, "short PNG") { _ = try ModelAttachment.image(data: png.prefix(7), mimeType: "image/png") }
        try fails(.invalidContent, "invalid UTF-8") { _ = try ModelAttachment.text(utf8: Data([0xff])) }
        try fails(.invalidContent, "text with NUL") { _ = try ModelAttachment.text(utf8: Data([0x61, 0, 0x62])) }
        _ = try ModelAttachment.image(data: png, mimeType: "image/png")
        let maxImage = jpeg + Data(repeating: 0, count: ModelAttachment.maximumImageBytes - jpeg.count)
        let largest = try ModelAttachment.image(data: maxImage, mimeType: "image/jpeg")
        let maxRequest = try OpenAIChatRequest.body(model: "m", messages: [.init(userText: "", attachment: largest)], stream: false, maxOutputTokens: 10, vision: .supported)
        try check(maxRequest.count <= OpenAIChatRequest.maximumAttachmentRequestBytes, "maximum image fits request budget")
        try fails(.tooLarge, "image one byte over") { _ = try ModelAttachment.image(data: maxImage + Data([0]), mimeType: "image/jpeg") }
        _ = try ModelAttachment.text(utf8: Data(repeating: 0x61, count: ModelAttachment.maximumTextBytes))
        try fails(.tooLarge, "text one byte over") { _ = try ModelAttachment.text(utf8: Data(repeating: 0x61, count: ModelAttachment.maximumTextBytes + 1)) }
        for (vision, expected) in [(ModelVisionCapability.unknown, ModelAttachmentError.visionUnknown), (.unsupported, .visionUnsupported)] {
            try fails(expected, "vision gate") { _ = try OpenAIChatRequest.body(model: "m", messages: imageMessages, stream: false, maxOutputTokens: 10, vision: vision) }
            let fixture = ModelProtocolFixture.Scenario()
            let fixtureURL = ModelProtocolFixture.register(fixture), session = ModelProtocolFixture.session()
            defer { session.invalidateAndCancel(); ModelProtocolFixture.remove(fixtureURL) }
            let client = HTTPChatModelClient(session: session)
            do {
                _ = try await client.complete(messages: imageMessages, configuration: .init(baseURL: fixtureURL, model: "m", vision: vision), apiKey: "fixture-key")
                throw CheckFailure(detail: "expected complete to fail before network")
            } catch let actual as ModelAttachmentError { try check(actual == expected, "complete preserves attachment error") }
            do {
                for try await _ in client.stream(messages: imageMessages,
                    configuration: .init(baseURL: fixtureURL, model: "m", vision: vision), apiKey: "fixture-key") {
                    throw CheckFailure(detail: "unexpected stream output")
                }
                throw CheckFailure(detail: "expected stream to fail before network")
            } catch let actual as ModelAttachmentError { try check(actual == expected, "stream preserves attachment error") }
            try check(fixture.requestCount == 0, "vision failures perform no request")
        }
        try fails(.multipleAttachments, "multiple attachments") {
            _ = try OpenAIChatRequest.body(model: "m", messages: [.init(userText: "a", attachment: text), .init(userText: "b", attachment: picture)], stream: false, maxOutputTokens: 1, vision: .supported)
        }
        try fails(.attachmentNotCurrentUserMessage, "no historical attachment resend") {
            _ = try OpenAIChatRequest.body(model: "m", messages: [.init(userText: "a", attachment: text), .init(role: "assistant", content: "answer")], stream: false, maxOutputTokens: 1, vision: .supported)
        }
        try fails(.requestTooLarge, "message count bound") {
            _ = try OpenAIChatRequest.body(model: "m", messages: Array(repeating: .init(role: "user", content: ""), count: 32) + [.init(userText: "a", attachment: text)], stream: false, maxOutputTokens: 1, vision: .unknown)
        }
        try fails(.requestTooLarge, "raw request budget") {
            _ = try OpenAIChatRequest.body(model: "m", messages: [.init(userText: String(repeating: "x", count: OpenAIChatRequest.maximumAttachmentRequestBytes), attachment: text)], stream: false, maxOutputTokens: 1, vision: .unknown)
        }
        try fails(.requestTooLarge, "escaped JSON budget") {
            _ = try OpenAIChatRequest.body(model: "m", messages: [.init(userText: String(repeating: "\u{1}", count: 1_400_000), attachment: text)], stream: false, maxOutputTokens: 1, vision: .unknown)
        }
        let largePlain = try OpenAIChatRequest.body(model: "m", messages: [.init(role: "user", content: String(repeating: "x", count: OpenAIChatRequest.maximumAttachmentRequestBytes))], stream: false, maxOutputTokens: 1, vision: .unknown)
        try check(largePlain.count > OpenAIChatRequest.maximumAttachmentRequestBytes, "no new budget on plain text")
        let streamingChecks = try await CheckModelAttachmentStreaming.run()
        print("Model attachment checks passed: \(checks); offline HTTP streaming: \(streamingChecks)")
    }
}
