import Foundation
@testable import AssistantModels
import AssistantMemory
import AssistantMCP

private enum Failure: Error { case check(String), injected }
private let config = ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture", vision: .supported)
private let prompt = "Summarize this file and check the selected tool."
private let reviewed = [ModelMessage(role: "user", content: prompt)]
private let key = "synthetic-key"
private let secret = "synthetic-file-sentinel-09423"

private actor Gate {
    private var arrived = false
    private var released = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    func wait() async {
        arrived = true; arrival?.resume(); arrival = nil
        if released { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() { released = true; waiting?.resume(); waiting = nil }
}

private actor Model: LifetimeBoundCompletionChatModelClient, StructuredStreamingChatModelClient {
    let replies: [String]
    let fails: Bool
    let gate: Gate?
    private(set) var bodies: [Data] = []
    private(set) var streams = 0
    init(_ replies: [String] = [], fails: Bool = false, gate: Gate? = nil) {
        self.replies = replies; self.fails = fails; self.gate = gate
    }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        let body = try OpenAIChatRequest.body(model: configuration.model, messages: messages, stream: false,
                                              maxOutputTokens: configuration.maxOutputTokens, vision: configuration.vision)
        bodies.append(body)
        if let gate { await gate.wait() }
        if fails { throw Failure.injected }
        guard bodies.count <= replies.count else { throw Failure.injected }
        return replies[bodies.count - 1]
    }
    private func markStream() { streams += 1 }
    nonisolated func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.markStream(); continuation.finish(throwing: HTTPStreamFallbackError.explicitUnsupported(400)) }
        }
    }
}

private actor Executor: MCPConversationExecuting {
    private(set) var calls = 0
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        calls += 1; return .object(["value": .string("synthetic-result")])
    }
    func readResource(uri: String) async throws -> JSONValue { throw Failure.injected }
}

private actor Approvals {
    private(set) var count = 0
    func accept() -> Bool { count += 1; return true }
}

