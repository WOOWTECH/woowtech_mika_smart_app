import Foundation

private struct Failure: Error { let message: String }
private struct SecretError: Error { let secret: String }

private actor Gate {
    var continuation: CheckedContinuation<String, Error>?
    var messages: [ModelMessage] = []
    var maxTokens = 0
    func wait(messages: [ModelMessage], configuration: ModelConfiguration) async throws -> String {
        self.messages = messages; maxTokens = configuration.maxOutputTokens
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func started() -> Bool { continuation != nil }
    func complete(_ text: String) { continuation?.resume(returning: text); continuation = nil }
    func snapshot() -> ([ModelMessage], Int) { (messages, maxTokens) }
}

private struct WaitingClient: ChatModelClient {
    let gate: Gate
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await gate.wait(messages: messages, configuration: configuration)
    }
}

private struct ErrorClient: ChatModelClient {
    let error: any Error
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String { throw error }
}

@main struct CheckModelConnection {
    @MainActor static func main() async throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            assertions += 1
            guard condition() else { throw Failure(message: label) }
        }
        func wait(_ condition: @escaping @MainActor () async -> Bool) async throws {
            for _ in 0..<1000 {
                if await condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw Failure(message: "fixture deadline")
        }
        let key = "fixture-secret-never-print"
        let config = ModelConfiguration(baseURL: URL(string: "https://model.example.invalid/v1")!, model: "fixture")
        let checkModel = ModelConnectionCheck(timeoutNanoseconds: 1_000_000_000)
        try check(checkModel.state == .untested, "starts untested")
        let gate = Gate()
        checkModel.start(client: WaitingClient(gate: gate), configuration: config, apiKey: key)
        try await wait { await gate.started() }
        let (messages, budget) = await gate.snapshot()
        try check(messages.count == 1 && messages[0].role == "user" && messages[0].content == "This is a connection test. Reply briefly.", "only fixed test message")
        try check(!messages[0].content.contains(key) && budget == 32, "bounded prompt contains no key")
        await gate.complete("test reply")
        try await wait { checkModel.state == .passed }
        try check(checkModel.state == .passed, "nonempty completion passes")
        checkModel.reset()
        try check(checkModel.state == .untested, "reset removes pass")

        let cancelled = Gate()
        checkModel.start(client: WaitingClient(gate: cancelled), configuration: config, apiKey: key)
        try await wait { await cancelled.started() }
        checkModel.reset()
        await cancelled.complete("late")
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(checkModel.state == .untested, "cancelled noncooperative completion ignored")

        let old = Gate(), newer = Gate()
        checkModel.start(client: WaitingClient(gate: old), configuration: config, apiKey: key)
        try await wait { await old.started() }
        checkModel.start(client: WaitingClient(gate: newer), configuration: config, apiKey: key)
        try await wait { await newer.started() }
        await old.complete("old")
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(checkModel.state == .testing, "old result cannot replace new test")
        await newer.complete("new")
        try await wait { checkModel.state == .passed }
        try check(checkModel.state == .passed, "new test completes")

        let timeoutGate = Gate(), timed = ModelConnectionCheck(timeoutNanoseconds: 25_000_000)
        timed.start(client: WaitingClient(gate: timeoutGate), configuration: config, apiKey: key)
        try await wait { await timeoutGate.started() }
        try await wait { timed.state == .failed(.timeout) }
        await timeoutGate.complete("too late")
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(timed.state == .failed(.timeout), "deadline cannot be replaced by late success")

        let cases: [(any Error, ModelConnectionCheck.Failure)] = [
            (HTTPChatModelError.invalidConfiguration, .configuration), (HTTPChatModelError.httpStatus(401), .authentication),
            (HTTPChatModelError.httpStatus(403), .authentication), (HTTPChatModelError.httpStatus(404), .notFound),
            (HTTPChatModelError.httpStatus(429), .rateLimited), (HTTPChatModelError.httpStatus(503), .server),
            (HTTPChatModelError.httpStatus(400), .rejected), (HTTPChatModelError.invalidResponse, .response),
            (HTTPChatModelError.redirectRejected, .redirect), (HTTPChatModelError.timedOut, .timeout),
            (SecretError(secret: key), .network)
        ]
        for (error, expected) in cases {
            checkModel.start(client: ErrorClient(error: error), configuration: config, apiKey: key)
            try await wait { checkModel.state != .testing }
            try check(checkModel.state == .failed(expected), "error classification")
            try check(!String(describing: checkModel.state).contains(key), "no error detail in state")
        }
        checkModel.credentialsUnavailable()
        try check(checkModel.state == .failed(.credentials), "credential error is fixed")
        let reentrant = ModelConnectionCheck()
        reentrant.onChange = { state in if state == .testing { reentrant.reset() } }
        let notStarted = Gate()
        reentrant.start(client: WaitingClient(gate: notStarted), configuration: config, apiKey: key)
        try await Task.sleep(nanoseconds: 20_000_000)
        let started = await notStarted.started()
        try check(reentrant.state == .untested && !started, "reentrant cancellation cannot start a request")

        let reentry = ModelConnectionCheck()
        reentry.credentialsUnavailable()
        let reentryGate = Gate()
        reentry.onChange = { state in
            if state == .untested {
                reentry.start(client: WaitingClient(gate: reentryGate), configuration: config, apiKey: key)
            }
        }
        reentry.credentialsUnavailable()
        try await wait { await reentryGate.started() }
        try check(reentry.state == .testing, "a reentrant new test is not replaced by a stale credential failure")
        await reentryGate.complete("ok")
        try await wait { reentry.state == .passed }

        let empty = Gate()
        checkModel.start(client: WaitingClient(gate: empty), configuration: config, apiKey: key)
        try await wait { await empty.started() }
        await empty.complete("  \n")
        try await wait { checkModel.state != .testing }
        try check(checkModel.state == .failed(.response), "blank completion cannot pass")

        let session = ModelProtocolFixture.session()
        defer { session.invalidateAndCancel() }
        let response = Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#.utf8)
        let fixture = ModelProtocolFixture.Scenario(chunks: [response])
        let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
        checkModel.start(client: HTTPChatModelClient(session: session),
                         configuration: .init(baseURL: url, model: "fixture"), apiKey: key)
        try await wait { checkModel.state != .testing }
        try check(checkModel.state == .passed && fixture.requestCount == 1, "intercepted HTTP completion")
        guard let request = fixture.lastRequest else { throw Failure(message: "missing intercepted request") }
        let body: Data
        if let data = request.httpBody { body = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw Failure(message: "fixture body unreadable") }
                if count == 0 { break }
                guard result.count + count <= 16_384 else { throw Failure(message: "fixture body too large") }
                result.append(contentsOf: buffer.prefix(count))
            }
            body = result
        } else { throw Failure(message: "missing fixture body") }
        guard let wire = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let sentMessages = wire["messages"] as? [[String: String]] else { throw Failure(message: "invalid fixture body") }
        try check(sentMessages == [["role": "user", "content": "This is a connection test. Reply briefly."]],
                  "intercepted HTTP sends the fixed prompt only")
        try check(wire["stream"] as? Bool == false && wire["max_tokens"] as? Int == 32,
                  "intercepted HTTP uses bounded non-streaming completion")
        try check(!String(decoding: body, as: UTF8.self).contains(key), "fixture key is absent from request body")
        let rejected = ModelProtocolFixture.Scenario(status: 401, chunks: [Data(key.utf8)])
        let rejectedURL = ModelProtocolFixture.register(rejected); defer { ModelProtocolFixture.remove(rejectedURL) }
        checkModel.start(client: HTTPChatModelClient(session: session),
                         configuration: .init(baseURL: rejectedURL, model: "fixture"), apiKey: key)
        try await wait { checkModel.state != .testing }
        try check(checkModel.state == .failed(.authentication) && rejected.requestCount == 1,
                  "intercepted HTTP authorization failure remains content-free")
        let held = ModelProtocolFixture.Scenario(holdBeforeHeaders: true)
        let heldURL = ModelProtocolFixture.register(held); defer { ModelProtocolFixture.remove(heldURL) }
        checkModel.start(client: HTTPChatModelClient(session: session),
                         configuration: .init(baseURL: heldURL, model: "fixture"), apiKey: key)
        try await wait { held.requestCount == 1 }
        checkModel.reset()
        try await wait { held.stopCount > 0 }
        try check(checkModel.state == .untested && held.requestCount == 1, "cancel stops intercepted transport without replay")
        print("PASS model connection: \(assertions) assertions; synthetic clients and intercepted HTTP only")
    }
}
