import AssistantModels
import Foundation

private final class Credentials: ModelCredentialStoring {
    enum FixtureFailure: Error { case partialRemoval }
    var values: [String: String] = [:]
    var failAfterRemoval = false
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws {
        values.removeAll()
        if failAfterRemoval { throw FixtureFailure.partialRemoval }
    }
}

private final class RepositoryBox: @unchecked Sendable {
    let repository: ModelSettingsRepository
    init(_ repository: ModelSettingsRepository) { self.repository = repository }
}
private final class DispatchSignals: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let done = DispatchSemaphore(value: 0)
    func waitForDone() -> Bool { done.wait(timeout: .now() + 5) == .success }
}

@MainActor private final class FakeTransport: AuthorizedSpeechProviderTransport {
    struct Reply { let status: Int; let data: Data; let delayed: Bool }
    var replies: [Reply] = []
    var requests: [URLRequest] = []
    var waiting: CheckedContinuation<Void, Never>?
    func enqueue(_ status: Int, _ body: String = "{}", delayed: Bool = false) {
        replies.append(Reply(status: status, data: Data(body.utf8), delayed: delayed))
    }
    var blockBeforeDispatch = false
    var beforeDispatch: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest, permit: SpeechDispatchPermit) async throws -> (Data, Int) {
        if blockBeforeDispatch {
            blockBeforeDispatch = false
            await withCheckedContinuation { beforeDispatch = $0 }
        }
        try permit.dispatch { self.requests.append(request) }
        precondition(!replies.isEmpty, "unexpected request")
        let reply = replies.removeFirst()
        if reply.delayed { await withCheckedContinuation { waiting = $0 } }
        return (reply.data, reply.status)
    }
    func release() { waiting?.resume(); waiting = nil }
    func releaseBeforeDispatch() { beforeDispatch?.resume(); beforeDispatch = nil }
    func isWaiting() -> Bool { waiting != nil }
    func count() -> Int { requests.count }
    func request(_ index: Int) -> URLRequest { requests[index] }
}

