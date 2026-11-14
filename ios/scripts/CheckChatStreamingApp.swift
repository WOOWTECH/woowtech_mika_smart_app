#if CHAT_STREAM_APP_STANDALONE || canImport(WoowAssistant)
import AssistantModels
import AssistantMemory
import AssistantMCP
import AssistantPersistence
import AssistantDomain
import Combine
import Foundation
#if !CHAT_STREAM_APP_STANDALONE
import XCTest
@testable import WoowAssistant
#endif

private final class StreamKeys: LearningKeyStore {
    var values: [String: Data] = [:]
    func read(id: String) throws -> Data? { values[id] }
    func insert(_ key: Data, id: String) throws { values[id] = key }
    func remove(id: String) throws { values.removeValue(forKey: id) }
    func removeAll(except id: String) throws { values = values.filter { $0.key == id } }
}
private final class StreamCredentials: ModelCredentialStoring {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values = [:] }
}
private final class StreamClient: StructuredStreamingChatModelClient, ReferenceDispatchBoundStreamingChatModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private let replies: [String]
    private var completions = 0
    private var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
    init(_ replies: [String] = []) { self.replies = replies }
    private func nextReply() throws -> String {
        lock.lock(); defer { lock.unlock() }
        let index = completions; completions += 1
        guard index < replies.count else { throw ChatStreamingChecks.Failure(name: "unexpected complete/extraction request") }
        return replies[index]
    }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String { try nextReply() }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                  onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        onDispatch(); return try nextReply()
    }
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: {}, onProducerFinished: {})
    }
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                onDispatch: @escaping @Sendable () -> Void,
                onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(8)) { c in
            c.onTermination = { @Sendable _ in onProducerFinished() }
            onDispatch() // Synthetic in-process dispatch, no real transport.
            lock.lock(); streams.append(c); lock.unlock()
        }
    }
    var counts: (complete: Int, stream: Int) { lock.lock(); defer { lock.unlock() }; return (completions, streams.count) }
    private func continuation(_ index: Int) -> AsyncThrowingStream<String, Error>.Continuation {
        lock.lock(); defer { lock.unlock() }; return streams[index]
    }
    @discardableResult func emit(_ text: String, at index: Int = 0) -> Bool {
        if case .enqueued = continuation(index).yield(text) { return true }; return false
    }
    func finish(_ error: Error? = nil, at index: Int = 0) { continuation(index).finish(throwing: error) }
}
private final class CompleteSequenceClient: ReferenceDispatchBoundChatModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private let replies: [String]
    private var requests = 0
    init(_ replies: [String]) { self.replies = replies }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        lock.lock(); defer { lock.unlock() }
        let index = requests; requests += 1
        guard index < replies.count else { throw ChatStreamingChecks.Failure(name: "unexpected structured fallback request") }
        return replies[index]
    }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                  onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        onDispatch(); return try await complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }
    var counts: (complete: Int, stream: Int) { lock.lock(); defer { lock.unlock() }; return (requests, 0) }
}
private struct CompleteOnlyClient: ReferenceDispatchBoundChatModelClient {
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String { "Complete-only adapter reply" }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                  onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        onDispatch(); return try await complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }
}
/// Fails every request with one model error, as HTTPChatModelClient would.
private struct FailingClient: ReferenceDispatchBoundChatModelClient {
    let error: HTTPChatModelError
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String { throw error }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                  onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        onDispatch(); throw error
    }
}
#if DEBUG
private actor FixturePauseRecorder {
    private var intervals: [UInt64] = []
    func pause(_ nanoseconds: UInt64) { intervals.append(nanoseconds) }
    func recorded() -> [UInt64] { intervals }
}
private actor FixturePauseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func pause() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
@MainActor private final class StreamNotifications: TaskNotificationClient {
    var operations = 0, adds = 0
    var kinds: [TaskNotificationKind] = []
    func settings() async -> TaskNotificationSettings { operations += 1; return .init(authorization: .authorized, sound: .enabled, alert: .enabled) }
    func requestAuthorization() async throws { operations += 1 }
    func add(_ payload: TaskNotificationPayload, sound: Bool) async throws { operations += 1; adds += 1; kinds.append(payload.kind) }
    func remove(identifiers: [String]) async { operations += 1 }
    func removeAllOwned() async { operations += 1 }
}
@MainActor private final class StreamEnvironment {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-stream-" + UUID().uuidString)
    let suite = "woow.stream.check." + UUID().uuidString
    let keys = StreamKeys(), learningKeys = StreamKeys()
    let defaults: UserDefaults
    let repository: ModelSettingsRepository
    let learning: LearningStore
    let archive: ConversationArchiveStore
    var archiveFile: URL { root.appendingPathComponent("archive.vault") }
    var learningFile: URL { root.appendingPathComponent("learning.vault") }
    init(baseURL: URL = URL(string: "https://stream.example.invalid/v1")!) throws {
        defaults = UserDefaults(suiteName: suite)!
        repository = ModelSettingsRepository(defaults: defaults, credentials: StreamCredentials())
        _ = try repository.save(baseURL: baseURL.absoluteString, model: "fixture", newKey: "synthetic-not-a-key")
        // The user agreed to share content with this provider (App Review 5.1.2(i)).
        try repository.recordConsentForMain()
        learning = LearningStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("learning.vault"), keys: learningKeys))
        guard learning.updatePreferences({ $0.useMemory = false; $0.autoRemember = true }) else { throw ChatStreamingChecks.Failure(name: "isolated learning creation") }
        archive = ConversationArchiveStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("archive.vault"), keys: keys))
    }
    func session(_ client: any ChatModelClient) -> ChatSession { ChatSession(learning: learning, repository: repository, client: client, archive: archive) }
    func reopen() -> ConversationArchiveStore { ConversationArchiveStore(vault: EncryptedLearningFile(url: archiveFile, keys: keys)) }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}
private struct StreamEndpoint: MCPEndpointStoring {
    func load() throws -> URL? { URL(string: "https://mcp-stream.example.invalid/fixture") }
    func save(endpoint: String) throws { throw MCPSettingsError.invalidEndpoint }
    func remove() throws {}
}
private actor StreamMCP: MCPDiscovering {
    private(set) var calls = 0
    func initialize() async throws -> MCPServerInfo { .init(protocolVersion: "2025-03-26", capabilities: ["tools"]) }
    func listTools() async throws -> [MCPTool] { [.init(name: "synthetic_read", inputSchema: .object(["type": .string("object")]))] }
    func listResources() async throws -> [MCPResource] { [] }
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        guard name == "synthetic_read" else { throw MCPError.invalidRequest }
        calls += 1
        return .object(["isError": .bool(false), "content": .array([.object(["type": .string("text"), "text": .string("Read value")])])])
    }
    func readResource(uri: String) async throws -> JSONValue { throw MCPError.invalidRequest }
    func cancel() async {}
}

