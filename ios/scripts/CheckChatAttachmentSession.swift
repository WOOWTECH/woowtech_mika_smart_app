import AssistantAttachments
import AssistantMemory
import AssistantModels
import AssistantPersistence
import CoreGraphics
import Foundation
import ImageIO

private struct Failure: Error { let name: String }
@MainActor private var assertions = 0
@MainActor private func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
    guard value() else { throw Failure(name: name) }; assertions += 1
}
private final class Keys: LearningKeyStore {
    var values: [String: Data] = [:]
    func read(id: String) throws -> Data? { values[id] }
    func insert(_ key: Data, id: String) throws { values[id] = key }
    func remove(id: String) throws { values.removeValue(forKey: id) }
    func removeAll(except id: String) throws { values = values.filter { $0.key == id } }
}
private final class Credentials: ModelCredentialStoring {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values = [:] }
}
private actor Gate {
    private var started = false, released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = [], releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        started = true; let waiters = startWaiters; startWaiters = []; waiters.forEach { $0.resume() }
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func waitForStart() async { if !started { await withCheckedContinuation { startWaiters.append($0) } } }
    func release() { released = true; let waiters = releaseWaiters; releaseWaiters = []; waiters.forEach { $0.resume() } }
}
private actor Model: ChatModelClient {
    let replies: [String]
    let gate: Gate?
    private(set) var requests: [[ModelMessage]] = []
    private(set) var visions: [ModelVisionCapability] = []
    init(_ replies: [String], gate: Gate? = nil) { self.replies = replies; self.gate = gate }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        let index = requests.count; requests.append(messages); visions.append(configuration.vision)
        if let gate { await gate.wait() }
        guard index < replies.count else { throw Failure(name: "unexpected model request") }
        return replies[index]
    }
}
private actor StreamRecords {
    var streamed: [[ModelMessage]] = []; var completed: [[ModelMessage]] = []
    func addStream(_ messages: [ModelMessage]) { streamed.append(messages) }
    func addComplete(_ messages: [ModelMessage]) { completed.append(messages) }
}
private final class StreamModel: StreamingChatModelClient, @unchecked Sendable {
    let records = StreamRecords(); let fails: Bool
    init(fails: Bool) { self.fails = fails }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        await records.addComplete(messages); return "unexpected fallback"
    }
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await records.addStream(messages)
                continuation.yield("fixture partial")
                if fails { continuation.finish(throwing: URLError(.networkConnectionLost)) }
                else { continuation.yield(" reply"); continuation.finish() }
            }
        }
    }
}
private struct CompleteHTTP: ChatModelClient {
    let client: HTTPChatModelClient
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await client.complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }
}
@MainActor private final class Environment {
    let root: URL, defaults: UserDefaults, repository: ModelSettingsRepository, learning: LearningStore, archive: ConversationArchiveStore
    let suite = "woow.attachment.session." + UUID().uuidString
    let keys = Keys(), archiveKeys = Keys(), credentials = Credentials()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-attachment-session-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        repository = ModelSettingsRepository(defaults: defaults, credentials: credentials)
        _ = try repository.save(baseURL: "https://attachment.example.invalid/v1", model: "fixture", newKey: "synthetic-key")
        learning = LearningStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("learning.vault"), keys: keys))
        guard learning.updatePreferences({ $0.useMemory = false; $0.autoRemember = false }) else { throw Failure(name: "learning setup") }
        archive = ConversationArchiveStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("archive.vault"), keys: archiveKeys))
    }
    func session(_ model: any ChatModelClient, probe: @escaping @MainActor () async -> Void = {},
                 clientProbe: @escaping @MainActor () -> Void = {}) -> ChatSession {
        ChatSession(learning: learning, repository: repository, client: model, archive: archive,
                    attachmentPreflightProbe: probe, attachmentClientStartProbe: clientProbe)
    }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    func file(_ name: String = "attachment.txt") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("fixture attachment secret".utf8).write(to: url)
        return url
    }
}
@MainActor private func wait(_ predicate: () -> Bool) async throws {
    for _ in 0..<1000 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
    throw Failure(name: "fixture wait timed out")
}
@MainActor private func stage(_ session: ChatSession, url: URL, vision: ModelVisionCapability = .unknown) async throws {
    session.attachmentPresenter.picked(url)
    try await wait { if case .ready = session.attachmentPresenter.state.phase { return true }; return false }
    try check(session.prepareAttachmentReview(vision: vision), "review context prepared")
    try session.attachmentPresenter.confirm()
    try check(session.canSend, "confirmed attachment can send")
}
@MainActor private func finish(_ session: ChatSession) async throws {
    session.send()
    guard let task = session.capturedArchiveRequest else { throw Failure(name: "request did not start") }
    await task.value
}
private func image() throws -> Data {
    guard let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let cg = context.makeImage() else { throw Failure(name: "fixture image") }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw Failure(name: "image encoder") }
    CGImageDestinationAddImage(destination, cg, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure(name: "image finalize") }
    return data as Data
}