@main enum Checks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label); count += 1
        }
        func waitForRequest(_ fake: FakeTransport) async {
            for _ in 0..<100_000 {
                if fake.isWaiting() { return }
                await Task.yield()
            }
            fatalError("fake transport did not receive request")
        }
        func waitBeforeDispatch(_ fake: FakeTransport) async {
            for _ in 0..<100_000 {
                if fake.beforeDispatch != nil { return }
                await Task.yield()
            }
            fatalError("transport did not reach pre-dispatch gate")
        }
        let suite = "configured-speech-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = Credentials()
        let repository = ModelSettingsRepository(defaults: defaults, credentials: credentials)
        let fake = FakeTransport()
        let flow = ConfiguredProviderSpeech(repository: repository, transport: fake)
        let url = "https://speech.invalid/v1"
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "fixture-key")
        check(fake.count() == 0, "initialization must not contact a provider")
        do { _ = try flow.beginRecording(); fatalError("unverified") } catch ConfiguredProviderSpeech.Failure.unavailable { count += 1 }
        do { _ = try await flow.probe(rawBaseURL: "https://other.invalid/v1", kind: .openAICompatible, model: "speech-model"); fatalError("mismatched URL") }
        catch SpeechProviderError.invalidConfiguration { count += 1 }
        check(fake.count() == 0, "unreviewed URL must not transmit")
        fake.enqueue(404)
        fake.enqueue(200, "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}")
        let method = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        check(method == .chatInputAudio, "fallback selects successful method")
        let first = fake.request(0)
        check(first.url?.absoluteString == url + "/audio/transcriptions", "bound configured destination")
        check(first.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "uses stored fixture credential")
        check(first.httpBody?.range(of: Data("RIFF".utf8)) != nil, "probe includes WAV")
        let second = fake.request(1)
        check(second.url?.absoluteString == url + "/chat/completions", "fallback endpoint")
        let short = try flow.beginRecording()
        let empty = try await flow.transcribe(recording: short, samples: [1, -1])
        let afterShort = fake.count()
        check(empty == "" && afterShort == 2, "short recording must not be uploaded")
        let id = try flow.beginRecording()
        fake.enqueue(200, "{\"choices\":[{\"message\":{\"content\":\" transcript \"}}]}")
        let text = try await flow.transcribe(recording: id, samples: [Int16](repeating: 1, count: 8_000))
        check(text == "transcript", "transcription returned")
        do { _ = try await flow.transcribe(recording: id, samples: [1]); fatalError("reused") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        fake.enqueue(401)
        do { _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "other-model"); fatalError("unauthorized") }
        catch SpeechProviderError.unauthorized { count += 1 }
        let retained = try flow.beginRecording()
        let retainedText = try await flow.transcribe(recording: retained, samples: [1])
        check(retainedText.isEmpty, "failed probe retains prior selection")
        let retainedFull = try flow.beginRecording()
        fake.enqueue(200, "{\"choices\":[{\"message\":{\"content\":\"retained\"}}]}")
        let fullText = try await flow.transcribe(recording: retainedFull, samples: [Int16](repeating: 1, count: 8_000))
        let fullRequest = fake.request(fake.count() - 1)
        check(fullText == "retained" && fullRequest.url?.absoluteString == url + "/chat/completions", "failed probe retains old method for full recording")
        check(fullRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "retained recording uses previous credential")
        let fullJSON = try JSONSerialization.jsonObject(with: fullRequest.httpBody!) as? [String: Any]
        check(fullJSON?["model"] as? String == "speech-model", "retained recording uses previous model")
        let old = try flow.beginRecording()
        let next = try flow.beginRecording()
        do { _ = try await flow.transcribe(recording: old, samples: [1]); fatalError("superseded") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        flow.invalidate()
        do { _ = try await flow.transcribe(recording: next, samples: [1]); fatalError("cancelled") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        fake.enqueue(401)
        do { _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model"); fatalError("unauthorized") }
        catch SpeechProviderError.unauthorized { count += 1 }
        check(fake.count() == 6, "unauthorized does not fall back")
        fake.enqueue(200, "{\"text\":\"ok\"}", delayed: true)
        let delayed = Task { try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model") }
        await waitForRequest(fake)
        _ = try repository.save(baseURL: url, model: "changed", newKey: "")
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "")
        fake.release()
        do { _ = try await delayed.value; fatalError("ABA settings accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        do { _ = try flow.beginRecording(); fatalError("stale probe authorized") }
        catch ConfiguredProviderSpeech.Failure.unavailable { count += 1 }
        fake.enqueue(200, "{\"text\":\"ok\"}", delayed: true)
        let cancelled = Task { try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model") }
        await waitForRequest(fake)
        flow.invalidate()
        fake.release()
        do { _ = try await cancelled.value; fatalError("late success accepted") }
        catch is CancellationError { count += 1 }
        fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let recording = try flow.beginRecording()
        fake.enqueue(200, "{\"text\":\"late\"}", delayed: true)
        let result = Task { try await flow.transcribe(recording: recording, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        flow.invalidate()
        fake.release()
        do { _ = try await result.value; fatalError("late transcript accepted") }
        catch is CancellationError { count += 1 }
        fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let previous = try flow.beginRecording()
        fake.enqueue(200, "{\"text\":\"old\"}", delayed: true)
        let oldResult = Task { try await flow.transcribe(recording: previous, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        let newer = try flow.beginRecording()
        fake.release()
        do { _ = try await oldResult.value; fatalError("superseded result accepted") }
        catch is CancellationError { count += 1 }
        let newText = try await flow.transcribe(recording: newer, samples: [1])
        check(newText.isEmpty, "newer attempt remains usable")
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "replacement-fixture")
        do { _ = try flow.beginRecording(); fatalError("changed credential accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        fake.enqueue(200, "{\"candidates\":[{\"content\":{\"parts\":[]}}]}")
        let gemini = try await flow.probe(rawBaseURL: url, kind: .gemini, model: "gemini-fixture")
        check(gemini == .geminiInline, "explicit Gemini choice uses Gemini method")
        let lastIndex = fake.count() - 1
        let geminiRequest = fake.request(lastIndex)
        check(geminiRequest.url?.absoluteString == url + "/v1beta/models/gemini-fixture:generateContent", "Gemini destination")
        check(geminiRequest.value(forHTTPHeaderField: "x-goog-api-key") == "replacement-fixture", "new key used only after new probe")
        let changing = try flow.beginRecording()
        fake.enqueue(200, "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"old\"}]}}]}", delayed: true)
        let changingResult = Task { try await flow.transcribe(recording: changing, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "third-fixture")
        fake.release()
        do { _ = try await changingResult.value; fatalError("old credential result accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }

        let gate = FakeTransport()
        let guarded = ConfiguredProviderSpeech(repository: repository, transport: gate)
        let otherWindowRepository = ModelSettingsRepository(defaults: defaults, credentials: credentials)
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let beforeChange = try guarded.beginRecording()
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let staged = Task { try await guarded.transcribe(recording: beforeChange, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitBeforeDispatch(gate)
        let priorCount = gate.count()
        _ = try otherWindowRepository.save(baseURL: "https://new.invalid/v1", model: "new-model", newKey: "new-fixture")
        gate.releaseBeforeDispatch()
        do { _ = try await staged.value; fatalError("changed destination dispatched") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        check(gate.count() == priorCount, "no dispatch after other repository replaces destination and credential")
        gate.replies.removeAll()
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "fresh-fixture")
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let aba = try guarded.beginRecording()
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let stagedABA = Task { try await guarded.transcribe(recording: aba, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitBeforeDispatch(gate)
        let countBeforeABA = gate.count()
        _ = try repository.save(baseURL: url, model: "temporary", newKey: "")
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "")
        gate.releaseBeforeDispatch()
        do { _ = try await stagedABA.value; fatalError("ABA dispatched") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        check(gate.count() == countBeforeABA, "no dispatch after settings changed and reverted")
        gate.replies.removeAll()
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let canceledID = try guarded.beginRecording()
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let stagedCancel = Task { try await guarded.transcribe(recording: canceledID, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitBeforeDispatch(gate)
        let beforeCancel = gate.count()
        guarded.invalidate()
        gate.releaseBeforeDispatch()
        do { _ = try await stagedCancel.value; fatalError("cancelled request dispatched") }
        catch is CancellationError { count += 1 }
        check(gate.count() == beforeCancel, "explicit invalidation before dispatch sends nothing")
        gate.replies.removeAll()
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let taskCanceledID = try guarded.beginRecording()
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let taskCanceled = Task { try await guarded.transcribe(recording: taskCanceledID, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitBeforeDispatch(gate)
        let beforeTaskCancel = gate.count()
        taskCanceled.cancel()
        gate.releaseBeforeDispatch()
        do { _ = try await taskCanceled.value; fatalError("cancelled task dispatched") }
        catch is CancellationError { count += 1 }
        check(gate.count() == beforeTaskCancel, "task cancellation before dispatch sends nothing")
        gate.replies.removeAll()
        let sentID = try guarded.beginRecording()
        gate.enqueue(200, "{\"text\":\"late\"}", delayed: true)
        let alreadySent = Task { try await guarded.transcribe(recording: sentID, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitForRequest(gate)
        let dispatchedCount = gate.count()
        _ = try repository.save(baseURL: url, model: "after-dispatch", newKey: "later-fixture")
        gate.release()
        do { _ = try await alreadySent.value; fatalError("stale result accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        check(gate.count() == dispatchedCount && dispatchedCount == beforeTaskCancel + 1,
              "request dispatched before settings change cannot be recalled")
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let stagedProbe = Task { try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "another-model") }
        await waitBeforeDispatch(gate)
        let beforeProbeChange = gate.count()
        _ = try repository.save(baseURL: url, model: "changed-again", newKey: "")
        gate.releaseBeforeDispatch()
        do { _ = try await stagedProbe.value; fatalError("stale probe dispatched") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        check(gate.count() == beforeProbeChange, "stale probe never dispatches or falls back")
        gate.replies.removeAll()
        gate.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await guarded.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let removalID = try guarded.beginRecording()
        gate.blockBeforeDispatch = true
        gate.enqueue(200, "{\"text\":\"should not send\"}")
        let removing = Task { try await guarded.transcribe(recording: removalID, samples: [Int16](repeating: 7, count: 8_000)) }
        await waitBeforeDispatch(gate)
        let beforeRemoval = gate.count()
        credentials.failAfterRemoval = true
        do { try repository.remove(); fatalError("fixture removal should fail") }
        catch Credentials.FixtureFailure.partialRemoval { count += 1 }
        gate.releaseBeforeDispatch()
        do { _ = try await removing.value; fatalError("partially removed credential dispatched") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        check(gate.count() == beforeRemoval, "partial credential removal invalidates before dispatch")

        // Deterministically attempt a write on another thread while the
        // synchronous dispatch operation still holds the repository lock.
        let lockSuite = "speech-dispatch-lock-" + UUID().uuidString
        let lockDefaults = UserDefaults(suiteName: lockSuite)!
        defer { lockDefaults.removePersistentDomain(forName: lockSuite) }
        let lockRepository = ModelSettingsRepository(defaults: lockDefaults, credentials: Credentials())
        _ = try lockRepository.save(baseURL: url, model: "first", newKey: "fixture")
        let box = RepositoryBox(lockRepository)
        let signals = DispatchSignals()
        let boundary = SpeechDispatchPermit { dispatch in try ModelSettingsRepository.withSpeechDispatchLock { try dispatch() } }
        try boundary.dispatch {
            DispatchQueue.global().async {
                signals.started.signal()
                _ = try? box.repository.save(baseURL: url, model: "second", newKey: "")
                signals.done.signal()
            }
            check(signals.started.wait(timeout: .now() + 5) == .success, "writer attempted mutation")
            check(signals.done.wait(timeout: .now() + .milliseconds(50)) == .timedOut, "settings write cannot interleave with dispatch")
        }
        check(signals.waitForDone(), "settings write completes after dispatch boundary")
        check(try lockRepository.load()?.model == "second", "concurrent settings change committed")
        let cancelSignals = DispatchSignals()
        let cancelBoundary = SpeechDispatchPermit { dispatch in try dispatch() }
        let cancellationGate = cancelBoundary.cancellation
        try cancelBoundary.dispatch {
            DispatchQueue.global().async {
                cancelSignals.started.signal()
                cancellationGate.cancel()
                cancelSignals.done.signal()
            }
            check(cancelSignals.started.wait(timeout: .now() + 5) == .success, "concurrent cancellation attempted")
            check(cancelSignals.done.wait(timeout: .now() + .milliseconds(50)) == .timedOut,
                  "cancellation cannot split the synchronous dispatch operation")
        }
        check(cancelSignals.waitForDone(), "cancellation completes after dispatch operation")
        print("PASS configured provider flow: \(count) checks; isolated defaults, fixture credentials and fake transport")
    }
}