@MainActor enum ChatStreamingChecks {
    struct Failure: Error { let name: String }
    struct Assertions {
        var count = 0
        mutating func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try value() else { throw Failure(name: name) }; count += 1
        }
    }
    private static func wait(_ label: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            guard Date() < deadline else { throw Failure(name: label) }
            await Task.yield()
        }
    }
    #if DEBUG
    /// Run the real DEBUG adapter with an immediate recording sleeper. This
    /// checks its emitted fragments and the UI tests' interaction windows
    /// without sleeping through them.
    static func fixtureInteractionWindows() async throws -> Int {
        var a = Assertions()
        guard let fixture = try UITestChatStreamingConfiguration.resolve(arguments:
            ["-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestChatStreaming"])
        else { throw Failure(name: "stream fixture not selected") }
        let configuration = ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture")
        let second: UInt64 = 1_000_000_000
        let cases: [(prompt: String, markers: [String], minimumWindows: [UInt64])] = [
            ("[fixture:stream-scroll]", ["SCROLL_FIRST_END", "SCROLL_SECOND_END"], [40, 15]),
            ("[fixture:stream-return]", ["RETURN_FIRST_END", "RETURN_SECOND_END", "RETURN_THIRD_END"], [30, 20, 10]),
            ("[fixture:stream-noop]", ["短回覆；等待下一段。", "SCROLL_NOOP_GROW_END"], [30, 10])
        ]
        for test in cases {
            let clock = FixturePauseRecorder()
            let client = UITestStreamingChatModelClient(configuration: fixture,
                sleep: { nanoseconds in await clock.pause(nanoseconds) })
            var fragments: [String] = []
            for try await fragment in client.stream(messages: [.init(role: "user", content: test.prompt)],
                                                    configuration: configuration, apiKey: "synthetic") {
                fragments.append(fragment)
            }
            let intervals = await clock.recorded()
            try a.check(fragments.count == test.markers.count &&
                zip(fragments, test.markers).allSatisfy({ $0.0.contains($0.1) }),
                "fixture fragment order for \(test.prompt)")
            try a.check(intervals.count == test.minimumWindows.count &&
                zip(intervals, test.minimumWindows).allSatisfy({ $0.0 >= $0.1 * second }),
                "native interaction windows for \(test.prompt)")
        }
        let structuredClock = FixturePauseRecorder()
        let structuredClient = UITestStreamingChatModelClient(configuration: fixture,
            sleep: { nanoseconds in await structuredClock.pause(nanoseconds) })
        var structuredFragments: [String] = []
        for try await fragment in structuredClient.stream(messages: [
            .init(role: "system", content: "Ordinary chat with an available profile_edit tool."),
            .init(role: "user", content: "[fixture:structured-stream-complete]")
        ], configuration: configuration, apiKey: "synthetic") {
            structuredFragments.append(fragment)
        }
        let structuredIntervals = await structuredClock.recorded()
        try a.check(structuredFragments.count == 2 && structuredFragments[0].contains("結構化串流：第一段")
                    && structuredFragments[1].contains("；完整回覆。"), "structured fixture retains ordered fragments")
        try a.check(structuredIntervals == [30 * second], "structured archive interaction has a 30-second window")
        return a.count
    }
    #endif
    /// Like the Play build the question is in the transcript from the moment it
    /// is sent; until an answer arrives the last entry is the question, and a
    /// turn that ended without one closes with 沒有完成 or 已停止。
    private static func unanswered(_ session: ChatSession) -> Bool {
        session.entries.last?.role == "user" || session.entries.last?.outcome != nil
    }
    private static func ended(_ session: ChatSession, _ outcome: ArchivedConversationTurn.Outcome) -> Bool {
        session.entries.last?.role == "assistant" && session.entries.last?.outcome == outcome
    }
    /// No completed answer reached the archive (a turn without one may be saved).
    private static func noSavedAnswer(_ store: ConversationArchiveStore) -> Bool {
        store.state.conversations.allSatisfy { $0.turns.allSatisfy { $0.outcome != nil } }
    }
    private static func start(_ session: ChatSession, _ prompt: String, mcp: MCPSession? = nil) throws -> Task<Void, Never> {
        session.draft = prompt; session.send(mcp: mcp)
        guard let task = session.capturedArchiveRequest else { throw Failure(name: "actual request missing") }
        return task
    }
    private static func interceptedBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        // URLSession may move the request body into a stream before URLProtocol.
        guard let stream = request.httpBodyStream else { throw Failure(name: "intercepted request body absent") }
        stream.open(); defer { stream.close() }
        var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw Failure(name: "intercepted request body unreadable") }
            if count == 0 { return body }
            guard body.count + count <= 64 * 1024 else { throw Failure(name: "unexpected fixture request size") }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
    static func incrementalCompletion() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let client = StreamClient(); let session = e.session(client)
        let conversationAtStart = session.conversationID
        var publishedConversations: [String] = []
        let identityObservation = session.$conversationID.sink { publishedConversations.append($0) }
        defer { identityObservation.cancel() }
        let notifications = StreamNotifications(); let service = TaskNotificationService(client: notifications, enabled: true)
        await service.refresh(); let baseline = notifications.operations
        let bridge = TaskNotificationChatBridge(session: session, service: service); defer { bridge.invalidate() }
        let learningBytes = try Data(contentsOf: e.learningFile)
        try a.check(session.chatStatusMessage == .chatStatusConfigured, "configured status before request")
        let task = try start(session, "A complete streaming question")
        try await wait("stream requested") { client.counts.stream == 1 }
        client.emit("Hello "); try await wait("first real partial") { session.replyPreview?.text == "Hello " }
        let id = session.replyPreview!.id
        try a.check(session.isSubmitting && session.replyPreview?.phase == .receiving, "partial explicitly unfinished")
        try a.check(session.chatStatusMessage == .chatStatusWaiting, "in-flight status reflects the actual request")
        try a.check(session.entries.map(\.role) == ["user"] && e.archive.conversations.isEmpty && !FileManager.default.fileExists(atPath: e.archiveFile.path), "the question shows at once; the partial is neither complete nor durable")
        try a.check(session.draft.isEmpty && session.entries.first?.content == "A complete streaming question", "like Play the input bar empties when the question is sent")
        await service.waitUntilIdle()
        try a.check(notifications.operations == baseline && notifications.adds == 0, "actual notification bridge ignores partial")
        try a.check(try Data(contentsOf: e.learningFile) == learningBytes && !e.learning.isLearning, "partial never extracts learning")
        client.emit("世界 🏡"); try await wait("second real partial") { session.replyPreview?.text == "Hello 世界 🏡" }
        try a.check(session.replyPreview?.id == id && session.entries.count == 1, "one preview identity across Unicode deltas")
        client.finish(); await task.value; await service.waitUntilIdle()
        try a.check(!session.isSubmitting && session.replyPreview == nil && session.entries.count == 2, "only completed stream publishes pair")
        try a.check(session.chatStatusMessage == .chatStatusConfigured, "completed request restores configured status")
        try a.check(session.entries[1].content == "Hello 世界 🏡" && session.draft.isEmpty, "exact completed text and draft clearing")
        try a.check(e.archive.conversations.count == 1 && e.reopen().conversations[0].turns[0].assistantText == session.entries[1].content, "actual encrypted completion relaunch")
        try a.check(notifications.adds == 1 && notifications.kinds == [.completed] && service.trackedCount == 1, "one completed notification retained by existing service until expiry")
        try a.check(client.counts.complete == 0 && client.counts.stream == 1, "single request no hidden fallback or extraction")
        try a.check(try Data(contentsOf: e.learningFile) == learningBytes, "master-off learning stays unchanged")
        try a.check(session.conversationID == conversationAtStart && publishedConversations == [conversationAtStart],
                    "completion and first message insertion do not change conversation identity")
        session.newConversation()
        let firstEmptyConversation = session.conversationID
        try a.check(firstEmptyConversation != conversationAtStart && session.entries.isEmpty,
                    "new conversation replaces identity after a completed exchange")
        session.newConversation()
        try a.check(session.conversationID != firstEmptyConversation && session.entries.isEmpty,
                    "empty to empty new conversation still changes identity")
        try a.check(publishedConversations == [conversationAtStart, firstEmptyConversation, session.conversationID],
                    "true conversation identity publishes every switch to the observing view")
        return a.count
    }
    static func cancellationFailureAndGeneration() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let client = StreamClient(); let session = e.session(client)
        let notifications = StreamNotifications(); let service = TaskNotificationService(client: notifications, enabled: true)
        await service.refresh(); let bridge = TaskNotificationChatBridge(session: session, service: service); defer { bridge.invalidate() }
        let beforeStart = try start(session, "Cancel before request starts")
        session.cancel(); await beforeStart.value; await service.waitUntilIdle()
        try a.check(client.counts.stream == 0 && client.counts.complete == 0, "cancel before execution does not create a request")
        try a.check(session.replyPreview == nil && ended(session, .cancelled) && session.entries.count == 2 && notifications.adds == 0, "pre-start cancel leaves 已停止。 and no completion")
        let task = try start(session, "Cancelled question")
        try await wait("cancel stream requested") { client.counts.stream == 1 }
        client.emit("Old partial"); try await wait("cancel partial") { session.replyPreview != nil }
        session.cancel(); await task.value; await service.waitUntilIdle()
        try a.check(session.replyPreview == nil && ended(session, .cancelled), "cancel replaces the partial with 已停止。, like Play")
        try a.check(session.draft.isEmpty && e.archive.conversations.first?.turns.last?.outcome == .cancelled && noSavedAnswer(e.archive), "the stopped turn is saved with the conversation, never as an answer")
        try a.check(notifications.adds == 0 && service.trackedCount == 0, "cancel cannot become notification completion")
        let newer = try start(session, "New question")
        try a.check(session.replyPreview == nil, "new submitted generation clears old partial")
        try await wait("new stream requested") { client.counts.stream == 2 }
        client.emit("New partial", at: 1); try await wait("new partial") { session.replyPreview?.text == "New partial" }
        try a.check(!client.emit("Late poison", at: 0), "cancelled stream rejects actual late producer yield")
        client.finish(at: 0)
        try a.check(session.replyPreview?.text == "New partial" && session.entries.last?.role == "user", "old generation cannot replace newer preview")
        client.finish(HTTPChatModelError.transportFailure, at: 1); await newer.value; await service.waitUntilIdle()
        try a.check(session.replyPreview == nil && ended(session, .failed) && session.chatError == nil, "failure stays in the conversation as 沒有完成, like Play")
        try a.check(session.draft.isEmpty && e.archive.conversations.first?.turns.last?.outcome == .failed, "the failed turn is saved with its reason")
        try a.check(noSavedAnswer(e.archive) && notifications.adds == 0 && client.counts.complete == 0, "error does not save an answer, notify or retry")
        session.newConversation(); try a.check(session.replyPreview == nil && session.entries.isEmpty, "new conversation starts empty")
        let changed = try start(session, "Change destination")
        try await wait("third stream") { client.counts.stream == 3 }
        client.emit("Old destination", at: 2); try await wait("third partial") { session.replyPreview != nil }
        session.cancel(); await changed.value
        let kept = session.entries.map(\.id)
        session.modelDraft = "new-model"; session.saveSettings()
        try a.check(session.replyPreview == nil && session.entries.map(\.id) == kept && ended(session, .cancelled),
                    "like Play a model change keeps the conversation; no unfinished text carries over")
        try a.check(!client.emit("Late after settings", at: 2), "old stream remains closed after settings change")
        return a.count
    }
    static func boundsFallbackAndSaveFailure() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let client = StreamClient(); let session = e.session(client)
        let task = try start(session, "Bounded text")
        try await wait("bound stream") { client.counts.stream == 1 }
        client.emit("safe"); try await wait("safe prefix") { session.replyPreview != nil }
        client.emit(String(repeating: "界", count: ChatReplyPreview.maximumUTF8Bytes / 3 + 1)); await task.value
        try a.check(session.replyPreview == nil && ended(session, .failed), "UTF8 overflow ends the turn as 沒有完成")
        try a.check(!(session.entries.last?.content.contains("界界") ?? true) && noSavedAnswer(e.archive) && session.draft.isEmpty, "the oversized text is never shown or saved")
        let empty = try start(session, "Empty text")
        try await wait("empty stream") { client.counts.stream == 2 }; client.finish(at: 1); await empty.value
        try a.check(session.replyPreview == nil && ended(session, .failed) && session.entries.last?.content == "模型回傳空白內容，請重試。"
                    && session.chatError == nil, "an empty stream ends as 沒有完成, not an answer")
        try a.check(client.counts.complete == 0, "no automatic HTTP fallback after stream errors")
        let fallback = e.session(CompleteOnlyClient()); await (try start(fallback, "Non-stream adapter")).value
        try a.check(fallback.entries.count == 2 && fallback.replyPreview == nil, "non-stream capability keeps existing complete path")
        let broken = try StreamEnvironment(); defer { broken.close() }
        try FileManager.default.createDirectory(at: broken.archiveFile, withIntermediateDirectories: true)
        let deliveredClient = StreamClient(); let delivered = broken.session(deliveredClient)
        let delivery = try start(delivered, "Completed but disk failed")
        try await wait("delivery stream") { deliveredClient.counts.stream == 1 }
        deliveredClient.emit("Complete answer"); deliveredClient.finish(); await delivery.value
        try a.check(delivered.entries.count == 2 && delivered.replyPreview == nil && delivered.archiveNotice != nil, "disk failure preserves completed displayed answer")
        try a.check(broken.archive.conversations.isEmpty && delivered.canRetryArchiveSave, "failed save remains distinguishable")
        let ids = delivered.entries.map(\.id)
        try FileManager.default.removeItem(at: broken.archiveFile); delivered.retryArchiveSave()
        try a.check(delivered.archiveNotice == nil && broken.reopen().conversations.count == 1 && delivered.entries.map(\.id) == ids, "save retry retains completed pair IDs")
        try a.check(deliveredClient.counts.stream == 1 && deliveredClient.counts.complete == 0, "save retry cannot issue model request")
        return a.count
    }
    static func restoreCancelsPreview() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let seed = e.session(CompleteOnlyClient()); await (try start(seed, "Saved question")).value
        let row = e.archive.conversations[0]
        let client = StreamClient(); let session = e.session(client)
        let task = try start(session, "Unfinished unrelated question")
        try await wait("restore stream") { client.counts.stream == 1 }
        client.emit("Unfinished"); try await wait("restore partial") { session.replyPreview != nil }
        try a.check(session.openConversation(id: row.id), "explicit restore cancels active request")
        await task.value
        try a.check(session.replyPreview == nil && !session.isSubmitting && session.entries.map(\.id) == [row.turns[0].userID,row.turns[0].assistantID], "restore exposes only saved completed pair")
        try a.check(!client.emit("Late after restore"), "late stream cannot enter restored conversation")
        client.finish()
        let after = e.reopen().state.conversations
        try a.check(after.count == 2 && after.first { $0.id == row.id } == row
                    && after.contains { $0.id != row.id && $0.turns.map(\.outcome) == [.cancelled]
                        && $0.turns[0].userText == "Unfinished unrelated question" },
                    "restore keeps the saved row; the interrupted question stays as 已停止。, never its partial")
        try a.check(client.counts.complete == 0 && client.counts.stream == 1 && session.profileReceipt == nil && session.memoryReceipt == nil, "restore creates no calls or learning changes")
        return a.count
    }
    static func structuredToolsApplyDirectly() async throws -> Int {
        var a = Assertions()
        #if DEBUG
        a.count += try await nativeStreamingFixture()
        #endif
        do {
            // Like the Play build, profile_edit applies with no review sheet.
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let proposal = #"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#
            let client = CompleteSequenceClient([proposal, #"{"action":"finish","answer":"Saved profile."}"#]); let session = e.session(client)
            let task = try start(session, "Please remember that I prefer jasmine tea")
            await task.value
            try a.check(session.profileReceipt?.applied == true && e.learning.profile.snapshot().entries.map(\.text) == ["I prefer jasmine tea"],
                        "profile_edit applies without a review")
            try a.check(session.entries.count == 2 && session.entries[1].content == "Saved profile." && e.archive.conversations.count == 1,
                        "the model continues to its final answer after its own edit")
            try a.check(session.replyPreview == nil && client.counts.stream == 0 && client.counts.complete == 2, "structured flow uses unchanged bounded complete requests")
        }
        do {
            // Like the Play build, the selected tool runs with no approval card.
            let e = try StreamEnvironment(); defer { e.close() }
            let server = StreamMCP(); let connection = MCPSession(repository: StreamEndpoint(), clientFactory: { _ in server })
            connection.connect(); try await wait("actual MCP discovery") { !connection.isBusy }
            connection.selectTool("synthetic_read", enabled: true)
            try a.check(connection.canUseInConversation, "real selected MCP catalog")
            let client = CompleteSequenceClient([#"{"action":"call_tool","name":"synthetic_read","arguments":{}}"#, #"{"action":"finish","answer":"Verified tool result."}"#])
            let session = e.session(client); session.usesMCP = true
            let task = try start(session, "Read selected tool", mcp: connection)
            try a.check(session.chatStatusMessage == .chatStatusMCPWorking && session.replyPreview == nil && unanswered(session),
                        "a running MCP turn shows the working status; its JSON is never shown")
            await task.value
            let after = await server.calls
            try a.check(after == 1 && session.mcpSteps.count == 1 && session.chatError == nil, "the selected tool ran once with no approval")
            try a.check(session.entries.count == 2 && session.replyPreview == nil && client.counts.stream == 0, "MCP finish validator still precedes delivered answer")
        }
        return a.count
    }

    static func structuredStreamingAnswerAndReview() async throws -> Int {
        var a = Assertions()
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            try a.check(e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }, "memory-on fixture persists")
            let client = StreamClient(), session = e.session(client)
            let notifications = StreamNotifications(), service = TaskNotificationService(client: notifications, enabled: true)
            await service.refresh(); let baseline = notifications.operations
            let bridge = TaskNotificationChatBridge(session: session, service: service); defer { bridge.invalidate() }
            let learningBytes = try Data(contentsOf: e.learningFile)
            let task = try start(session, "普通記憶開啟問題")
            try await wait("structured stream requested") { client.counts.stream == 1 }
            client.emit(" { \"action\" : \"finish\" , \"answer\" : \"Hi ")
            try await wait("decoded initial answer") { session.replyPreview?.text == "Hi " }
            client.emit(#"\u4E16\u754C \uD83C"#)
            try await wait("decoded before surrogate") { session.replyPreview?.text == "Hi 世界 " }
            try a.check(session.replyPreview?.text == "Hi 世界 ", "incomplete surrogate is not exposed")
            client.emit(#"\uDFE1\n\"done\""#)
            try await wait("decoded escaped answer") { session.replyPreview?.text == "Hi 世界 🏡\n\"done\"" }
            try a.check(session.replyPreview?.phase == .receiving && unanswered(session) && e.archive.conversations.isEmpty,
                        "memory-on answer is explicitly unfinished")
            let unchangedLearningBytes = try Data(contentsOf: e.learningFile) == learningBytes
            try a.check(session.draft.isEmpty && unchangedLearningBytes,
                        "the input bar emptied at send; the preview cannot extract memory")
            await service.waitUntilIdle()
            try a.check(notifications.operations == baseline && notifications.adds == 0, "preview cannot notify completion")
            client.emit("\"}"); client.finish(); await task.value; await service.waitUntilIdle()
            try a.check(session.entries.map(\.role) == ["user", "assistant"] && session.entries[1].content == "Hi 世界 🏡\n\"done\"",
                        "full command validation publishes exact decoded answer")
            try a.check(session.replyPreview == nil && e.reopen().conversations[0].turns[0].assistantText == session.entries[1].content,
                        "validated result alone enters encrypted archive")
            try a.check(notifications.adds == 1 && client.counts.stream == 1 && client.counts.complete == 0,
                        "one structured model call and one completed notification")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Please remember that I prefer jasmine tea")
            try await wait("structured proposal stream") { client.counts.stream == 1 }
            client.emit(#"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#)
            try a.check(session.replyPreview == nil && unanswered(session) && e.learning.profile.snapshot().entries.isEmpty,
                        "tool JSON and arguments stay hidden before validation")
            client.finish()
            try await wait("streamed post-commit answer") { client.counts.stream == 2 }
            try a.check(session.replyPreview == nil && e.archive.conversations.isEmpty && client.counts.complete == 0,
                        "streamed proposal never falls back to complete")
            try a.check(e.learning.profile.snapshot().entries.count == 1 && unanswered(session),
                        "actual applied receipt remains separate from final answer")
            try a.check(client.emit(#"{"action":"finish","answer":"Saved "# , at: 1), "second stream accepts decoded partial")
            try await wait("post-commit decoded partial") { session.replyPreview?.text == "Saved " }
            try a.check(client.emit(#"profile."}"#, at: 1), "second stream accepts final delta")
            client.finish(at: 1); await task.value
            try a.check(session.entries.last?.content == "Saved profile." && e.reopen().conversations.count == 1,
                        "applied edit and validated streamed finish publish once")
            try a.check(client.counts.stream == 2 && client.counts.complete == 0, "the edit stays within two model calls")
        }
        return a.count
    }

    static func structuredStreamingRejectionsAndCancellation() async throws -> Int {
        var a = Assertions()
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Malformed response")
            try await wait("malformed first request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"safe "#)
            try await wait("first candidate preview") { session.replyPreview?.text == "safe " }
            client.emit(#"\q","arguments":{"secret":"HIDDEN"}}"#)
            try await wait("invalid escape clears preview") { session.replyPreview == nil }
            client.finish()
            try await wait("one bounded format correction") { client.counts.stream == 2 }
            try a.check(unanswered(session) && e.archive.conversations.isEmpty && session.replyPreview == nil,
                        "invalid command neither displays tool bytes nor persists")
            client.emit(#"{"action":"unknown","arguments":{"secret":"HIDDEN"}}"#, at: 1); client.finish(at: 1)
            await task.value
            try a.check(ended(session, .failed) && session.replyPreview == nil && session.chatError == nil
                        && !(session.entries.last?.content.contains("HIDDEN") ?? true),
                        "second malformed command fails closed after one correction")
            try a.check(client.counts.stream == 2 && client.counts.complete == 0, "no hidden transport retry")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Invalid trailing field")
            try await wait("invalid trailing request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"tentative","arguments":{"secret":"HIDDEN"}}"#)
            client.finish()
            try await wait("trailing field repair") { client.counts.stream == 2 }
            try a.check(session.replyPreview == nil && unanswered(session) && e.archive.conversations.isEmpty,
                        "complete validator retracts tentative answer with extra fields")
            client.emit(#"{"action":"finish","answer":"repaired"}"#, at: 1); client.finish(at: 1); await task.value
            try a.check(session.entries.last?.content == "repaired" && client.counts.stream == 2,
                        "validated correction alone publishes final answer")
        }
        for invalid in [
            #"{"action":"finish","answer":"tentative","action":"profile_edit","arguments":{"quote":"TOOL_SECRET"}}"#,
            #"{"action":"finish","answer":"tentative","\u0061ction":"memory_save","arguments":{"content":"TOOL_SECRET"}}"#,
            #"{"action":"finish","answer":"tentative","extra":"TOOL_SECRET"}"#,
            #"{"action":"finish","answer":"tentative"}TRAILING_SECRET"#,
            #"{"action":"finish","answer":"tentative","answer":"TOOL_SECRET"}"#
        ] {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            var observed: [String] = []
            let subscription = session.$replyPreview.sink { if let value = $0 { observed.append(value.text) } }
            defer { subscription.cancel() }
            let task = try start(session, "Reject whole envelope")
            try await wait("strict envelope first stream") { client.counts.stream == 1 }
            client.emit(invalid); client.finish()
            try await wait("strict envelope format correction") { client.counts.stream == 2 }
            try a.check(session.replyPreview == nil && unanswered(session) && e.archive.conversations.isEmpty,
                        "invalid full command retracts speculative preview without saving")
            try a.check(observed.allSatisfy { !$0.contains("TOOL_SECRET") && !$0.contains("TRAILING_SECRET")
                && !$0.contains("arguments") && !$0.contains("action") }, "no tool or wire fields in any preview")
            client.emit(#"{"action":"invalid","arguments":{"secret":"TOOL_SECRET"}}"#, at: 1)
            client.finish(at: 1); await task.value
            try a.check(ended(session, .failed) && noSavedAnswer(e.archive) && session.replyPreview == nil
                        && !(session.entries.last?.content.contains("SECRET") ?? true)
                        && session.chatError == nil && client.counts.stream == 2 && client.counts.complete == 0,
                        "duplicate, extra and trailing bytes never become completed answers")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Remember preference Prefer jasmine tea")
            try await wait("memory proposal stream") { client.counts.stream == 1 }
            client.emit(#"{"action":"memory_save","arguments":{"kind":"preference","content":"Prefer jasmine tea","quote":"Prefer jasmine tea","keywords":["tea"]}}"#)
            client.finish()
            try await wait("memory follow-up stream") { client.counts.stream == 2 }
            try a.check(session.replyPreview == nil && unanswered(session) && e.archive.conversations.isEmpty,
                        "memory tool arguments are never previewed")
            try a.check(e.learning.memory.memories.map(\.content) == ["Prefer jasmine tea"] && session.memoryReceipt != nil,
                        "streamed memory_save applies without a review")
            client.emit(#"{"action":"finish","answer":"Saved memory."}"#, at: 1)
            client.finish(at: 1); await task.value
            try a.check(session.entries.last?.content == "Saved memory." && client.counts.stream == 2,
                        "the reply continues after the model's own memory change")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Truncated response")
            try await wait("truncated request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"partial"#)
            try await wait("truncated partial") { session.replyPreview?.text == "partial" }
            client.finish(HTTPChatModelError.incompleteResponse); await task.value
            try a.check(session.replyPreview == nil && ended(session, .failed),
                        "transport truncation ends the turn as 沒有完成")
            try a.check(noSavedAnswer(e.archive) && session.draft.isEmpty
                        && client.counts.stream == 1 && client.counts.complete == 0,
                        "truncation neither saves an answer nor replays a request")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let notifications = StreamNotifications(), service = TaskNotificationService(client: notifications, enabled: true)
            await service.refresh(); let bridge = TaskNotificationChatBridge(session: session, service: service); defer { bridge.invalidate() }
            let task = try start(session, "Cancel memory-on stream")
            try await wait("cancel structured request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"partial"#)
            try await wait("cancel structured partial") { session.replyPreview?.text == "partial" }
            session.cancel(); await task.value; await service.waitUntilIdle()
            try a.check(session.replyPreview == nil && ended(session, .cancelled) && session.draft.isEmpty,
                        "cancel leaves 已停止。 like Play")
            try a.check(!client.emit(#" late","arguments":{"secret":"HIDDEN"}}"#)
                        && ended(session, .cancelled) && noSavedAnswer(e.archive) && notifications.adds == 0,
                        "late stream cannot publish, execute or notify")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Oversized structured response")
            try await wait("oversize structured request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"safe"#)
            try await wait("oversize initial preview") { session.replyPreview?.text == "safe" }
            client.emit(String(repeating: "x", count: 24 * 1024)); await task.value
            try a.check(session.replyPreview == nil && ended(session, .failed),
                        "24 KiB whole-command bound ends the turn")
            try a.check(noSavedAnswer(e.archive) && client.counts.stream == 1,
                        "oversized command cannot commit or retry")
        }
        return a.count
    }
    #if DEBUG
    private static func nativeStreamingFixture() async throws -> Int {
        var a = Assertions()
        let namespace = UUID().uuidString
        let valid = ["-UITestMode", "-UITestNamespace", namespace, "-UITestChatStreaming"]
        guard let configuration = try UITestChatStreamingConfiguration.resolve(arguments: valid) else { throw Failure(name: "valid streaming gate") }
        try a.check(configuration.namespace.uuidString == namespace, "exact isolated namespace")
        try a.check(try UITestChatStreamingConfiguration.resolve(arguments: []) == nil, "production has no stream fixture")
        try a.check(try UITestChatStreamingConfiguration.resolve(arguments: Array(valid.dropLast())) == nil, "legacy UI fixture stays complete-only")
        var malformed: [[String]] = [
            ["-UITestChatStreaming"], ["-UITestMode", "-UITestChatStreaming"],
            ["-UITestMode", "-UITestNamespace", "bad", "-UITestChatStreaming"],
            ["-UITestMode", "-UITestChatStreaming", "-UITestNamespace"]
        ]
        for extra: [String] in [["-UITestChatStreaming"], ["-UITestMode"], ["-UITestNamespace", namespace],
                               ["-LiveModelUITest"], ["-LiveModelUITestNamespace", namespace], ["-LiveMCPUITest"],
                               ["-UITestMCPFixture"], ["-UITestResetStorage", "-UITestResetStorage"], ["-UITestChatStreaming=true"]] {
            var args = valid; args.append(contentsOf: extra); malformed.append(args)
        }
        var malformedFlag = Array(valid.dropLast()); malformedFlag.append("-UITestChatStreaming=true"); malformed.append(malformedFlag)
        for args in malformed {
            do { _ = try UITestChatStreamingConfiguration.resolve(arguments: args); throw Failure(name: "malformed streaming gate accepted") }
            catch is UITestChatStreamingConfiguration.Invalid { a.count += 1 }
        }
        let client = UITestStreamingChatModelClient(configuration: configuration)
        let e = try StreamEnvironment(); defer { e.close() }
        let session = e.session(client)
        let task = try start(session, "[fixture:stream-complete]")
        try await wait("actual native fixture first delta") { session.replyPreview?.text == "串流測試：第一段" }
        try a.check(session.replyPreview?.phase == .receiving && unanswered(session) && e.archive.conversations.isEmpty, "fixture traverses actual unfinished App path")
        await task.value
        try a.check(session.replyPreview == nil && session.entries.last?.content == "串流測試：第一段；完整回覆。", "bounded fixture terminates as real complete pair")
        try a.check(e.reopen().conversations.count == 1, "fixture only saves on complete")
        session.newConversation()
        let cancelled = try start(session, "[fixture:stream-cancel]")
        try await wait("actual fixture cancellation partial") { session.replyPreview != nil }
        session.cancel(); await cancelled.value
        try a.check(session.replyPreview == nil && ended(session, .cancelled) && session.draft.isEmpty, "fixture cancellation leaves 已停止。 like Play")
        try a.check(e.reopen().conversations.count == 2 && e.reopen().conversations.contains { $0.turns.last?.outcome == .cancelled },
                    "the stopped fixture turn is saved with its conversation")
        for messages in [[ModelMessage(role: "user", content: "unknown prompt")],
                         [ModelMessage(role: "system", content: "structured tool instruction"), ModelMessage(role: "user", content: "[fixture:stream-complete]")]] {
            var deltas = 0
            do {
                for try await _ in client.stream(messages: messages, configuration: try session.modelAccess().configuration, apiKey: "synthetic") { deltas += 1 }
                throw Failure(name: "fixture accepted unknown/structured stream")
            } catch HTTPChatModelError.invalidConfiguration { try a.check(deltas == 0, "fixture cannot stream raw structured instructions") }
        }
        session.newConversation(); _ = e.learning.updatePreferences { $0.useMemory = true }
        let applied = try start(session, "Remember Prefer tea")
        await applied.value
        try a.check(e.learning.profile.snapshot().entries.count == 1
                    && session.entries.last?.content == "個人檔案工具已完成。" && session.replyPreview == nil,
                    "the fixture's profile command applies with no review and reaches its final answer")
        try a.check(e.reopen().conversations.count == 3, "the completed profile answer adds one durable pair")

        session.newConversation()
        // Gate the fixture only in this host integration test, so it can
        // inspect the unfinished state without sleeping for the UI window.
        let gate = FixturePauseGate()
        let gatedClient = UITestStreamingChatModelClient(configuration: configuration,
            sleep: { _ in await gate.pause() })
        let structuredSession = e.session(gatedClient)
        let structured = try start(structuredSession, "[fixture:structured-stream-complete]")
        try await wait("actual structured fixture first delta") { structuredSession.replyPreview?.text == "結構化串流：第一段" }
        try a.check(structuredSession.replyPreview?.phase == .receiving && unanswered(structuredSession)
                    && structuredSession.profileReceipt == nil && e.reopen().conversations.count == 3,
                    "split finish.answer previews without exposing a command or saving an unfinished answer")
        await gate.release()
        await structured.value
        try a.check(structuredSession.replyPreview == nil && structuredSession.entries.last?.content == "結構化串流：第一段；完整回覆。"
                    && e.reopen().conversations.count == 4,
                    "the actual second JSON delta validates and archives only the completed answer")
        return a.count
    }
    #endif
    static func actualHTTPStream() async throws -> Int {
        var a = Assertions()
        let event = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Actual SSE 🏡\"},\"finish_reason\":null}]}\n\n"
        let stop = "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        for mode in ["success", "truncated", "invalid", "cancel"] {
            let suffix = mode == "success" ? stop + "data: [DONE]\n\n" : mode == "invalid" ? "data: not-json\n\n" : ""
            let fixture = ModelProtocolFixture.Scenario(mime: "text/event-stream", chunks: [Data(event.utf8), Data(suffix.utf8)], holdAfterBody: mode == "cancel")
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            let client: any ChatModelClient = HTTPChatModelClient(session: transport); let session = e.session(client)
            var observed: [ChatReplyPreview] = []; var allWereUnfinished = true
            let subscription = session.$replyPreview.sink { value in
                if let value { observed.append(value); allWereUnfinished = allWereUnfinished && Self.unanswered(session) && e.archive.conversations.isEmpty }
            }; defer { subscription.cancel() }
            let task = try start(session, "Actual intercepted SSE request")
            if mode == "cancel" {
                try await wait("actual HTTP partial before cancel") { session.replyPreview?.text == "Actual SSE 🏡" }
                session.cancel()
            }
            await task.value
            try a.check(fixture.requestCount == 1 && fixture.bodyDelivered, "actual HTTP stream made one intercepted request")
            let request = fixture.lastRequest!
            let body = try JSONSerialization.jsonObject(with: interceptedBody(request)) as! [String: Any]
            try a.check(body["stream"] as? Bool == true && request.value(forHTTPHeaderField: "Accept") == "text/event-stream", "real HTTP client selected SSE transport")
            try a.check(observed.first?.text == "Actual SSE 🏡" && allWereUnfinished, "real parser delta displayed only as unfinished")
            if mode == "success" {
                try a.check(session.entries.count == 2 && session.replyPreview == nil && e.reopen().conversations[0].turns[0].assistantText == "Actual SSE 🏡", "verified DONE alone permits actual archive completion")
            } else {
                try a.check(ended(session, mode == "cancel" ? .cancelled : .failed) && noSavedAnswer(e.reopen()) && session.draft.isEmpty,
                            "truncated, invalid or cancelled HTTP never saves an answer")
                try a.check(session.replyPreview == nil && !(session.entries.last?.content.contains("Actual SSE") ?? true),
                            "the partial gives way to 沒有完成 or 已停止。, like Play")
            }
        }
        return a.count
    }
    static func structuredTransportCompatibility() async throws -> Int {
        var a = Assertions()
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient([#"{"action":"finish","answer":"Complete fallback"}"#]), session = e.session(client)
            let task = try start(session, "Explicitly unsupported stream")
            try await wait("unsupported stream request") { client.counts.stream == 1 }
            client.finish(HTTPStreamFallbackError.explicitUnsupported(400)); await task.value
            try a.check(client.counts.stream == 1 && client.counts.complete == 1 &&
                        session.entries.last?.content == "Complete fallback" && e.reopen().conversations.count == 1,
                        "only first zero-content explicit rejection permits one bounded complete fallback")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient([
                #"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#,
                #"{"action":"finish","answer":"Saved through known complete transport"}"#
            ]), session = e.session(client)
            let task = try start(session, "Please remember that I prefer jasmine tea")
            try await wait("first rejected transport") { client.counts.stream == 1 }
            client.finish(HTTPStreamFallbackError.explicitUnsupported(415))
            await task.value
            try a.check(client.counts.stream == 1 && client.counts.complete == 2 &&
                        e.learning.profile.snapshot().entries.count == 1 &&
                        session.entries.last?.content == "Saved through known complete transport",
                        "known complete-only transport carries the applied tool's final within three total calls")
        }
        for failure: Error in [HTTPChatModelError.httpStatus(429), HTTPChatModelError.timedOut,
                               HTTPChatModelError.incompleteResponse, CancellationError(),
                               HTTPStreamFallbackError.explicitUnsupported(501)] {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient([#"{"action":"finish","answer":"MUST NOT RETRY"}"#]), session = e.session(client)
            let task = try start(session, "No automatic retry")
            try await wait("failed stream request") { client.counts.stream == 1 }
            client.finish(failure); await task.value
            try a.check(client.counts.complete == 0 && ended(session, .failed) && noSavedAnswer(e.archive),
                        "rate limit, timeout, incomplete response and cancellation never retry")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient([#"{"action":"finish","answer":"MUST NOT RETRY"}"#]), session = e.session(client)
            let task = try start(session, "Partially delivered unsupported stream")
            try await wait("partial unsupported request") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"partial"#)
            try await wait("partial unsupported preview") { session.replyPreview?.text == "partial" }
            client.finish(HTTPStreamFallbackError.explicitUnsupported(415)); await task.value
            try a.check(client.counts.complete == 0 && session.replyPreview == nil &&
                        ended(session, .failed) && noSavedAnswer(e.archive),
                        "even explicit unsupported error after content cannot replay")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient([#"{"action":"finish","answer":"MUST NOT RETRY"}"#]), session = e.session(client)
            let task = try start(session, "Please remember that I prefer jasmine tea")
            try await wait("tool first stream") { client.counts.stream == 1 }
            client.emit(#"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#)
            client.finish()
            try await wait("post-tool second stream") { client.counts.stream == 2 }
            client.finish(HTTPStreamFallbackError.explicitUnsupported(415), at: 1); await task.value
            try a.check(client.counts.complete == 0 && e.learning.profile.snapshot().entries.count == 1 &&
                        ended(session, .failed) && noSavedAnswer(e.archive),
                        "committed tool receipt survives without replaying failed final model request")
        }
        do {
            let reply = #"{"action":"finish","answer":"Complete JSON from same request"}"#
            let body = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": reply], "finish_reason": "stop"]]])
            let fixture = ModelProtocolFixture.Scenario(chunks: [body])
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Complete-only JSON endpoint")
            await task.value
            let request = fixture.lastRequest!
            let requestBody = try JSONSerialization.jsonObject(with: interceptedBody(request)) as! [String: Any]
            try a.check(fixture.requestCount == 1 && requestBody["stream"] as? Bool == true &&
                        session.entries.last?.content == "Complete JSON from same request" && e.reopen().conversations.count == 1,
                        "HTTP complete JSON returned to stream request uses same response without replay")
        }
        do {
            let errorBody = Data(#"{"error":{"code":"unsupported_parameter","param":"stream"}}"#.utf8)
            let fixture = ModelProtocolFixture.Scenario(status: 400, chunks: [errorBody])
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            let config = ModelConfiguration(baseURL: url, model: "fixture")
            let client = HTTPChatModelClient(session: transport)
            do {
                for try await _ in client.stream(messages: [.init(role: "user", content: "probe")], configuration: config,
                                                apiKey: "synthetic-not-a-key") {}
                throw Failure(name: "explicit HTTP stream rejection was accepted")
            } catch HTTPStreamFallbackError.explicitUnsupported(400) {}
            try a.check(fixture.requestCount == 1 && fixture.bodyDelivered,
                        "only structured HTTP unsupported-stream error is classified for bounded fallback")
        }
        let finalReply = #"{"action":"finish","answer":"Bounded complete answer"}"#
        let completeBody = try JSONSerialization.data(withJSONObject: ["choices": [["message":
            ["role": "assistant", "content": finalReply], "finish_reason": "stop"]]])
        let canary = "PRIVATE_ERROR_CANARY"
        for (status, mime, errorBody) in [
            (400, "application/json", #"{"error":{"code":"unsupported_parameter","param":"stream","message":"PRIVATE_ERROR_CANARY"}}"#),
            (415, "application/json", #"{"error":{"code":"unsupported_value","param":"stream"}}"#),
            (422, "application/json", #"{"error":{"code":"not_supported","param":"stream"}}"#)
        ] {
            let fixture = ModelProtocolFixture.Scenario(status: status, mime: mime, chunks: [Data(errorBody.utf8)],
                followUp: .init(status: 200, mime: "application/json", chunks: [completeBody]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            var displayed: [String] = []
            let subscription = session.$replyPreview.sink { if let value = $0 { displayed.append(value.text) } }
            defer { subscription.cancel() }
            let task = try start(session, "Bounded compatible request")
            await task.value
            let requests = fixture.requestSnapshot
            try a.check(requests.count == 2, "eligible first error uses exactly one complete fallback")
            let streamBody = try JSONSerialization.jsonObject(with: interceptedBody(requests[0])) as! [String: Any]
            let fallbackRequestData = try interceptedBody(requests[1])
            let fallbackBody = try JSONSerialization.jsonObject(with: fallbackRequestData) as! [String: Any]
            let fallbackRequestText = String(decoding: fallbackRequestData, as: UTF8.self)
            try a.check(streamBody["stream"] as? Bool == true && fallbackBody["stream"] as? Bool == false &&
                        (streamBody["messages"] as? [[String: String]]) == (fallbackBody["messages"] as? [[String: String]]),
                        "fallback changes only transport and preserves the exact prompt messages")
            try a.check(session.entries.last?.content == "Bounded complete answer" && e.reopen().conversations.count == 1,
                        "actual HTTP complete fallback still requires validated finish before archive")
            try a.check(e.learning.profile.snapshot().entries.isEmpty && e.learning.memory.memories.isEmpty,
                        "complete fallback cannot silently create local tool effects")
            try a.check(!displayed.contains(where: { $0.contains(canary) }) &&
                        !fallbackRequestText.contains(canary) &&
                        !(session.chatError ?? "").contains(canary),
                        "private error body is absent from preview, next prompt and diagnostic")
        }
        for (status, body) in [(429, #"{"error":{"code":"rate_limit","param":"stream"}}"#),
                               (400, #"{"error":{"code":"invalid_request","param":"stream"}}"#),
                               (400, #"{"error":{"code":"unsupported_parameter","param":"stream","param":"other"}}"#)] {
            let fixture = ModelProtocolFixture.Scenario(status: status, chunks: [Data(body.utf8)])
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let client = HTTPChatModelClient(session: transport)
            do {
                for try await _ in client.stream(messages: [.init(role: "user", content: "probe")],
                                                configuration: ModelConfiguration(baseURL: url, model: "fixture"),
                                                apiKey: "synthetic-not-a-key") {}
                throw Failure(name: "HTTP failure was accepted")
            } catch HTTPChatModelError.httpStatus(let received) {
                try a.check(received == status && fixture.requestCount == 1,
                            "rate limit and generic request error remain terminal without fallback classification")
            }
        }
        for (status, mime, body) in [
            (401, "text/plain", "auth"), (403, "text/plain", "forbidden"),
            (404, "text/plain", "missing"), (429, "text/plain", "limited"),
            (500, "text/plain", "server"),
            (400, "text/plain", "plain rejection " + canary),
            (415, "text/plain", "unsupported media type " + canary),
            (422, "application/json", ""),
            (501, "application/json", #"{"error":{"code":"unsupported_parameter","param":"stream"}}"#),
            (503, "text/plain", "unavailable"),
            (400, "application/json", #"{"error":{"code":"invalid_request","param":"stream"}}"#),
            (400, "application/json", "not-json"),
            (415, "application/json", #"{"error":{"code":"invalid_request","param":"stream"}}"#),
            (422, "application/json", #"{"error":{"code":"invalid_request","param":"stream"}}"#),
            (400, "text/plain", #"{"error":{"code":"unsupported_parameter","param":"other"}}"#),
            (415, "text/html", "<html>not a plain error</html>"),
            (422, "text/plain", "data: possible event"),
            (400, "text/plain", String(repeating: "x", count: 2049))
        ] {
            let fixture = ModelProtocolFixture.Scenario(status: status, mime: mime, chunks: [Data(body.utf8)],
                followUp: .init(status: 200, mime: "application/json", chunks: [completeBody]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Terminal HTTP rejection")
            await task.value
            try a.check(fixture.requestCount == 1 && ended(session, .failed) && noSavedAnswer(e.archive) &&
                        !session.entries.contains { $0.content.contains(canary) } && !(session.chatError ?? "").contains(canary),
                        "excluded status or structured body never sends a complete fallback or private error text")
        }
        do {
            let fixture = ModelProtocolFixture.Scenario(status: 415, chunks: [Data(#"{"error":{"code":"unsupported_parameter","param":"stream"}}"#.utf8)],
                holdAfterBody: true, followUp: .init(status: 200, mime: "application/json", chunks: [completeBody]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Cancel before error body completes")
            try await wait("first HTTP error body is held") { fixture.requestCount == 1 && fixture.bodyDelivered }
            session.cancel(); await task.value
            try a.check(fixture.requestCount == 1 && ended(session, .cancelled) && noSavedAnswer(e.archive),
                        "cancellation while reading eligibility body never starts fallback")
        }
        do {
            let fixture = ModelProtocolFixture.Scenario(status: 415, chunks: [Data(#"{"error":{"code":"unsupported_parameter","param":"stream"}}"#.utf8)],
                followUp: .init(status: 200, mime: "application/json", chunks: [completeBody], holdAfterBody: true))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Cancel complete fallback")
            try await wait("complete fallback request is held") { fixture.requestCount == 2 }
            session.cancel(); await task.value
            try a.check(fixture.requestCount == 2 && ended(session, .cancelled) && noSavedAnswer(e.archive) &&
                        session.draft.isEmpty,
                        "cancelling the sole complete fallback leaves 已停止。 and sends no third request")
        }
        return a.count
    }
    /// Like the Play build, learning data changed while a reply is pending
    /// never stops it: the reply still publishes.
    static func structuredRepliesSurviveLearningChanges() async throws -> Int {
        var a = Assertions()
        let explicitError = Data(#"{"error":{"code":"unsupported_parameter","param":"stream"}}"#.utf8)
        let reply = #"{"action":"finish","answer":"Published after the change"}"#
        let completeBody = try JSONSerialization.data(withJSONObject: ["choices": [["message":
            ["role": "assistant", "content": reply], "finish_reason": "stop"]]])
        for kind in ["switch", "delete-memory", "delete-profile", "failed-write"] {
            let fixture = ModelProtocolFixture.Scenario(status: 400, chunks: [explicitError], holdAfterBody: true,
                followUp: .init(status: 200, mime: "application/json", chunks: [completeBody]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            guard e.learning.updatePreferences({ $0.useMemory = true; $0.autoRemember = false }) else {
                throw Failure(name: "revocation fixture preferences")
            }
            if kind == "delete-memory" {
                guard e.learning.mutateMemory({ _ = try $0.add(kind: .preference, content: "Prefer jasmine tea") }) else {
                    throw Failure(name: "revocation fixture memory")
                }
            } else if kind == "delete-profile" {
                guard e.learning.mutateProfile({ _ = try $0.add(text: "I prefer jasmine tea.") }) else {
                    throw Failure(name: "revocation fixture profile")
                }
            }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Do you remember my jasmine tea preference?")
            try await wait("initial structured POST is awaiting completion") {
                fixture.requestCount == 1 && fixture.bodyDelivered
            }
            // URLProtocol delivery and the URLSession dispatch callback run on
            // different executors. Body delivery alone does not prove that the
            // host's dispatch lease has already been released.
            try await wait("initial structured dispatch lease released") {
                guard let lease = try? e.learning.acquireCurrentReferenceLease() else { return false }
                lease.release(); return true
            }
            let generation = e.learning.generation
            switch kind {
            case "switch":
                try a.check(e.learning.updatePreferences({ $0.useMemory = false }), "master switch persists")
                try a.check(e.learning.generation != generation, "master switch revokes generation")
            case "delete-memory":
                let id = e.learning.memory.memories[0].id
                try a.check(e.learning.mutateMemory({ _ = try $0.delete(id: id) }), "memory deletion persists")
                try a.check(e.learning.generation != generation && e.learning.memory.memories.isEmpty,
                            "memory deletion revokes captured context")
            case "delete-profile":
                try a.check(e.learning.mutateProfile({ try $0.delete(segment: "jasmine tea") }),
                            "profile deletion persists")
                try a.check(e.learning.generation == generation && e.learning.profile.snapshot().entries.isEmpty,
                            "profile deletion persists without generation rotation")
            default:
                let old = e.learning.memory
                try a.check(!e.learning.mutateMemory({ _ in throw Failure(name: "fixture write failed") }),
                            "failed mutation is rejected")
                try a.check(e.learning.generation != generation && e.learning.memory == old,
                            "failed mutation leaves stored memory unchanged")
            }
            fixture.releaseHeldResponses()
            await task.value
            try a.check(fixture.requestCount == 2 && session.entries.last?.content == "Published after the change" &&
                        e.reopen().conversations.count == 1 && session.draft.isEmpty && !session.isSubmitting,
                        "the pending reply still sends its one complete fallback and publishes (" + kind + ")")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Do you remember jasmine tea?")
            try await wait("ordinary structured reply begins") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"ANSWER AFTER SWITCH"}"#)
            _ = e.learning.updatePreferences { $0.useMemory = false }
            client.finish(); await task.value
            try a.check(client.counts.stream == 1 && client.counts.complete == 0 && session.entries.last?.content == "ANSWER AFTER SWITCH" &&
                        e.archive.conversations.count == 1 && session.replyPreview == nil,
                        "an ordinary finish publishes after the memory switch changes")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Format correction continues after a change")
            try await wait("initial correction candidate") { client.counts.stream == 1 }
            client.emit(#"{"action":"finish","answer":"bad","extra":true}"#)
            _ = e.learning.updatePreferences { $0.useMemory = false }
            client.finish()
            try await wait("format correction request") { client.counts.stream == 2 }
            client.emit(#"{"action":"finish","answer":"Corrected"}"#, at: 1)
            client.finish(at: 1); await task.value
            try a.check(client.counts.stream == 2 && client.counts.complete == 0 && session.entries.last?.content == "Corrected",
                        "format correction still sends its one second request after a change")
        }
        do {
            let e = try StreamEnvironment(); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Please remember that I prefer jasmine tea")
            try await wait("profile proposal starts") { client.counts.stream == 1 }
            client.emit(#"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#)
            _ = e.learning.updatePreferences { $0.useMemory = false }
            client.finish(); await task.value
            try a.check(client.counts.stream == 1 && session.profileReceipt == nil &&
                        e.learning.profile.snapshot().entries.isEmpty && unanswered(session),
                        "a profile proposal after memory is switched off is not applied")
        }
        do {
            // Exercise the flow boundary after a trusted tool receipt, where a
            // second advance would otherwise start the final model request.
            let first = #"{"action":"profile_edit","arguments":{"op":"add","text":"I prefer jasmine tea","quote":"Please remember that I prefer jasmine tea"}}"#
            let client = CompleteSequenceClient([first, reply])
            let flow = try UserProfileChatFlow(messages: [.init(role: "user", content: "Please remember that I prefer jasmine tea")])
            let config = ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture")
            var valid = true
            let step = try await flow.advance(client: client, configuration: config, apiKey: "synthetic", validateState: {
                if !valid { throw UserProfileToolError.staleRevision }
            })
            guard case .proposedEdit = step else { throw Failure(name: "trusted proposal step") }
            try flow.recordCommitted(entryID: UUID())
            valid = false
            do {
                _ = try await flow.advance(client: client, configuration: config, apiKey: "synthetic", validateState: {
                    if !valid { throw UserProfileToolError.staleRevision }
                })
                throw Failure(name: "revoked post-receipt flow started")
            } catch UserProfileToolError.staleRevision {}
            try a.check(client.counts.complete == 1 && flow.didCommit,
                        "post-commit final request is gated while the persisted receipt remains true")
        }
        return a.count
    }

    static func unfinishedAndUnsavedBranchFences() async throws -> Int {
        var a = Assertions()
        let e = try StreamEnvironment(); defer { e.close() }
        let client = StreamClient(), session = e.session(client)
        let first = try start(session, "Saved question")
        try await wait("saved stream begins") { client.counts.stream == 1 }
        client.emit("Saved answer"); client.finish(); await first.value
        guard let saved = e.archive.state.conversations.first else { throw Failure(name: "saved branch source") }
        let original = e.archive.state
        let running = try start(session, "Unfinished question")
        try await wait("second stream begins") { client.counts.stream == 2 }
        client.emit("Unfinished preview", at: 1)
        try await wait("preview reaches session") { session.replyPreview?.text == "Unfinished preview" }
        try a.check(!session.selectQuote(messageID: session.replyPreview!.id, expectedContent: "Unfinished preview", in: saved.id),
                    "a real unfinished preview cannot be quoted as an archived message")
        do {
            _ = try session.prepareBranch(source: saved, assistantID: saved.turns[0].assistantID, title: "Branch")
            throw Failure(name: "running preview allowed a branch")
        } catch ConversationBranchError.blocked {}
        try a.check(session.replyPreview?.text == "Unfinished preview" && e.archive.state == original,
                    "busy branch rejection preserves the real preview and archive")
        session.cancel(); client.finish(at: 1); await running.value
        guard let stopped = e.archive.state.conversations.first(where: { $0.id == saved.id }) else {
            throw Failure(name: "stopped conversation")
        }
        try a.check(session.replyPreview == nil && ended(session, .cancelled) && stopped.turns.count == 2
                    && stopped.turns[1].outcome == .cancelled && stopped.turns[0] == saved.turns[0],
                    "like Play the stopped turn is saved after the answer before it")
        let targets = session.messageActionTargets
        try a.check(targets.replies == [saved.turns[0].assistantID] && targets.questions.contains(stopped.turns[1].userID),
                    "從這裡分支 is on answers only; 從這裡重新問 stays on the stopped question")
        do {
            _ = try session.prepareBranch(source: saved, assistantID: saved.turns[0].assistantID, title: "Branch")
            throw Failure(name: "a superseded source allowed a branch")
        } catch ConversationBranchError.staleSource {}
        let plan = try session.prepareBranch(source: stopped, assistantID: stopped.turns[1].assistantID, title: "Branch")
        try a.check(plan.branch.turns.map(\.outcome) == [nil, .cancelled] && plan.branch.turns[1].assistantText == stopped.turns[1].assistantText,
                    "a branch through a stopped turn keeps it stopped, like the Play build's copy")

        let other = try StreamEnvironment(); defer { other.close() }
        let nextClient = StreamClient(), next = other.session(nextClient)
        let seed = try start(next, "Earlier question")
        try await wait("earlier stream begins") { nextClient.counts.stream == 1 }
        nextClient.emit("Earlier answer"); nextClient.finish(); await seed.value
        let prior = other.archive.state.conversations[0]
        let before = try Data(contentsOf: other.archiveFile)
        let backup = other.root.appendingPathComponent("before-unsaved-branch")
        try FileManager.default.moveItem(at: other.archiveFile, to: backup)
        try FileManager.default.createDirectory(at: other.archiveFile, withIntermediateDirectories: false)
        let failedSave = try start(next, "Completed but unsaved")
        try await wait("unsaved stream begins") { nextClient.counts.stream == 2 }
        nextClient.emit("Actual completed answer", at: 1); nextClient.finish(at: 1); await failedSave.value
        try a.check(next.canRetryArchiveSave && next.entries.count == 4 && next.archiveNotice != nil,
                    "real completed result remains visible and retryable after write failure")
        do {
            _ = try next.prepareBranch(source: prior, assistantID: prior.turns[0].assistantID, title: "Branch")
            throw Failure(name: "unsaved answer allowed a branch")
        } catch ConversationBranchError.unfinishedTurn {}
        try a.check(next.canRetryArchiveSave && other.archive.state.conversations == [prior]
                    && (try Data(contentsOf: backup)) == before, "unsaved branch rejection preserves retry and prior ciphertext")
        other.archive.reload()
        try a.check(!other.archive.available && next.canRetryArchiveSave,
                    "a failed reload cannot discard the completed pending answer")
        try FileManager.default.removeItem(at: other.archiveFile)
        try FileManager.default.moveItem(at: backup, to: other.archiveFile)
        next.retryArchiveSave()
        let reopened = other.reopen()
        if next.canRetryArchiveSave || !reopened.available || reopened.state.conversations.first?.turns.count != 2 {
            throw Failure(name: "retry diagnostic: retry=\(next.canRetryArchiveSave) available=\(reopened.available) rows=\(reopened.state.conversations.count) turns=\(reopened.state.conversations.first?.turns.count ?? -1) notice=\(next.archiveNotice ?? "nil")")
        }
        try a.check(!next.canRetryArchiveSave && reopened.state.conversations[0].turns.count == 2,
                    "retry restores the actual completed answer after failed write")
        return a.count
    }

    /// App Review 5.1.2(i): a main model set up before the consent existed
    /// asks before the first send. Declining keeps the draft and sends
    /// nothing; agreeing records the consent and sends. Until then work
    /// outside the chat cannot get the model either.
    static func consentBeforeFirstSend() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let suite = "woow.stream.consent." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(name: "isolated consent defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ModelSettingsRepository(defaults: defaults, credentials: StreamCredentials())
        // The single form's save records no consent, like a setting from before it.
        _ = try repository.save(baseURL: "https://consent.example.invalid/v1", model: "fixture", newKey: "synthetic-not-a-key")
        let client = StreamClient()
        let session = ChatSession(learning: e.learning, repository: repository, client: client, archive: e.archive)
        try a.check(session.mainNeedsConsent && session.pendingSendConsent == nil, "a main model never agreed to")
        let shared = ModelSharedContent.allCases.map(\.text.key)
        try a.check(shared.count == 10 && Set(shared).count == 10 && shared.allSatisfy { $0.hasPrefix("consent.item.") }
                    && shared.contains("consent.item.memoryOrganizing") && shared.contains("consent.item.researchJudgment"),
                    "the consent's one list names each kind of content once")
        var refused = false
        do { _ = try session.modelAccess() } catch ModelSettingsError.consentRequired { refused = true }
        try a.check(refused, "work outside the chat cannot get the model before the consent")
        session.draft = "Hello after the update"
        session.attemptSend()
        try a.check(session.pendingSendConsent?.purpose == .send && session.pendingSendConsent?.host == "consent.example.invalid"
                    && !session.isSubmitting && session.capturedArchiveRequest == nil && client.counts == (0, 0),
                    "the first send asks first and starts nothing")
        session.resolveSendConsent(agreed: false)
        try a.check(session.pendingSendConsent == nil && session.chatErrorText == .chatConsentDeclined(provider: "consent.example.invalid")
                    && session.draft == "Hello after the update" && !session.isSubmitting && client.counts == (0, 0)
                    && (try repository.document())?.consent == nil, "declining sends nothing, keeps the draft and records nothing")
        session.attemptSend()
        try a.check(session.pendingSendConsent != nil && client.counts == (0, 0), "the next send asks again")
        session.resolveSendConsent(agreed: true)
        try a.check(session.pendingSendConsent == nil && !session.mainNeedsConsent && session.isSubmitting
                    && (try repository.document())?.consent?.providerID == session.savedSettings?.providerID,
                    "agreeing records the consent and sends")
        session.cancel()
        try a.check(try session.modelAccess().identity.target.model == "fixture", "afterwards other work gets the model")
        return a.count
    }

    /// Android parity: a typed draft is tappable before a model exists, and the
    /// tap shows 還不能開始任務 instead of doing nothing or starting a request.
    static func sendBlockerExplainsWithoutStarting() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let suite = "woow.stream.blocker." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(name: "isolated blocker defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ModelSettingsRepository(defaults: defaults, credentials: StreamCredentials())
        // StreamClient without replies throws on any model request.
        let session = ChatSession(learning: e.learning, repository: repository, client: StreamClient(), archive: e.archive)
        try a.check(!session.hasStoredKey && !session.canAttemptSend, "an empty draft offers nothing to send")
        session.draft = "Keep this draft"
        try a.check(session.canAttemptSend && !session.canSend, "a typed draft is tappable before a model is set up")
        session.attemptSend()
        try a.check(session.shownSendBlocker == .noModel && !session.isSubmitting && session.capturedArchiveRequest == nil
                    && session.entries.isEmpty && session.draft == "Keep this draft" && session.chatError == nil,
                    "a send without a model shows the card, keeps the draft and starts no request")
        session.dismissSendBlocker()
        try a.check(session.shownSendBlocker == nil && session.draft == "Keep this draft", "知道了 dismisses only the card")
        session.attemptSend()
        session.baseURLDraft = "https://stream.example.invalid/v1"
        session.modelDraft = "fixture"
        session.keyDraft = "synthetic-not-a-key"
        session.saveSettings()
        try a.check(session.hasStoredKey && session.shownSendBlocker == nil && session.draft == "Keep this draft",
                    "saving a model clears the card and keeps the draft")
        session.removeSettings()
        session.attemptSend()
        try a.check(session.shownSendBlocker == .noModel && session.capturedArchiveRequest == nil,
                    "removing the model blocks the next send again")
        session.newConversation()
        try a.check(session.shownSendBlocker == nil && session.draft == "Keep this draft", "a new conversation clears the card")
        return a.count
    }

    /// Android parity (ModelErrorCopy.failure): a plain request's model failure
    /// says 呼叫模型失敗：<reason> from its HTTP status alone, under the turn's
    /// 沒有完成 like the Play build; failures it cannot name keep the generic message.
    static func modelFailuresUsePlayWording() async throws -> Int {
        var a = Assertions(); let e = try StreamEnvironment(); defer { e.close() }
        let cases: [(HTTPChatModelError, AppText?)] = [
            (.httpStatus(401), .chatModelFailedAuth), (.httpStatus(403), .chatModelFailedAuth),
            (.httpStatus(402), .chatModelFailedQuota), (.httpStatus(404), .chatModelFailedNotFound),
            (.httpStatus(429), .chatModelFailedRateLimited), (.httpStatus(503), .chatModelFailedServer(status: 503)),
            (.httpStatus(400), .chatModelFailedStatus(status: 400)), (.transportFailure, .chatModelFailedNetwork),
            (.incompleteResponse, .chatModelFailedStreamCut), (.invalidResponse, .chatModelFailedUnreadable),
            (.timedOut, nil), (.redirectRejected, nil)]
        let chinese = AppLocalizer(language: .traditionalChinese)
        for (error, expected) in cases {
            let session = e.session(FailingClient(error: error))
            session.draft = "Ask once"
            session.send()
            guard let task = session.capturedArchiveRequest else { throw Failure(name: "model failure request \(error)") }
            await task.value
            let reason = expected.map(chinese.text) ?? "傳送失敗。請檢查模型設定或網路後重試。"
            try a.check(ended(session, .failed) && session.entries.last?.content == reason && session.chatError == nil
                        && !session.isSubmitting && session.draft.isEmpty && session.entries.first?.content == "Ask once",
                        "\(error) is named like Android, or keeps the generic message, as the reason under 沒有完成")
        }
        try a.check(chinese.text(.chatModelFailedRateLimited) == "呼叫模型失敗：請求太頻繁，請稍後再試。"
                    && chinese.text(.chatModelFailedServer(status: 500)) == "呼叫模型失敗：伺服器端出錯（HTTP 500）。請稍後再試。",
                    "the reason keeps the Play sentence in Traditional Chinese")
        let english = e.session(FailingClient(error: .httpStatus(429)))
        english.interfaceLanguage = { .english }
        english.draft = "Ask in English"; english.send()
        if let task = english.capturedArchiveRequest { await task.value }
        try a.check(ended(english, .failed) && english.entries.last?.content == AppLocalizer(language: .english).text(.chatModelFailedRateLimited),
                    "an English interface keeps the reason in English")
        english.newConversation()
        try a.check(english.entries.isEmpty && english.chatError == nil && english.chatErrorText == nil, "a new conversation starts clean")
        return a.count
    }

    /// An endpoint that streams but refuses stream_options: a plain request is
    /// resent once without it before any text, later turns skip it, and the
    /// profile flow falls back to one complete request. Never a third request.
    static func usageOptionFallback() async throws -> Int {
        var a = Assertions()
        let canary = "PRIVATE_ERROR_CANARY"
        let refusal = Data(#"{"error":{"code":"unsupported_parameter","param":"stream_options","message":"PRIVATE_ERROR_CANARY"}}"#.utf8)
        let event = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Resent SSE\"},\"finish_reason\":null}]}\n\n"
        let stop = "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        func body(_ request: URLRequest?) throws -> [String: Any] {
            guard let request, let value = try JSONSerialization.jsonObject(with: interceptedBody(request)) as? [String: Any] else {
                throw Failure(name: "intercepted body is not a JSON object")
            }
            return value
        }
        func asksUsage(_ request: URLRequest?) throws -> Bool {
            try (body(request)["stream_options"] as? [String: Bool]) == ["include_usage": true]
        }
        do {
            let fixture = ModelProtocolFixture.Scenario(status: 400, chunks: [refusal],
                followUp: .init(status: 200, mime: "text/event-stream", chunks: [Data((event + stop).utf8)]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            let session = e.session(HTTPChatModelClient(session: transport))
            var displayed: [String] = []
            let subscription = session.$replyPreview.sink { if let value = $0 { displayed.append(value.text) } }
            defer { subscription.cancel() }
            await (try start(session, "Usage option refused")).value
            let requests = fixture.requestSnapshot
            try a.check(requests.count == 2, "a refused usage option is resent exactly once")
            let first = try body(requests[0]), second = try body(requests[1])
            try a.check(try asksUsage(requests[0]) && second["stream_options"] == nil && second["stream"] as? Bool == true &&
                        (first["messages"] as? [[String: String]]) == (second["messages"] as? [[String: String]]),
                        "the resend leaves out only the usage option")
            let sent = first["messages"] as? [[String: String]] ?? []
            let lead = sent.first?["content"] ?? ""
            try a.check(sent.count == 2 && sent[0]["role"] == "system" &&
                        (lead == AISafetyRules.prompt || lead.hasSuffix("\n\n" + AISafetyRules.prompt)) &&
                        sent[1] == ["role": "user", "content": "Usage option refused"],
                        "plain chat sends one system message ending with the identity line and the Play safety rules")
            try a.check(session.entries.last?.content == "Resent SSE" && session.chatError == nil && displayed == ["Resent SSE"] &&
                        e.reopen().conversations.count == 1, "the resent stream previews, completes and saves the turn")
            try a.check(!String(decoding: try interceptedBody(requests[1]), as: UTF8.self).contains(canary),
                        "the refusal body never enters the resend")
            await (try start(session, "Next question")).value
            try a.check(fixture.requestCount == 3 && (try body(fixture.lastRequest))["stream_options"] == nil &&
                        session.entries.count == 4, "later turns on the same endpoint and model skip the option")
        }
        do {
            let finish = #"{"action":"finish","answer":"Complete after a refused option"}"#
            let completeBody = try JSONSerialization.data(withJSONObject: ["choices": [["message":
                ["role": "assistant", "content": finish], "finish_reason": "stop"]]])
            let fixture = ModelProtocolFixture.Scenario(status: 422, chunks: [refusal],
                followUp: .init(status: 200, mime: "application/json", chunks: [completeBody]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url) }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            _ = e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }
            let session = e.session(HTTPChatModelClient(session: transport))
            await (try start(session, "Profile flow with a refused option")).value
            let requests = fixture.requestSnapshot
            try a.check(requests.count == 2 && (try asksUsage(requests[0])) && (try body(requests[1]))["stream"] as? Bool == false &&
                        (try body(requests[1]))["stream_options"] == nil, "the profile flow falls back to one complete request")
            let instructions = ((try body(requests[0]))["messages"] as? [[String: String]])?.first
            try a.check(instructions?["role"] == "system" && instructions?["content"]?.hasPrefix(UserProfileChatFlow.instructions) == true &&
                        UserProfileChatFlow.instructions.hasSuffix("\n\n" + AISafetyRules.prompt),
                        "the profile flow's instructions carry the identity line and the Play safety rules")
            try a.check(session.entries.last?.content == "Complete after a refused option" && e.reopen().conversations.count == 1 &&
                        e.learning.profile.snapshot().entries.isEmpty, "the fallback answer is still validated before it is saved")
        }
        do {
            let fixture = ModelProtocolFixture.Scenario(status: 400, chunks: [refusal], holdAfterBody: true,
                followUp: .init(status: 200, mime: "text/event-stream", chunks: [Data((event + stop).utf8)]))
            let url = ModelProtocolFixture.register(fixture); defer { ModelProtocolFixture.remove(url); fixture.releaseHeldResponses() }
            let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
            let e = try StreamEnvironment(baseURL: url); defer { e.close() }
            let session = e.session(HTTPChatModelClient(session: transport))
            let task = try start(session, "Cancel while the refusal is read")
            try await wait("refusal body held") { fixture.requestCount == 1 && fixture.bodyDelivered }
            session.cancel(); await task.value
            try a.check(fixture.requestCount == 1 && ended(session, .cancelled) && session.draft.isEmpty,
                        "cancelling while the refusal is read never resends")
        }
        for (label, failure, emitFirst) in [("Refusal after text", HTTPStreamFallbackError.usageOptionUnsupported(400), true),
                                            ("Stream refusal on a plain request", HTTPStreamFallbackError.explicitUnsupported(400), false)] {
            let e = try StreamEnvironment(); defer { e.close() }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, label)
            try await wait("\(label) stream") { client.counts.stream == 1 }
            if emitFirst {
                client.emit("partial"); try await wait("\(label) partial") { session.replyPreview?.text == "partial" }
            }
            client.finish(failure); await task.value
            try a.check(client.counts.stream == 1 && client.counts.complete == 0 && ended(session, .failed) &&
                        session.chatError == nil && session.draft.isEmpty,
                        "only an untouched usage-option refusal is resent: \(label)")
        }
        for cancel in [false, true] {
            let e = try StreamEnvironment(); defer { e.close() }
            let client = StreamClient(), session = e.session(client)
            let task = try start(session, "Refused twice")
            try await wait("first refused stream") { client.counts.stream == 1 }
            client.finish(HTTPStreamFallbackError.usageOptionUnsupported(400))
            try await wait("the single resend") { client.counts.stream == 2 }
            if cancel { session.cancel() } else { client.finish(HTTPStreamFallbackError.usageOptionUnsupported(400), at: 1) }
            await task.value
            try a.check(client.counts.stream == 2 && client.counts.complete == 0 && ended(session, cancel ? .cancelled : .failed) &&
                        session.draft.isEmpty && noSavedAnswer(e.archive),
                        cancel ? "cancelling the resend sends nothing more" : "a second refusal is not resent")
        }
        return a.count
    }

}
#if CHAT_STREAM_APP_STANDALONE
@main enum ChatStreamingMain {
    @MainActor static func main() async {
        do {
            var groups = try await [ChatStreamingChecks.incrementalCompletion(), ChatStreamingChecks.cancellationFailureAndGeneration(),
                ChatStreamingChecks.boundsFallbackAndSaveFailure(), ChatStreamingChecks.restoreCancelsPreview(),
                ChatStreamingChecks.structuredToolsApplyDirectly(), ChatStreamingChecks.structuredStreamingAnswerAndReview(),
                ChatStreamingChecks.structuredStreamingRejectionsAndCancellation(), ChatStreamingChecks.actualHTTPStream(),
                ChatStreamingChecks.structuredTransportCompatibility(), ChatStreamingChecks.structuredRepliesSurviveLearningChanges(),
                ChatStreamingChecks.unfinishedAndUnsavedBranchFences(), ChatStreamingChecks.sendBlockerExplainsWithoutStarting(),
                ChatStreamingChecks.modelFailuresUsePlayWording(), ChatStreamingChecks.usageOptionFallback(),
                ChatStreamingChecks.consentBeforeFirstSend()]
            #if DEBUG
            groups.append(try await ChatStreamingChecks.fixtureInteractionWindows())
            #endif
            print("{\"groups\":\(groups.count),\"assertions\":\(groups.reduce(0,+)),\"group_counts\":\(groups)}")
        } catch { print("STREAM_APP_FAILURE: \(error)"); exit(1) }
    }
}
#else
final class ChatStreamingAppTests: XCTestCase {
    #if DEBUG
    @MainActor func testFixtureInteractionWindows() async throws {
        let n = try await ChatStreamingChecks.fixtureInteractionWindows(); XCTAssertEqual(n, 8)
    }
    #endif
    @MainActor func testUnfinishedAndUnsavedBranchFences() async throws { let n = try await ChatStreamingChecks.unfinishedAndUnsavedBranchFences(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testModelFailuresUsePlayWording() async throws { let n = try await ChatStreamingChecks.modelFailuresUsePlayWording(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testUsageOptionFallback() async throws { let n = try await ChatStreamingChecks.usageOptionFallback(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testSendBlockerExplainsWithoutStarting() async throws { let n = try await ChatStreamingChecks.sendBlockerExplainsWithoutStarting(); XCTAssertEqual(n, 7) }
    @MainActor func testConsentBeforeFirstSend() async throws { let n = try await ChatStreamingChecks.consentBeforeFirstSend(); XCTAssertEqual(n, 8) }
    @MainActor func testIncrementalCompletion() async throws { let n = try await ChatStreamingChecks.incrementalCompletion(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testCancellationFailureAndGeneration() async throws { let n = try await ChatStreamingChecks.cancellationFailureAndGeneration(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testBoundsFallbackAndSaveFailure() async throws { let n = try await ChatStreamingChecks.boundsFallbackAndSaveFailure(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testRestoreCancelsPreview() async throws { let n = try await ChatStreamingChecks.restoreCancelsPreview(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testStructuredToolsApplyDirectly() async throws { let n = try await ChatStreamingChecks.structuredToolsApplyDirectly(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testStructuredStreamingAnswerAndReview() async throws { let n = try await ChatStreamingChecks.structuredStreamingAnswerAndReview(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testStructuredStreamingRejectionsAndCancellation() async throws { let n = try await ChatStreamingChecks.structuredStreamingRejectionsAndCancellation(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testActualHTTPStream() async throws { let n = try await ChatStreamingChecks.actualHTTPStream(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testStructuredTransportCompatibility() async throws { let n = try await ChatStreamingChecks.structuredTransportCompatibility(); XCTAssertGreaterThan(n, 0) }
    @MainActor func testStructuredRepliesSurviveLearningChanges() async throws { let n = try await ChatStreamingChecks.structuredRepliesSurviveLearningChanges(); XCTAssertGreaterThan(n, 0) }
}
#endif
#endif