@main private enum CheckChatAttachmentSession {
    @MainActor static func main() async throws {
        try await archiveQuoteAndBranch()
        try await boundariesAndVision()
        try await streamingAndFailure()
        try await realHTTPSerialization()
        try await preflightChanges()
        try await clientStartChange()
        try await staleQuoteDuringPreflight()
        try await nonStreamingFailure()
        try await cancellation()
        print("Chat attachment session checks passed: \(assertions)")
    }
    @MainActor static func archiveQuoteAndBranch() async throws {
        let e = try Environment(); defer { e.close() }
        let model = Model(["fixture answer includes fixture attachment secret", "second reply", "plain reply"])
        let s = e.session(model); s.draft = "first question"
        let file = try e.file(); try await stage(s, url: file); try await finish(s)
        let firstRequests = await model.requests
        let expected = try ModelAttachment.text(utf8: Data("fixture attachment secret".utf8))
        try check(firstRequests.count == 1 && firstRequests[0].last?.attachment == expected, "first request contains exact attachment")
        try check(s.entries.count == 2 && s.entries[0].content == "first question" && s.draft.isEmpty, "completed pair and draft")
        let original = e.archive.state.conversations[0]
        try check(original.turns[0].userText == "first question" && original.turns[0].assistantText.contains("fixture attachment secret"), "answer remains saved even if it quotes attachment")
        try check(original.turns[0].pdf == nil, "no PDF or original attachment metadata archived")
        s.draft = "pending attachment"; try await stage(s, url: file)
        try check(!s.deleteConversation(id: original.id) && !s.openConversation(id: original.id),
                  "pending attachment blocks deleting or switching current conversation")
        s.newConversation()
        try check(s.isCurrentConversation(id: original.id) && e.archive.state.conversations.count == 1,
                  "pending attachment cannot be silently discarded by new conversation")
        do { _ = try s.prepareBranch(source: original, assistantID: original.turns[0].assistantID, title: "blocked")
             throw Failure(name: "pending attachment allowed branch") }
        catch ConversationBranchError.unfinishedTurn { assertions += 1 }
        s.discardGeneralAttachment(); s.draft = ""
        let plan = try s.prepareBranch(source: original, assistantID: original.turns[0].assistantID, title: "fixture branch")
        let branchID = try s.commitBranch(plan)
        try check(s.selectQuote(messageID: plan.branch.turns[0].assistantID, expectedContent: original.turns[0].assistantText, in: branchID), "quote from restored branch")
        s.draft = "follow up"; try await stage(s, url: file); try await finish(s)
        let branch = e.archive.state.conversations.first { $0.id == branchID }!
        try check(branch.branchOrigin?.parentID == original.id && branch.customTitle == "fixture branch" && branch.turns.count == 2, "v5 branch metadata survives attachment save")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e.archive.state)) as! [String: Any]
        try check(encoded["version"] as? Int == 5, "archive remains version five")
        let requests = await model.requests
        try check(requests.count == 2 && requests[1].last?.attachment == expected, "branch request includes attachment once")
        try check(requests[1].dropLast().allSatisfy { $0.attachment == nil }, "history has no original attachment")
        try check(requests[1].last?.content.contains("fixture answer includes") == true, "quote is in current user prompt")
        try check(branch.turns[1].userText.contains("follow up") && branch.turns[1].assistantText == "second reply", "quoted user text and answer archived")
        s.draft = "ordinary next"; try await finish(s)
        let final = await model.requests
        try check(final.count == 3 && final[2].allSatisfy { $0.attachment == nil }, "later plain turn never replays original attachment")
        try check(final[2].contains { $0.content.contains("fixture answer includes fixture attachment secret") }, "ordinary history may contain answer-derived content")
    }
    @MainActor static func boundariesAndVision() async throws {
        let e = try Environment(); defer { e.close() }
        let model = Model(["image answer"]); let s = e.session(model); s.draft = "question"
        s.attachmentPresenter.picked(e.root.appendingPathComponent("unsupported.pdf"))
        try check(!s.canSend && s.attachmentPresenter.state.error != nil, "failed selection cannot silently become text-only")
        s.send(); let failedSelectionCalls = await model.requests
        try check(failedSelectionCalls.isEmpty, "failed selection sends nothing")
        s.discardGeneralAttachment()
        try await stage(s, url: e.file())
        s.attachmentPresenter.picked(e.root.appendingPathComponent("unsupported.pdf"))
        try check(!s.canSend && s.attachmentPresenter.state.error != nil, "failed replacement cannot send the old confirmed file")
        s.send(); let failedReplacementCalls = await model.requests
        try check(failedReplacementCalls.isEmpty, "failed replacement sends nothing")
        try await stage(s, url: e.file())
        let originalContext = s.attachmentPresenter.state.context!
        let substituted = try ChatAttachmentReviewContext(baseURL: URL(string: "https://other.example.invalid/v1")!,
            model: originalContext.model, credentialRevision: originalContext.credentialRevision,
            inputRevision: originalContext.inputRevision, additionalData: originalContext.additionalData, vision: .unknown)
        s.attachmentPresenter.updateContext(substituted); try s.attachmentPresenter.confirm()
        try check(!s.canSend, "foreign reviewed destination cannot authorize configured endpoint")
        s.send(); let substitutedCalls = await model.requests
        try check(substitutedCalls.isEmpty, "foreign destination sends nothing")
        try check(s.prepareAttachmentReview(), "restore configured destination review")
        try s.attachmentPresenter.confirm()
        s.usesMCP = true; s.send()
        try check(s.attachmentIssue == .chatAttachmentToolsEnabled && !s.isSubmitting, "MCP cannot receive attachment")
        s.usesMCP = false
        try check(e.learning.updatePreferences { $0.useMemory = true }, "enable memory tools")
        try check(!s.prepareAttachmentReview() && s.attachmentIssue == .chatAttachmentToolsEnabled, "memory tools cannot receive attachment")
        let calls = await model.requests; try check(calls.isEmpty, "tool boundary prevents all model calls")
        try check(e.learning.updatePreferences { $0.useMemory = false }, "disable memory tools")
        try check(s.prepareAttachmentReview(), "review refreshed after tool change")
        try s.attachmentPresenter.confirm()
        s.draft = "changed question"
        try check(!s.canSend && s.attachmentPresenter.state.context == nil, "draft edit revokes confirmation")
        s.send(); try check(s.attachmentIssue == .chatAttachmentReviewRequired, "unconfirmed send reports review")
        s.discardGeneralAttachment()
        let imageURL = e.root.appendingPathComponent("fixture.png"), imageData = try image(); try imageData.write(to: imageURL)
        s.attachmentPresenter.picked(imageURL)
        try await wait { if case .ready = s.attachmentPresenter.state.phase { return true }; return false }
        try check(s.prepareAttachmentReview(), "image review prepared")
        do { try s.attachmentPresenter.confirm(); throw Failure(name: "unknown vision accepted") }
        catch ChatAttachmentPresentationError.visionUnknown { assertions += 1 }
        try check(!s.canSend, "unknown model vision blocks image send")
        try check(s.prepareAttachmentReview(vision: .unsupported), "unsupported capability review")
        do { try s.attachmentPresenter.confirm(); throw Failure(name: "unsupported vision accepted") }
        catch ChatAttachmentPresentationError.visionUnsupported { assertions += 1 }
        try check(s.prepareAttachmentReview(vision: .supported), "explicit supported capability review")
        try s.attachmentPresenter.confirm(); try await finish(s)
        let imageRequests = await model.requests, visions = await model.visions
        let expectedImage = try ModelAttachment.image(data: imageData, mimeType: "image/png")
        try check(imageRequests.count == 1 && imageRequests[0].last?.attachment == expectedImage && visions == [.supported],
                  "explicit supported image is sent once with matching capability")
        s.draft = "another question"; s.attachmentPresenter.picked(imageURL)
        try await wait { if case .ready = s.attachmentPresenter.state.phase { return true }; return false }
        s.generalAttachmentEnteredBackground()
        try check(s.attachmentPresenter.state.phase == .empty, "background discards staged image")
    }
    @MainActor static func streamingAndFailure() async throws {
        for fails in [false, true] {
            let e = try Environment(); defer { e.close() }
            let model = StreamModel(fails: fails), s = e.session(model); s.draft = "stream question"
            try await stage(s, url: e.file()); try await finish(s)
            let streams = await model.records.streamed, completes = await model.records.completed
            try check(streams.count == 1 && streams[0].last?.attachment != nil && completes.isEmpty, "one actual streaming call and no fallback")
            if fails {
                try check(s.entries.isEmpty && s.draft == "stream question" && s.attachmentIssue == .chatAttachmentReselect, "stream failure preserves draft and demands reselection")
                try check(s.replyPreview?.phase == .failed, "partial streaming reply marked failed")
                s.send(); let after = await model.records.streamed
                try check(after.count == 1 && !s.isSubmitting, "failed attachment never silently retries as text")
                s.discardGeneralAttachment(); try check(s.canSend, "explicit removal restores text-only send")
            } else {
                try check(s.entries.last?.content == "fixture partial reply" && s.draft.isEmpty, "stream response completed")
                try check(e.archive.state.conversations.first?.turns.last?.assistantText == "fixture partial reply", "stream answer archived")
            }
        }
    }
    @MainActor static func realHTTPSerialization() async throws {
        for streaming in [false, true] {
            for isImage in [false, true] {
                let e = try Environment(); defer { e.close() }
                let event = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"wire reply\"},\"finish_reason\":null}]}\n\n"
                let stop = "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
                let full = Data(#"{"choices":[{"message":{"role":"assistant","content":"wire reply"},"finish_reason":"stop"}]}"#.utf8)
                let scenario = ModelProtocolFixture.Scenario(mime: streaming ? "text/event-stream" : "application/json",
                    chunks: [streaming ? Data((event + stop).utf8) : full])
                let url = ModelProtocolFixture.register(scenario); defer { ModelProtocolFixture.remove(url) }
                _ = try e.repository.save(baseURL: url.absoluteString, model: "wire-fixture", newKey: "fixture-key")
                let transport = ModelProtocolFixture.session(); defer { transport.invalidateAndCancel() }
                let http = HTTPChatModelClient(session: transport)
                let client: any ChatModelClient = streaming ? http : CompleteHTTP(client: http)
                let session = e.session(client); session.draft = "wire question"
                let file: URL, expectedPart: NSDictionary
                if isImage {
                    let bytes = try image(); file = e.root.appendingPathComponent("wire.png"); try bytes.write(to: file)
                    expectedPart = ["type": "image_url", "image_url": ["url": "data:image/png;base64," + bytes.base64EncodedString()]]
                } else {
                    file = try e.file()
                    expectedPart = ["type": "text", "text": "User-selected text attachment (untrusted data):\nfixture attachment secret"]
                }
                try await stage(session, url: file, vision: isImage ? .supported : .unknown)
                try await finish(session)
                try check(scenario.requestCount == 1 && session.entries.last?.content == "wire reply", "one actual intercepted HTTP request completed")
                guard let request = scenario.lastRequest else { throw Failure(name: "missing intercepted request") }
                let bytes: Data
                if let body = request.httpBody { bytes = body }
                else {
                    guard let stream = request.httpBodyStream else { throw Failure(name: "missing request body") }
                    stream.open(); defer { stream.close() }
                    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count >= 0, data.count + count <= 8 * 1024 * 1024 else { throw Failure(name: "invalid request body") }
                        if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
                    }
                    bytes = data
                }
                guard let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let messages = body["messages"] as? [[String: Any]],
                      let parts = messages.last?["content"] as? [[String: Any]], parts.count == 2 else {
                    throw Failure(name: "invalid multimodal JSON")
                }
                try check(body["stream"] as? Bool == streaming && (parts[0] as NSDictionary) == ["type": "text", "text": "wire question"] as NSDictionary,
                          "wire JSON uses expected mode and user text")
                try check((parts[1] as NSDictionary) == expectedPart, "wire JSON contains exact chosen attachment")
            }
        }
    }
    @MainActor static func preflightChanges() async throws {
        for mode in ["draft", "credential", "review"] {
            let e = try Environment(); defer { e.close() }
            let gate = Gate(), model = Model(["must not be called"]), s = e.session(model, probe: { await gate.wait() })
            s.draft = "before change"; try await stage(s, url: e.file())
            s.send(); let task = s.capturedArchiveRequest!
            await gate.waitForStart()
            if mode == "credential" {
                e.credentials.values[s.savedSettings!.credentialAccount] = "changed-synthetic-key"
            } else if mode == "draft" { s.draft = "after change" }
            else {
                let prior = s.attachmentPresenter.state.context!
                let substituted = try ChatAttachmentReviewContext(baseURL: URL(string: "https://other.example.invalid/v1")!,
                    model: prior.model, credentialRevision: prior.credentialRevision,
                    inputRevision: prior.inputRevision, additionalData: prior.additionalData, vision: prior.vision)
                s.attachmentPresenter.updateContext(substituted)
            }
            await gate.release(); await task.value
            let calls = await model.requests
            try check(calls.isEmpty && s.entries.isEmpty && e.archive.state.conversations.isEmpty, "changed preflight never starts network or archives")
            try check(s.attachmentIssue == .chatAttachmentReselect && !s.isSubmitting, "consumed attachment requires explicit decision")
            try check(s.draft == (mode == "draft" ? "after change" : "before change"), "changed draft retained")
            s.send(); let retry = await model.requests
            try check(retry.isEmpty, "changed preflight cannot become text-only send")
        }
    }
    @MainActor static func staleQuoteDuringPreflight() async throws {
        let e = try Environment(); defer { e.close() }
        let gate = Gate(), model = Model(["original answer"]), s = e.session(model, probe: { await gate.wait() })
        s.draft = "original question"; try await finish(s)
        let row = e.archive.state.conversations[0]
        try check(s.selectQuote(messageID: row.turns[0].assistantID, expectedContent: "original answer", in: row.id), "select archived quote")
        s.draft = "quoted follow up"; try await stage(s, url: e.file()); s.send()
        let task = s.capturedArchiveRequest!; await gate.waitForStart()
        try check(e.archive.delete(id: row.id), "remove quoted source")
        await gate.release(); await task.value
        let calls = await model.requests
        try check(calls.count == 1 && s.entries.count == 2, "stale quoted source prevents attachment call")
        try check(s.pendingQuote != nil && s.draft == "quoted follow up" && s.attachmentIssue == .chatAttachmentReselect,
                  "stale quote and draft retained for review")
    }
    @MainActor static func clientStartChange() async throws {
        let e = try Environment(); defer { e.close() }
        let model = Model(["must not be called"])
        weak var target: ChatSession?
        let s = e.session(model, clientProbe: { target?.draft = "changed at client start" })
        target = s; s.draft = "before client start"; try await stage(s, url: e.file()); try await finish(s)
        let calls = await model.requests
        try check(calls.isEmpty && s.draft == "changed at client start" && s.attachmentIssue == .chatAttachmentReselect,
                  "client entry rechecks changed context before network")
    }
    @MainActor static func nonStreamingFailure() async throws {
        let e = try Environment(); defer { e.close() }
        let model = Model([]), s = e.session(model); s.draft = "failure question"
        try await stage(s, url: e.file()); try await finish(s)
        try check(s.entries.isEmpty && s.draft == "failure question" && s.attachmentIssue == .chatAttachmentReselect,
                  "non-streaming failure preserves draft and requires decision")
        s.send(); let calls = await model.requests
        try check(calls.count == 1, "non-streaming failure cannot retry implicitly")
    }
    @MainActor static func cancellation() async throws {
        let e = try Environment(); defer { e.close() }
        let gate = Gate(), model = Model(["late reply"], gate: gate), s = e.session(model)
        s.draft = "cancel question"; try await stage(s, url: e.file()); s.send()
        let task = s.capturedArchiveRequest!; await gate.waitForStart()
        try check(!s.prepareAttachmentReview(vision: .supported) && s.attachmentIssue == nil,
                  "in-flight review cannot change capability or publish a spurious error")
        s.cancel()
        try check(s.draft == "cancel question" && s.attachmentIssue == .chatAttachmentReselect, "cancel retains draft and requires decision")
        await gate.release(); await task.value
        try check(s.entries.isEmpty && e.archive.state.conversations.isEmpty && !s.isSubmitting, "late response cannot archive")
        s.send(); let calls = await model.requests
        try check(calls.count == 1, "cancel cannot silently resend")
    }
}