@main private struct Checks {
    static var count = 0
    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw Failure.check(label) }; count += 1
    }
    static func selected() throws -> ModelAttachment { try .text(utf8: Data(secret.utf8)) }
    static func wrapper(_ model: Model) throws -> OneShotAttachmentModelClient {
        try OneShotAttachmentModelClient(client: model, attachment: selected(), reviewedMessages: reviewed,
                                         configuration: config, apiKey: key)
    }
    static func occurrence(_ data: Data, _ text: String) -> Int {
        String(decoding: data, as: UTF8.self).components(separatedBy: text).count - 1
    }
    static func errors(_ body: () async throws -> Void, _ expected: OneShotAttachmentError) async throws {
        do { try await body(); throw Failure.check("expected \(expected)") }
        catch let error as OneShotAttachmentError { try check(error == expected, "wrong boundary error") }
    }
    @MainActor static func main() async throws {
        try await profileFlow()
        try await mcpFlow()
        try await failures()
        try await concurrency()
        print("Attachment tool boundary: \(count) checks passed (synthetic, offline)")
    }
    @MainActor static func profileFlow() async throws {
        let model = Model([#"{"action":"memory_search","arguments":{"query":"tea"}}"#,
                           #"{"action":"finish","answer":"done"}"#])
        let client = try wrapper(model), flow = try UserProfileChatFlow(messages: reviewed)
        let step = try await flow.advance(client: client, configuration: config, apiKey: key, onAnswerPreview: { _ in })
        guard case .memorySearch = step else { throw Failure.check("profile search") }
        try flow.recordMemorySearchResult(#"{"ok":true,"memories":[]}"#)
        let finish = try await flow.advance(client: client, configuration: config, apiKey: key, onAnswerPreview: { _ in })
        try check(finish == .answer("done"), "profile finished")
        let bodies = await model.bodies
        try check(bodies.count == 2, "profile calls")
        try check(await model.streams == 0, "structured stream fallback cannot resend attachment")
        try check(occurrence(bodies[0], secret) == 1 && occurrence(bodies[1], secret) == 0, "text attachment only in first JSON")
        let first = try JSONSerialization.jsonObject(with: bodies[0]) as! [String: Any]
        let firstMessages = first["messages"] as! [[String: Any]]
        let parts = firstMessages.last!["content"] as! [[String: Any]]
        try check(parts.count == 2 && (parts[1]["text"] as? String)?.contains("untrusted data") == true, "attachment marked data")

        let argument = #"{"kind":"fact","content":"synthetic-file-sentinel-09423","quote":"synthetic-file-sentinel-09423"}"#
        let run = MemoryToolRun(state: MemoryState(), utterances: [prompt])
        do { _ = try run.prepare(toolName: "memory_save", argumentsJSON: argument); throw Failure.check("attachment authorized memory") }
        catch MemoryToolError.quoteNotFromUser { try check(true, "attachment cannot authorize memory") }
        let legitimate = MemoryToolRun(state: MemoryState(), utterances: ["Remember Green tea"])
        let prepared = try legitimate.prepare(toolName: "memory_save", argumentsJSON:
            #"{"kind":"fact","content":"Green tea","quote":"Remember Green tea"}"#)
        try check(prepared.after?.content == "Green tea", "explicit typed memory remains eligible for review")
    }
    static func mcpFlow() async throws {
        let model = Model([#"{"action":"call_tool","name":"echo","arguments":{"value":"synthetic"}}"#,
                           #"{"action":"memory_search","arguments":{"query":"tea"}}"#,
                           #"{"action":"finish","answer":"done"}"#])
        let client = try wrapper(model), executor = Executor(), approvals = Approvals()
        let tool = MCPTool(name: "echo", description: "fixture", inputSchema: .object([:]))
        let result = try await MCPConversationRunner(client: client).run(messages: reviewed, configuration: config,
            apiKey: key, tools: [tool], executor: executor, approve: { _ in await approvals.accept() },
            handleLocal: { proposal, lease in
                try lease.check()
                guard proposal.action == .memorySearch else { throw Failure.injected }
                return .searchResult(json: #"{"ok":true,"memories":[]}"#)
            })
        let bodies = await model.bodies
        try check(result.stopReason == .finished && bodies.count == 3, "MCP and memory multi-call completes")
        try check(occurrence(bodies[0], secret) == 1 && bodies.dropFirst().allSatisfy { occurrence($0, secret) == 0 }, "MCP attaches once")
        let calls = await executor.calls, approved = await approvals.count
        try check(calls == 1 && approved == 1, "remote action needs exact approval")

        let deniedModel = Model([#"{"action":"call_tool","name":"echo","arguments":{"value":"synthetic-file-sentinel-09423"}}"#])
        let deniedClient = try wrapper(deniedModel), deniedExecutor = Executor()
        let denied = try await MCPConversationRunner(client: deniedClient).run(messages: reviewed, configuration: config,
            apiKey: key, tools: [tool], executor: deniedExecutor, approve: { _ in false })
        let deniedCalls = await deniedExecutor.calls
        try check(denied.stopReason == .approvalDenied && deniedCalls == 0,
                  "attachment-derived proposal cannot authorize remote dispatch")

        let malicious = Model([#"{"action":"memory_save","arguments":{"kind":"fact","content":"synthetic-file-sentinel-09423","quote":"synthetic-file-sentinel-09423"}}"#])
        let maliciousClient = try wrapper(malicious), maliciousExecutor = Executor()
        do {
            _ = try await MCPConversationRunner(client: maliciousClient).run(messages: reviewed, configuration: config,
                apiKey: key, tools: [tool], executor: maliciousExecutor, approve: { _ in true },
                handleLocal: { proposal, lease in
                    try lease.check()
                    let run = MemoryToolRun(state: MemoryState(), utterances: [prompt])
                    _ = try run.prepare(toolName: proposal.action.rawValue, argumentsJSON: proposal.argumentsJSON)
                    throw Failure.check("unauthorized memory accepted")
                })
            throw Failure.check("unauthorized memory reached finish")
        } catch MemoryToolError.quoteNotFromUser { try check(true, "actual MCP local handler rejects attachment authority") }
    }
    static func failures() async throws {
        let model = Model(fails: true), client = try wrapper(model)
        do { _ = try await client.complete(messages: reviewed, configuration: config, apiKey: key); throw Failure.check("expected transport failure") }
        catch Failure.injected { try check(true, "first failure") }
        try await errors({ _ = try await client.complete(messages: reviewed, configuration: config, apiKey: key) }, .ended)
        try check(await model.bodies.count == 1, "no resend after uncertain failure")
        for changed in [ModelConfiguration(baseURL: URL(string: "https://other.invalid")!, model: "fixture", vision: .supported),
                        ModelConfiguration(baseURL: config.baseURL, model: "other", vision: .supported),
                        ModelConfiguration(baseURL: config.baseURL, model: config.model, maxOutputTokens: 99, vision: .supported),
                        ModelConfiguration(baseURL: config.baseURL, model: config.model, vision: .unknown)] {
            let model = Model(), client = try wrapper(model)
            try await errors({ _ = try await client.complete(messages: reviewed, configuration: changed, apiKey: key) }, .contextChanged)
            try check(await model.bodies.isEmpty, "changed target never sends")
        }
        let changedModel = Model(), changedClient = try wrapper(changedModel)
        try await errors({ _ = try await changedClient.complete(messages: reviewed, configuration: config, apiKey: "different") }, .contextChanged)
        try check(await changedModel.bodies.isEmpty, "changed key never sends")
        let changedContext = Model(), changedContextClient = try wrapper(changedContext)
        try await errors({ _ = try await changedContextClient.complete(messages: [.init(role: "user", content: "changed")], configuration: config, apiKey: key) }, .contextChanged)
        try check(await changedContext.bodies.isEmpty, "changed reviewed messages never send")
        let injected = Model(), injectedClient = try wrapper(injected)
        let unexpected = ModelMessage(userText: prompt, attachment: try selected())
        try await errors({ _ = try await injectedClient.complete(messages: [unexpected], configuration: config, apiKey: key) }, .contextChanged)
        try check(await injected.bodies.isEmpty, "caller cannot inject another attachment")
        let cancelled = Model(), cancelledClient = try wrapper(cancelled)
        await cancelledClient.cancel()
        try await errors({ _ = try await cancelledClient.complete(messages: reviewed, configuration: config, apiKey: key) }, .ended)
        try check(await cancelled.bodies.isEmpty, "discard before start")
        let duplicate = Model(["success"]), duplicateClient = try wrapper(duplicate)
        _ = try await duplicateClient.complete(messages: reviewed, configuration: config, apiKey: key)
        try await errors({ _ = try await duplicateClient.complete(messages: reviewed, configuration: config, apiKey: key) }, .contextChanged)
        try check(await duplicate.bodies.count == 1, "same prompt cannot be retried without attachment")
        let changedLater = Model(["success"]), changedLaterClient = try wrapper(changedLater)
        _ = try await changedLaterClient.complete(messages: reviewed, configuration: config, apiKey: key)
        try await errors({ _ = try await changedLaterClient.complete(messages: reviewed + [.init(role: "user", content: "next")],
            configuration: config, apiKey: "new-key") }, .contextChanged)
        try check(await changedLater.bodies.count == 1, "changed destination binding stops later calls")

        let imageBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01])
        let image = try ModelAttachment.image(data: imageBytes, mimeType: "image/png")
        let imageModel = Model(["success", "done"])
        let imageClient = try OneShotAttachmentModelClient(client: imageModel, attachment: image,
            reviewedMessages: reviewed, configuration: config, apiKey: key)
        _ = try await imageClient.complete(messages: reviewed, configuration: config, apiKey: key)
        _ = try await imageClient.complete(messages: reviewed + [.init(role: "user", content: "next")], configuration: config, apiKey: key)
        let imageBodies = await imageModel.bodies
        try check(occurrence(imageBodies[0], imageBytes.base64EncodedString()) == 1 &&
                  occurrence(imageBodies[1], imageBytes.base64EncodedString()) == 0, "image bytes only in first JSON")
        let unknown = ModelConfiguration(baseURL: config.baseURL, model: config.model, vision: .unknown)
        let unknownModel = Model(), unknownClient = try OneShotAttachmentModelClient(client: unknownModel, attachment: image,
            reviewedMessages: reviewed, configuration: unknown, apiKey: key)
        do { _ = try await unknownClient.complete(messages: reviewed, configuration: unknown, apiKey: key); throw Failure.check("unknown vision") }
        catch ModelAttachmentError.visionUnknown { try check(true, "unknown vision rejected") }
        try await errors({ _ = try await unknownClient.complete(messages: reviewed, configuration: unknown, apiKey: key) }, .ended)
        try check(await unknownModel.bodies.isEmpty, "unknown vision never serialized")
    }
    static func concurrency() async throws {
        let earlyModel = Model(), earlyClient = try wrapper(earlyModel)
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await earlyClient.complete(messages: reviewed, configuration: config, apiKey: key)
        }
        do { _ = try await early.value; throw Failure.check("expected cancellation before start") }
        catch is CancellationError { try check(true, "cancellation before first request") }
        try check(await earlyModel.bodies.isEmpty, "cancel before start does not reach client")
        try await errors({ _ = try await earlyClient.complete(messages: reviewed, configuration: config, apiKey: key) }, .ended)
        let gate = Gate(), model = Model(["reply"], gate: gate), client = try wrapper(model)
        let first = Task { try await client.complete(messages: reviewed, configuration: config, apiKey: key) }
        await gate.waitForArrival()
        try await errors({ _ = try await client.complete(messages: reviewed, configuration: config, apiKey: key) }, .requestInProgress)
        await client.cancel(); await gate.release()
        do { _ = try await first.value; throw Failure.check("cancel must end in-flight turn") }
        catch is CancellationError { try check(true, "cancel while in flight") }
        try await errors({ _ = try await client.complete(messages: reviewed, configuration: config, apiKey: key) }, .ended)
        try check(await model.bodies.count == 1, "cancelled request not replayed")
    }
}
