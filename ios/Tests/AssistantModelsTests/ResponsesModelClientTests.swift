import XCTest
@testable import AssistantModels

/// The account sign-ins' Responses client, against local fakes only.
final class ResponsesModelClientTests: XCTestCase {
    private let route = ModelAccountRoute(kind: .chatGPT, providerID: UUID())

    private func configuration(_ base: URL, kind: ModelAccountKind = .chatGPT, vision: ModelVisionCapability = .unknown,
                               maxOutputTokens: Int? = nil) -> ModelConfiguration {
        ModelConfiguration(baseURL: base.appendingPathComponent("v1"), model: " gpt-fixture ", maxOutputTokens: maxOutputTokens,
                           vision: vision, account: ModelAccountRoute(kind: kind, providerID: UUID()))
    }

    private static func event(_ json: String) -> String { "data: " + json + "\n\n" }
    private static let hello = [event(#"{"type":"response.created","response":{}}"#),
                                event(#"{"type":"response.output_text.delta","delta":"Hel"}"#),
                                ": keep-alive\n\n",
                                event(#"{"type":"response.output_text.delta","delta":"lo 🏡"}"#),
                                event(#"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"output_text","text":"Hello 🏡"}]}}"#),
                                event(#"{"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":2},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":1},"total_tokens":15}}}"#)]

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (text: String, error: Error?) {
        var text = ""
        do {
            for try await delta in stream { text += delta }
            return (text, nil)
        } catch {
            return (text, error)
        }
    }

    // MARK: Request bodies

    func testBodyPutsTheSystemPromptInInstructionsAndKeepsPlayFieldsOnly() throws {
        let messages = [ModelMessage(role: "system", content: "Be brief."), ModelMessage(role: "user", content: "Hi"),
                        ModelMessage(role: "assistant", content: "Hello."), ModelMessage(role: "assistant", content: ""),
                        ModelMessage(role: "system", content: "Later rule"), ModelMessage(role: "user", content: "Again")]
        let data = try ResponsesRequest.body(model: "gpt-fixture", messages: messages, vision: .unknown)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["model", "instructions", "input", "store", "stream"],
                       "no tools, temperature, output limit or include")
        XCTAssertEqual(body["instructions"] as? String, "Be brief.")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["role"] as? String }, ["user", "assistant", "developer", "user"],
                       "an empty reply is left out; a later system message is a developer message")
        let reply = try XCTUnwrap((input[1]["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(reply["type"] as? String, "output_text")
        XCTAssertEqual(reply["text"] as? String, "Hello.")
        let ask = try XCTUnwrap((input[0]["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(ask["type"] as? String, "input_text")
        XCTAssertEqual(ask["text"] as? String, "Hi")
    }

    func testImagesGoOnlyToAModelThatSeesThem() throws {
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3])
        let image = try ModelAttachment.image(data: png, mimeType: "image/png", label: "cat.png")
        let file = try ModelAttachment.text(utf8: Data("notes".utf8), label: "a.txt")
        let message = ModelMessage(userText: "What is this?", attachments: [image, file])
        XCTAssertThrowsError(try ResponsesRequest.body(model: "m", messages: [message], vision: .unknown)) {
            XCTAssertEqual($0 as? ModelAttachmentError, .visionUnknown)
        }
        XCTAssertThrowsError(try ResponsesRequest.body(model: "m", messages: [message], vision: .unsupported)) {
            XCTAssertEqual($0 as? ModelAttachmentError, .visionUnsupported)
        }
        let data = try ResponsesRequest.body(model: "m", messages: [message], vision: .supported)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try XCTUnwrap(((body["input"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["type"] as? String }, ["input_text", "input_text", "input_image", "input_text"])
        XCTAssertEqual(parts[2]["image_url"] as? String, "data:image/png;base64," + png.base64EncodedString())
        XCTAssertTrue((parts[3]["text"] as? String)?.hasPrefix("User-selected file \"a.txt\" (untrusted data):") == true)
        XCTAssertThrowsError(try ResponsesRequest.body(model: "m", messages: [ModelMessage(role: "assistant", content: "x"),
                                                                             ModelMessage(userText: "a", attachment: file),
                                                                             ModelMessage(userText: "b", attachment: file)],
                                                       vision: .supported)) {
            XCTAssertEqual($0 as? ModelAttachmentError, .multipleAttachments)
        }
    }

    func testRequestGoesToResponsesWithTheTokenAndNoOutputLimit() throws {
        let configuration = ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1/")!, model: "m", maxOutputTokens: 32,
                                               account: route)
        let request = try ResponsesRequest.urlRequest(configuration: configuration, token: "token-1", body: Data("{}".utf8))
        XCTAssertEqual(request.url?.absoluteString, "https://fixture.invalid/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.timeoutInterval, 120)
        XCTAssertFalse(request.httpShouldHandleCookies)
        for base in ["http://fixture.invalid/v1", "https://user@fixture.invalid/v1", "https://fixture.invalid/v1?x=1"] {
            let bad = ModelConfiguration(baseURL: URL(string: base)!, model: "m", account: route)
            XCTAssertThrowsError(try ResponsesRequest.urlRequest(configuration: bad, token: "t", body: Data()), base)
        }
        XCTAssertThrowsError(try ResponsesRequest.urlRequest(configuration: configuration, token: "bad\ntoken", body: Data()))
        // An account configuration never reaches chat/completions with a key.
        XCTAssertThrowsError(try HTTPChatModelClient.request(messages: [ModelMessage(role: "user", content: "x")],
                                                            configuration: configuration, apiKey: "key", stream: true)) {
            XCTAssertEqual($0 as? HTTPChatModelError, .invalidConfiguration)
        }
    }

    // MARK: The event stream

    private func parse(_ text: String, kind: ModelAccountKind = .chatGPT) -> (deltas: [String], parser: ResponsesEventParser?, error: Error?) {
        var parser = ResponsesEventParser(kind: kind)
        var deltas: [String] = []
        do {
            for byte in Array(text.utf8) {
                if let delta = try parser.append(byte) { deltas.append(delta) }
                if parser.ended { break }
            }
            if !parser.ended { try parser.endOfStream() }
            return (deltas, parser, nil)
        } catch {
            return (deltas, nil, error)
        }
    }

    func testParserStreamsDeltasAndEndsOnlyAtAnEndEvent() throws {
        let normal = parse(Self.hello.joined())
        XCTAssertEqual(normal.deltas, ["Hel", "lo 🏡"])
        let outcome = try XCTUnwrap(normal.parser).outcome()
        XCTAssertEqual(outcome.end, .complete)
        XCTAssertEqual(outcome.unstreamed, "", "streamed text is not handed on twice")
        XCTAssertEqual(outcome.usage, ModelTokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15, cachedInputTokens: 2, reasoningTokens: 1))
        let crlf = parse(Self.hello.joined().replacingOccurrences(of: "\n", with: "\r\n"))
        XCTAssertEqual(crlf.deltas, ["Hel", "lo 🏡"])
        XCTAssertEqual(crlf.parser?.outcome().end, .complete)
        let cut = parse(Self.event(#"{"type":"response.output_text.delta","delta":"Hi"}"#))
        XCTAssertEqual(cut.parser?.outcome().end, .cut, "a stream without its end event was cut off")
        let doneOnly = parse(Self.event(#"{"type":"response.output_text.delta","delta":"Hi"}"#) + "data: [DONE]\n\n")
        XCTAssertEqual(doneOnly.parser?.outcome().end, .cut, "[DONE] alone is no end event")
        let unterminated = parse(Self.event(#"{"type":"response.output_text.delta","delta":"Hi"}"#)
            + #"data: {"type":"response.completed","response":{}}"#)
        XCTAssertEqual(unterminated.parser?.outcome().end, .complete, "a last event without its blank line still counts")
        let halfSent = parse(Self.event(#"{"type":"response.output_text.delta","delta":"Hi"}"#) + #"data: {"type":"response.comp"#)
        XCTAssertEqual(halfSent.parser?.outcome().end, .cut, "a half-sent last event is a cut")
        XCTAssertEqual(parse("data: {not json\n\n").error as? HTTPChatModelError, .invalidResponse)
    }

    func testParserNamesCutsRefusalsAndFailures() throws {
        let truncated = parse(Self.event(#"{"type":"response.output_text.delta","delta":"Part"}"#)
            + Self.event(#"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"#))
        XCTAssertEqual(truncated.deltas, ["Part"])
        XCTAssertEqual(truncated.parser?.outcome().end, .truncated)
        let filtered = parse(Self.event(#"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}"#))
        XCTAssertEqual(filtered.parser?.outcome().end, .refused)
        let refusal = parse(Self.event(#"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"refusal","refusal":"no"}]}}"#)
            + Self.event(#"{"type":"response.completed","response":{}}"#))
        XCTAssertEqual(refusal.parser?.outcome().end, .refused)
        let itemsOnly = parse(Self.event(#"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"output_text","text":"Whole"}]}}"#)
            + Self.event(#"{"type":"response.completed","response":{}}"#))
        XCTAssertEqual(itemsOnly.parser?.outcome().unstreamed, "Whole", "text that never came as deltas is handed on at the end")
        XCTAssertEqual(parse(Self.event(#"{"type":"response.completed","response":{}}"#)).parser?.outcome().end, .empty)
        func failure(_ json: String, kind: ModelAccountKind = .chatGPT) -> Error? { parse(Self.event(json), kind: kind).error }
        XCTAssertEqual(failure(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}"#)
                       as? ModelAccountError, .planLimitReached)
        XCTAssertEqual(failure(#"{"type":"error","code":"subscription_sharing_user_not_eligible","message":"no"}"#) as? ModelAccountError,
                       .planNotEligible, "an error event without an error object")
        XCTAssertEqual(failure(#"{"type":"error","error":{"code":"rate_limit_exceeded"}}"#) as? ModelAccountError, .planLimitReached)
        XCTAssertEqual(failure(#"{"type":"error","error":{"code":"rate_limit_exceeded"}}"#, kind: .xai) as? HTTPChatModelError, .httpStatus(429))
        XCTAssertEqual(failure(#"{"type":"error","error":{"code":"context_length_exceeded"}}"#) as? ModelAccountError, .contextTooLong)
        XCTAssertEqual(failure(#"{"type":"error","error":{"code":"weird_code","message":"odd"}}"#) as? HTTPChatModelError, .invalidResponse)
        let whole = try ResponsesEventParser.whole(Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Whole"}]}],"usage":{"input_tokens":3,"output_tokens":1}}"#.utf8),
                                                   kind: .chatGPT).outcome()
        XCTAssertEqual(whole.end, .complete)
        XCTAssertEqual(whole.unstreamed, "Whole")
        XCTAssertEqual(whole.usage?.inputTokens, 3)
    }

    func testHTTPFailuresFollowTheAccountKind() {
        func error(_ status: Int, _ body: String = "", kind: ModelAccountKind = .chatGPT) -> Error {
            ResponsesFailure.http(status: status, body: Data(body.utf8), kind: kind)
        }
        XCTAssertEqual(error(403) as? ModelAccountError, .planNotEligible)
        XCTAssertEqual(error(403, kind: .xai) as? ModelAccountError, .planNotAllowed(.xai), "xAI 403: the tier can't use this interface")
        XCTAssertEqual(error(429) as? ModelAccountError, .planLimitReached)
        XCTAssertEqual(error(429, kind: .xai) as? HTTPChatModelError, .httpStatus(429))
        XCTAssertEqual(error(401, kind: .xai) as? ModelAccountError, .unauthorized(.xai))
        XCTAssertEqual(error(400, #"{"error":{"code":"subscription_sharing_usage_unavailable"}}"#) as? HTTPChatModelError, .httpStatus(503))
        XCTAssertEqual(error(400, #"{"error":{"type":"insufficient_quota"}}"#) as? HTTPChatModelError, .httpStatus(402))
        XCTAssertEqual(error(403, #"{"error":{"code":"chatpass_v2_scope_not_authorized"}}"#) as? ModelAccountError, .unauthorized(.chatGPT))
        XCTAssertEqual(error(502) as? HTTPChatModelError, .httpStatus(502))
    }

    // MARK: The client over a fake server

    func testStreamsDeltasAndMetersTheUsage() async throws {
        let server = AccountProtocolFixture.register([.events(Self.hello)])
        let tokens = FakeAccountTokens()
        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: tokens)
        let tally = ModelUsageTally()
        let result = await ModelUsageScope.$tally.withValue(tally) {
            await collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                        configuration: configuration(server.base, maxOutputTokens: 32), apiKey: ""))
        }
        XCTAssertNil(result.error)
        XCTAssertEqual(result.text, "Hello 🏡")
        XCTAssertEqual(tally.seal(), ModelUsageTally.Snapshot(replies: 1, unreported: 0, input: 10, output: 5, cached: 2))
        let sent = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(sent.url.path, "/v1/responses")
        XCTAssertEqual(sent.header("Authorization"), "Bearer token-1")
        XCTAssertEqual(sent.json["model"] as? String, "gpt-fixture")
        XCTAssertNil(sent.json["max_output_tokens"], "no output limit, even for a short purpose")
        XCTAssertEqual(tokens.rejections, [nil])
    }

    func testA401GetsOneFreshTokenAndOneMoreTry() async throws {
        let server = AccountProtocolFixture.register([.json(401, #"{"error":{"code":"invalid_api_key"}}"#), .events(Self.hello)])
        let tokens = FakeAccountTokens()
        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: tokens)
        let text = try await client.complete(messages: [ModelMessage(role: "user", content: "Hi")],
                                             configuration: configuration(server.base), apiKey: "")
        XCTAssertEqual(text, "Hello 🏡")
        XCTAssertEqual(server.requests.map { $0.header("Authorization") }, ["Bearer token-1", "Bearer token-2"])
        XCTAssertEqual(tokens.rejections, [nil, "token-1"], "the refused token is named, so it is refreshed once")

        let twice = AccountProtocolFixture.register([.json(401, "{}"), .json(401, "{}"), .events(Self.hello)])
        let again = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: FakeAccountTokens())
        let result = await collect(again.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                configuration: configuration(twice.base, kind: .xai), apiKey: ""))
        XCTAssertEqual(result.error as? ModelAccountError, .unauthorized(.xai))
        XCTAssertEqual(twice.requests.count, 2, "only one more try")
    }

    func testReferenceBoundCallsNeverResendButRefreshForTheNextRequest() async throws {
        let server = AccountProtocolFixture.register([.json(401, "{}"), .events(Self.hello)])
        let tokens = FakeAccountTokens()
        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: tokens)
        let dispatched = expectation(description: "dispatched")
        dispatched.assertForOverFulfill = false
        do {
            _ = try await client.complete(messages: [ModelMessage(role: "user", content: "Hi")], configuration: configuration(server.base),
                                          apiKey: "", onDispatch: { dispatched.fulfill() })
            XCTFail("a refused bound call fails")
        } catch {
            XCTAssertEqual(error as? ModelAccountError, .unauthorized(.chatGPT))
        }
        await fulfillment(of: [dispatched], timeout: 5)
        XCTAssertEqual(server.requests.count, 1, "no automatic resend")
        XCTAssertEqual(tokens.rejections, [nil, "token-1"], "the refused token is refreshed for the next request")
    }

    func testForbiddenAndLimitsAreNotRetried() async throws {
        let xai = AccountProtocolFixture.register([.json(403, #"{"error":{"message":"tier"}}"#), .events(Self.hello)])
        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: FakeAccountTokens())
        let forbidden = await collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                    configuration: configuration(xai.base, kind: .xai), apiKey: ""))
        XCTAssertEqual(forbidden.error as? ModelAccountError, .planNotAllowed(.xai))
        XCTAssertEqual(xai.requests.count, 1)
        let plan = AccountProtocolFixture.register([.json(429, #"{"error":{"message":"limit"}}"#), .events(Self.hello)])
        do {
            _ = try await client.complete(messages: [ModelMessage(role: "user", content: "Hi")], configuration: configuration(plan.base),
                                          apiKey: "")
            XCTFail("the plan's limit fails")
        } catch {
            XCTAssertEqual(error as? ModelAccountError, .planLimitReached)
        }
        XCTAssertEqual(plan.requests.count, 1)
    }

    func testACutReplyHandsOverItsTextBeforeTruncatedResponse() async throws {
        let server = AccountProtocolFixture.register([.events([
            Self.event(#"{"type":"response.output_text.delta","delta":"Part one, "}"#),
            Self.event(#"{"type":"response.output_text.delta","delta":"part two"}"#),
            Self.event(#"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#)])])
        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: FakeAccountTokens())
        let result = await collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                 configuration: configuration(server.base), apiKey: ""))
        XCTAssertEqual(result.text, "Part one, part two")
        XCTAssertEqual(result.error as? HTTPChatModelError, .truncatedResponse)

        let cut = AccountProtocolFixture.register([.events([Self.event(#"{"type":"response.output_text.delta","delta":"Hi"}"#)])])
        let broken = await collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                 configuration: configuration(cut.base), apiKey: ""))
        XCTAssertEqual(broken.error as? HTTPChatModelError, .incompleteResponse)

        let whole = AccountProtocolFixture.register([.json(200, #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Whole"}]}]}"#)])
        let streamed = await collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                   configuration: configuration(whole.base), apiKey: ""))
        XCTAssertNil(streamed.error)
        XCTAssertEqual(streamed.text, "Whole", "a whole JSON answer instead of a stream")
    }

    func testSignedOutSendsNothingAndCancellationStopsTheStream() async throws {
        let server = AccountProtocolFixture.register([.events(Self.hello)])
        let signedOut = ResponsesModelClient(session: AccountProtocolFixture.session(),
                                             accounts: FakeAccountTokens(failure: ModelAccountError.signInExpired(.chatGPT)))
        let result = await collect(signedOut.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                    configuration: configuration(server.base), apiKey: ""))
        XCTAssertEqual(result.error as? ModelAccountError, .signInExpired(.chatGPT))
        XCTAssertTrue(server.requests.isEmpty)

        let client = ResponsesModelClient(session: AccountProtocolFixture.session(), accounts: FakeAccountTokens())
        let task = Task { await self.collect(client.stream(messages: [ModelMessage(role: "user", content: "Hi")],
                                                           configuration: self.configuration(server.base), apiKey: "")) }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.error is CancellationError || cancelled.error == nil, String(describing: cancelled.error))
    }

    func testTheProviderClientChoosesByTheAccountRoute() async throws {
        let responses = AccountProtocolFixture.register([.events(Self.hello)])
        let completions = AccountProtocolFixture.register([.json(200, #"{"choices":[{"message":{"role":"assistant","content":"compat"},"finish_reason":"stop"}]}"#)])
        let session = AccountProtocolFixture.session()
        let client = ModelProviderClient(http: HTTPChatModelClient(session: session),
                                         responses: ResponsesModelClient(session: session, accounts: FakeAccountTokens()))
        let account = try await client.complete(messages: [ModelMessage(role: "user", content: "Hi")],
                                                configuration: configuration(responses.base), apiKey: "")
        XCTAssertEqual(account, "Hello 🏡")
        XCTAssertEqual(responses.requests.first?.url.path, "/v1/responses")
        let compat = try await client.complete(messages: [ModelMessage(role: "user", content: "Hi")],
                                               configuration: ModelConfiguration(baseURL: completions.base.appendingPathComponent("v1"), model: "m"),
                                               apiKey: "fixture-key-not-real")
        XCTAssertEqual(compat, "compat")
        XCTAssertEqual(completions.requests.first?.url.path, "/v1/chat/completions")
        XCTAssertEqual(completions.requests.first?.header("Authorization"), "Bearer fixture-key-not-real")
        let noAccounts = ModelProviderClient(accounts: nil)
        do {
            _ = try await noAccounts.complete(messages: [ModelMessage(role: "user", content: "Hi")],
                                              configuration: configuration(responses.base), apiKey: "")
            XCTFail("an account configuration needs the account client")
        } catch {
            XCTAssertEqual(error as? HTTPChatModelError, .invalidConfiguration)
        }
        XCTAssertEqual(responses.requests.count, 1)
    }
}
