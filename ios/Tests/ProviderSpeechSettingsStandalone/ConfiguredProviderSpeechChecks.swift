@testable import AssistantModels
import Foundation

private final class LocalRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func record(_ value: URLRequest) { lock.lock(); defer { lock.unlock() }; requests.append(value) }
    func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
private final class LocalSpeechURLProtocol: URLProtocol {
    static let recorder = LocalRequestRecorder()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var body = Data(), chunk = [UInt8](repeating: 0, count: 4096)
            while body.count <= 4_000_000 {
                let count = stream.read(&chunk, maxLength: chunk.count)
                if count <= 0 { break }
                body.append(contentsOf: chunk.prefix(count))
            }
            stream.close()
            captured.httpBody = body
        }
        Self.recorder.record(captured)
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"text\":\"local transcript\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

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
private final class ChoiceBox: @unchecked Sendable {
    let store: SpeechChoiceStore
    init(_ store: SpeechChoiceStore) { self.store = store }
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
    var completed = 0
    func send(_ request: URLRequest, permit: SpeechDispatchPermit) async throws -> (Data, Int) {
        defer { completed += 1 }
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

@MainActor private final class FixtureLease: VoiceAudioLease, VoiceAudioCoordinating {
    private(set) var held = false
    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)? {
        guard !held else { return nil }
        held = true; return self
    }
    func activateForRecording() -> Bool { held }
    func release() { held = false }
}
@MainActor private final class FixturePCMSource: ProviderPCMSource {
    var buffer: ProviderPCMBuffer?
    var delayPermission = false
    var pendingPermission: (@MainActor (Bool) -> Void)?
    var permissionRequests = 0
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        permissionRequests += 1
        if delayPermission { pendingPermission = completion } else { completion(true) }
    }
    func start(buffer: ProviderPCMBuffer, activate: @escaping @MainActor () -> Bool,
               mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        if mayStart(), activate(), mayStart() { self.buffer = buffer }
    }
    func stop() { buffer = nil }
}
@MainActor private final class FixtureSystemVoice: VoiceInputDriver {
    var starts = 0, cancellations = 0
    var callbacks: [(UUID, (UUID, VoiceInputEvent) -> Void)] = []
    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        if mayContinue() { starts += 1; callbacks.append((id, emit)) }
    }
    func finish(id: UUID) {}
    func cancel(id: UUID) { cancellations += 1 }
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
        func waitForCompletions(_ fake: FakeTransport, _ expected: Int) async {
            for _ in 0..<100_000 {
                if fake.completed >= expected { return }
                await Task.yield()
            }
            fatalError("transport did not finish")
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
        // Exercise the actual PCM->WAV->request->response path using only an
        // injected source and transport; this does not wire any product UI.
        fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let token = try flow.beginRecording()
        let source = FixturePCMSource(), lease = FixtureLease()
        var final: VoiceInputEvent?
        let driver = ProviderPCMVoiceDriver(source: source, coordinator: lease, mayFinish: { true },
                                            onEnd: { _ in flow.discardUnsentRecording(token) },
                                            transcribe: { _, samples in
            try await flow.transcribe(recording: token, samples: samples)
        })
        let captureID = UUID()
        driver.start(id: captureID, mayContinue: { true }, emit: { _, event in final = event })
        check(source.buffer != nil && lease.held, "fixture source acquired shared lease")
        check(source.buffer!.append([Float](repeating: 0.5, count: 8_000), sampleRate: 16_000, channels: 1) == .accepted,
              "fixture PCM captured")
        fake.enqueue(200, "{\"text\":\"fixture transcript\"}")
        driver.finish(id: captureID)
        for _ in 0..<10_000 where final == nil { await Task.yield() }
        check(final == .final("fixture transcript") && !lease.held, "captured PCM produces parsed transcript")
        let recordedIndex = fake.count() - 1
        let recorded = fake.request(recordedIndex)
        let body = recorded.httpBody!
        guard let riff = body.range(of: Data("RIFF".utf8)) else { fatalError("missing WAV") }
        let firstSample = body.index(riff.lowerBound, offsetBy: 44)
        check(body[firstSample] == 0 && body[body.index(after: firstSample)] == 64,
              "multipart WAV contains converted 16-bit fixture audio")


        // Exercise a real captured-PCM path while settings change between
        // transport handoff and the authorized dispatch boundary.
        fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let fencedToken = try flow.beginRecording()
        let fencedRevision = repository.revision
        let fencedSource = FixturePCMSource(), fencedLease = FixtureLease()
        var fencedEvent: VoiceInputEvent?
        let fencedDriver = ProviderPCMVoiceDriver(source: fencedSource, coordinator: fencedLease,
            mayFinish: { repository.revision == fencedRevision },
            onEnd: { _ in flow.discardUnsentRecording(fencedToken) },
            transcribe: { _, samples in try await flow.transcribe(recording: fencedToken, samples: samples) })
        let fencedID = UUID()
        fencedDriver.start(id: fencedID, mayContinue: { true }, emit: { _, event in fencedEvent = event })
        let fencedBuffer = fencedSource.buffer!
        check(fencedBuffer.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1) == .accepted,
              "fenced fixture PCM captured")
        fake.blockBeforeDispatch = true
        fake.enqueue(200, "{\"text\":\"must not dispatch\"}")
        let beforeFenced = fake.count(), expectedFencedCompletion = fake.completed + 1
        fencedDriver.finish(id: fencedID)
        check(fencedSource.buffer == nil && !fencedLease.held &&
              fencedBuffer.append([1], sampleRate: 16_000, channels: 1) == .closed,
              "finishing closes audio and releases its lease before transport")
        await waitBeforeDispatch(fake)
        let windowRepository = ModelSettingsRepository(defaults: defaults, credentials: credentials)
        _ = try windowRepository.save(baseURL: url, model: "pcm-settings-changed", newKey: "")
        fake.releaseBeforeDispatch()
        await waitForCompletions(fake, expectedFencedCompletion)
        for _ in 0..<10_000 where fencedEvent == nil { await Task.yield() }
        check(fake.count() == beforeFenced && fencedEvent == .cancelled,
              "settings changed after capture but before dispatch sends nothing")
        fake.replies.removeAll()

        // The canceled task must close the permit even if its transport is
        // suspended and later returns after cancellation.
        fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let canceledToken = try flow.beginRecording()
        let canceledSource = FixturePCMSource(), canceledLease = FixtureLease()
        var canceledEvent: VoiceInputEvent?
        let canceledDriver = ProviderPCMVoiceDriver(source: canceledSource, coordinator: canceledLease,
            mayFinish: { true }, onEnd: { _ in flow.discardUnsentRecording(canceledToken) },
            transcribe: { _, samples in try await flow.transcribe(recording: canceledToken, samples: samples) })
        let canceledCaptureID = UUID()
        canceledDriver.start(id: canceledCaptureID, mayContinue: { true }, emit: { _, event in canceledEvent = event })
        let canceledBuffer = canceledSource.buffer!
        check(canceledBuffer.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1) == .accepted,
              "cancel fixture PCM captured")
        fake.blockBeforeDispatch = true
        fake.enqueue(200, "{\"text\":\"must not dispatch\"}")
        let beforeCanceledPCM = fake.count(), expectedCanceledCompletion = fake.completed + 1
        canceledDriver.finish(id: canceledCaptureID)
        await waitBeforeDispatch(fake)
        canceledDriver.cancel(id: canceledCaptureID)
        fake.releaseBeforeDispatch()
        await waitForCompletions(fake, expectedCanceledCompletion)
        check(fake.count() == beforeCanceledPCM && canceledEvent == nil && !canceledLease.held &&
              canceledBuffer.append([1], sampleRate: 16_000, channels: 1) == .closed,
              "cancellation before dispatch sends nothing and keeps audio resources closed")
        fake.replies.removeAll()

        // A canceled recording that never reaches transcribe must not leave a
        // reusable one-shot token, and must not clear the provider selection.
        let abandonedToken = try flow.beginRecording()
        let abandonedSource = FixturePCMSource(), abandonedLease = FixtureLease()
        var abandonedEnds = 0
        let abandonedDriver = ProviderPCMVoiceDriver(source: abandonedSource, coordinator: abandonedLease,
            mayFinish: { true }, onEnd: { _ in abandonedEnds += 1; flow.discardUnsentRecording(abandonedToken) },
            transcribe: { _, samples in try await flow.transcribe(recording: abandonedToken, samples: samples) })
        let abandonedID = UUID()
        abandonedDriver.start(id: abandonedID, mayContinue: { true }, emit: { _, _ in })
        let abandonedBuffer = abandonedSource.buffer!
        _ = abandonedBuffer.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        let beforeAbandon = fake.count()
        abandonedDriver.cancel(id: abandonedID)
        abandonedDriver.cancel(id: abandonedID)
        check(abandonedEnds == 1 && !abandonedLease.held && abandonedSource.buffer == nil &&
              abandonedBuffer.append([1], sampleRate: 16_000, channels: 1) == .closed,
              "cancel during capture closes audio and ends exactly once")
        do { _ = try await flow.transcribe(recording: abandonedToken, samples: [Int16](repeating: 1, count: 8_000)); fatalError("abandoned token reused") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        check(fake.count() == beforeAbandon, "abandoned recording cannot dispatch")
        let oldToken = try flow.beginRecording()
        let oldSource = FixturePCMSource(), oldLease = FixtureLease()
        let oldDriver = ProviderPCMVoiceDriver(source: oldSource, coordinator: oldLease,
            mayFinish: { true }, onEnd: { _ in flow.discardUnsentRecording(oldToken) },
            transcribe: { _, samples in try await flow.transcribe(recording: oldToken, samples: samples) })
        let oldCaptureID = UUID()
        oldDriver.start(id: oldCaptureID, mayContinue: { true }, emit: { _, _ in })
        let newToken = try flow.beginRecording()
        oldDriver.cancel(id: oldCaptureID)
        check(!oldLease.held && oldSource.buffer == nil, "old capture releases resources")
        fake.enqueue(200, "{\"text\":\"new recording\"}")
        let recoveredText = try await flow.transcribe(recording: newToken, samples: [Int16](repeating: 1, count: 8_000))
        check(recoveredText == "new recording", "stale cancellation preserves newer recording and provider selection")

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
        let coordinatedChoiceStore = SpeechChoiceStore(defaults: lockDefaults, key: "choice-lock-test")
        try coordinatedChoiceStore.save(.system)
        let choiceSnapshot = try coordinatedChoiceStore.snapshot()
        let choiceBox = ChoiceBox(coordinatedChoiceStore), choiceSignals = DispatchSignals()
        try coordinatedChoiceStore.withUnchanged(choiceSnapshot) {
            DispatchQueue.global().async {
                choiceSignals.started.signal()
                try? choiceBox.store.save(.off)
                choiceSignals.done.signal()
            }
            check(choiceSignals.started.wait(timeout: .now() + 5) == .success, "choice writer attempted mutation")
            check(choiceSignals.done.wait(timeout: .now() + .milliseconds(50)) == .timedOut,
                  "choice mutation cannot split dispatch boundary")
        }
        check(choiceSignals.waitForDone(), "choice write completes after dispatch boundary")
        do { try coordinatedChoiceStore.withUnchanged(choiceSnapshot) {}; fatalError("stale choice accepted") }
        catch SpeechProviderError.invalidConfiguration { count += 1 }

        // Route actual configured provider and PCM driver through synthetic
        // source/transport; no microphone or network service is contacted.
        let routeSuite = "candidate-speech-router-" + UUID().uuidString
        let routeDefaults = UserDefaults(suiteName: routeSuite)!
        defer { routeDefaults.removePersistentDomain(forName: routeSuite) }
        let routeRepo = ModelSettingsRepository(defaults: routeDefaults, credentials: Credentials())
        _ = try routeRepo.save(baseURL: url, model: "chat", newKey: "fixture")
        let routeTransport = FakeTransport(), routeSource = FixturePCMSource(), routeLease = FixtureLease()
        let routeFlow = ConfiguredProviderSpeech(repository: routeRepo, transport: routeTransport)
        let routeSystem = FixtureSystemVoice()
        let routeStore = SpeechChoiceStore(defaults: routeDefaults, key: "test.speech.choice")
        let router = CandidateSpeechRouter(flow: routeFlow, store: routeStore, systemFactory: { routeSystem },
            providerFactory: { mayFinish, onEnd, transcribe in
                ProviderPCMVoiceDriver(source: routeSource, coordinator: routeLease, mayFinish: mayFinish,
                                       onEnd: onEnd, transcribe: transcribe)
            })
        var routeEvents: [(UUID, VoiceInputEvent)] = []
        func startRoute() -> UUID {
            let id = UUID()
            router.start(id: id, mayContinue: { true }, emit: { routeEvents.append(($0, $1)) })
            return id
        }
        let systemID = startRoute()
        check(routeSystem.starts == 1 && routeSource.permissionRequests == 0, "default choice routes to system speech")
        try router.selectOff()
        let savedOffChoice = try routeStore.load()
        check(routeSystem.cancellations == 1 && savedOffChoice == .off,
              "switching off cancels active system driver and persists choice")
        let offID = startRoute()
        check(routeEvents.last?.0 == offID && routeEvents.last?.1 == .failed(.unavailable) &&
              routeSource.permissionRequests == 0, "off requests no provider permission")
        router.cancel(id: systemID)
        routeTransport.enqueue(200, "{\"text\":\"\"}")
        try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "actual-speech-model")
        check(router.choice == .provider(model: "actual-speech-model", method: .audioTranscriptions),
              "successful user probe selects exact model and method")
        let storedChoice = try routeStore.load()
        check(storedChoice == .provider(try SpeechProviderSelection(providerID: "configured-model", model: "actual-speech-model", method: .audioTranscriptions)),
              "successful provider choice persists model and method")
        let choiceData = routeDefaults.data(forKey: "test.speech.choice")!
        check(choiceData.range(of: Data("fixture".utf8)) == nil && choiceData.range(of: Data("speech.invalid".utf8)) == nil,
              "stored choice contains neither credential nor destination")
        let restoredFlow = ConfiguredProviderSpeech(repository: routeRepo, transport: routeTransport)
        let restored = CandidateSpeechRouter(flow: restoredFlow, store: routeStore, systemFactory: { routeSystem },
            providerFactory: { mayFinish, onEnd, transcribe in
                ProviderPCMVoiceDriver(source: routeSource, coordinator: routeLease, mayFinish: mayFinish,
                                       onEnd: onEnd, transcribe: transcribe)
            })
        let restoredID = UUID()
        var restoredEvent: VoiceInputEvent?
        restored.start(id: restoredID, mayContinue: { true }, emit: { _, event in restoredEvent = event })
        check(restored.choice == router.choice && restoredEvent == .failed(.unavailable) && routeTransport.count() == 1,
              "restored provider choice is visible but cannot send until explicitly re-probed")
        let probeRequest = routeTransport.request(0)
        check(probeRequest.url?.absoluteString == "https://speech.invalid/v1/audio/transcriptions" &&
              probeRequest.httpBody?.range(of: Data("actual-speech-model".utf8)) != nil,
              "probe dispatch contains selected model and destination")
        let routedRecording = startRoute()
        check(routeSource.buffer != nil && routeLease.held, "provider selection starts PCM with shared lease")
        _ = routeSource.buffer!.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        routeTransport.enqueue(200, "{\"text\":\"actual transcript\"}")
        router.finish(id: routedRecording)
        for _ in 0..<10_000 where routeEvents.last?.0 != routedRecording { await Task.yield() }
        check(routeEvents.last?.0 == routedRecording && routeEvents.last?.1 == .final("actual transcript") &&
              routeTransport.count() == 2 && !routeLease.held, "provider recording dispatches once and delivers transcript")
        routeTransport.enqueue(401)
        do {
            try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "failed-model")
            fatalError("failed probe selected")
        } catch SpeechProviderError.unauthorized { count += 1 }
        check(router.choice == .provider(model: "actual-speech-model", method: .audioTranscriptions),
              "failed provider probe retains previous choice")
        let beforeCanceledSend = routeTransport.count()
        let canceledRoute = startRoute()
        _ = routeSource.buffer!.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        routeTransport.blockBeforeDispatch = true
        routeTransport.enqueue(200, "{\"text\":\"must not send\"}")
        router.finish(id: canceledRoute)
        await waitBeforeDispatch(routeTransport)
        try router.selectOff()
        routeTransport.releaseBeforeDispatch()
        for _ in 0..<1_000 { await Task.yield() }
        check(routeTransport.count() == beforeCanceledSend && !routeLease.held,
              "switching off before dispatch cancels and prevents audio submission")
        routeTransport.replies.removeAll()
        routeTransport.enqueue(200, "{\"text\":\"\"}")
        try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "actual-speech-model")
        let changedBeforeDispatch = startRoute()
        _ = routeSource.buffer!.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        routeTransport.blockBeforeDispatch = true
        routeTransport.enqueue(200, "{\"text\":\"must not send\"}")
        router.finish(id: changedBeforeDispatch)
        await waitBeforeDispatch(routeTransport)
        let beforeRouteEdit = routeTransport.count()
        _ = try routeRepo.save(baseURL: url, model: "edited-chat", newKey: "edited-fixture")
        routeTransport.releaseBeforeDispatch()
        for _ in 0..<1_000 where routeEvents.last?.0 != changedBeforeDispatch { await Task.yield() }
        check(routeEvents.last?.0 == changedBeforeDispatch && routeEvents.last?.1 == .cancelled &&
              routeTransport.count() == beforeRouteEdit && !routeLease.held,
              "settings and credential change before routed dispatch prevents audio submission")
        routeTransport.replies.removeAll()
        routeTransport.enqueue(200, "{\"text\":\"\"}")
        try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "actual-speech-model")
        let savedProviderChoice = try routeStore.load()
        let choiceChangedCapture = startRoute()
        _ = routeSource.buffer!.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        routeTransport.blockBeforeDispatch = true
        routeTransport.enqueue(200, "{\"text\":\"must not send\"}")
        router.finish(id: choiceChangedCapture)
        await waitBeforeDispatch(routeTransport)
        let beforeChoiceABA = routeTransport.count()
        let otherWindowChoice = SpeechChoiceStore(defaults: routeDefaults, key: "test.speech.choice")
        try otherWindowChoice.save(.off)
        try otherWindowChoice.save(savedProviderChoice)
        routeTransport.releaseBeforeDispatch()
        for _ in 0..<10_000 where routeEvents.last?.0 != choiceChangedCapture { await Task.yield() }
        check(routeEvents.last?.0 == choiceChangedCapture && routeEvents.last?.1 == .cancelled &&
              routeTransport.count() == beforeChoiceABA,
              "other-window off then restore invalidates staged recording before dispatch")
        routeTransport.replies.removeAll()
        routeTransport.blockBeforeDispatch = true
        routeTransport.enqueue(200, "{\"text\":\"must not send\"}")
        let choiceChangedProbe = Task {
            try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "new-speech-model")
        }
        await waitBeforeDispatch(routeTransport)
        let beforeChoiceProbe = routeTransport.count()
        try otherWindowChoice.save(.off)
        routeTransport.releaseBeforeDispatch()
        do { try await choiceChangedProbe.value; fatalError("stale choice probe dispatched") }
        catch SpeechProviderError.invalidConfiguration { count += 1 }
        let otherWindowOff = try routeStore.load()
        check(routeTransport.count() == beforeChoiceProbe && otherWindowOff == .off,
              "other-window off invalidates staged probe before dispatch")
        routeTransport.replies.removeAll()
        routeTransport.enqueue(200, "{\"text\":\"\"}")
        try await router.selectProvider(rawBaseURL: url, kind: .openAICompatible, model: "actual-speech-model")
        let beforeDelayedPermission = routeTransport.count()
        routeSource.delayPermission = true
        let deniedRoute = startRoute()
        routeSource.pendingPermission!(false)
        check(routeEvents.last?.0 == deniedRoute && routeEvents.last?.1 == .failed(.microphoneDenied) &&
              routeSource.buffer == nil && !routeLease.held, "denied microphone permission releases lease")
        let delayedRoute = startRoute()
        let delayedPermission = routeSource.pendingPermission!
        _ = try routeRepo.save(baseURL: "https://changed.invalid/v1", model: "chat", newKey: "changed")
        delayedPermission(true)
        check(routeEvents.last?.0 == delayedRoute && routeEvents.last?.1 == .cancelled && routeSource.buffer == nil &&
              !routeLease.held && routeTransport.count() == beforeDelayedPermission,
              "settings change before permission cannot start recording or dispatch")
        routeSource.delayPermission = false
        let staleRoute = startRoute()
        check(routeEvents.last?.0 == staleRoute && routeEvents.last?.1 == .failed(.unavailable),
              "stale provider does not fall back to system")
        try router.selectSystem()
        let savedSystemChoice = try routeStore.load()
        let replacementSystem = startRoute()
        check(routeSystem.starts == 2 && savedSystemChoice == .system,
              "system speech remains selectable and persists after provider invalidation")
        router.cancel(id: replacementSystem)
        let reused = UUID()
        router.start(id: reused, mayContinue: { true }, emit: { routeEvents.append(($0, $1)) })
        let oldCallback = routeSystem.callbacks.last!.1
        router.start(id: reused, mayContinue: { true }, emit: { routeEvents.append(($0, $1)) })
        let eventCount = routeEvents.count
        oldCallback(reused, .final("stale"))
        check(routeEvents.count == eventCount, "reused ID does not authorize callback from previous system driver")
        routeSystem.callbacks.last!.1(reused, .final("fresh"))
        check(routeEvents.last?.1 == .final("fresh"), "current system driver callback remains usable")
        let otherWindowSystem = UUID()
        router.start(id: otherWindowSystem, mayContinue: { true }, emit: { routeEvents.append(($0, $1)) })
        let systemResult = routeSystem.callbacks.last!.1
        try otherWindowChoice.save(.off)
        systemResult(otherWindowSystem, .final("must be discarded"))
        check(routeEvents.last?.0 == otherWindowSystem && routeEvents.last?.1 == .cancelled,
              "other-window off discards an active system result")
        let staleSystem = startRoute()
        check(routeEvents.last?.0 == staleSystem && routeEvents.last?.1 == .failed(.unavailable),
              "other-window off blocks a new system capture before notification")
        let reentrantSystem = FixtureSystemVoice()
        var reentrantRouter: CandidateSpeechRouter!
        reentrantRouter = CandidateSpeechRouter(flow: routeFlow,
            store: SpeechChoiceStore(defaults: routeDefaults, key: "test.speech.reentrant"), systemFactory: {
            try? reentrantRouter.selectOff()
            return reentrantSystem
        }, providerFactory: { mayFinish, onEnd, transcribe in
            ProviderPCMVoiceDriver(source: routeSource, coordinator: routeLease, mayFinish: mayFinish,
                                   onEnd: onEnd, transcribe: transcribe)
        })
        reentrantRouter.start(id: UUID(), mayContinue: { true }, emit: { _, _ in })
        check(reentrantRouter.choice == .off && reentrantSystem.starts == 0,
              "reentrant selection during driver creation cannot start the old driver")
        routeTransport.enqueue(200, "{\"text\":\"late probe\"}", delayed: true)
        let delayedProbe = Task {
            try await router.selectProvider(rawBaseURL: "https://changed.invalid/v1", kind: .openAICompatible,
                                            model: "late-model")
        }
        await waitForRequest(routeTransport)
        try router.selectOff()
        routeTransport.release()
        do { try await delayedProbe.value; fatalError("late probe replaced off choice") }
        catch is CancellationError { count += 1 }
        let postProbeChoice = try routeStore.load()
        check(router.choice == .off && postProbeChoice == .off,
              "late probe result cannot replace off selection")
        routeDefaults.set(Data("invalid".utf8), forKey: "test.speech.corrupt")
        let corruptStore = SpeechChoiceStore(defaults: routeDefaults, key: "test.speech.corrupt")
        let corruptRouter = CandidateSpeechRouter(flow: routeFlow, store: corruptStore, systemFactory: { routeSystem },
            providerFactory: { mayFinish, onEnd, transcribe in
                ProviderPCMVoiceDriver(source: routeSource, coordinator: routeLease, mayFinish: mayFinish,
                                       onEnd: onEnd, transcribe: transcribe)
            })
        var corruptEvent: VoiceInputEvent?
        corruptRouter.start(id: UUID(), mayContinue: { true }, emit: { _, event in corruptEvent = event })
        check(corruptRouter.choice == .unavailable && corruptEvent == .failed(.unavailable),
              "corrupt stored choice fails closed without system fallback")

        // Exercise the real URLSession task/resume boundary using an
        // intercepting protocol for every URL; no DNS or external network.
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [LocalSpeechURLProtocol.self]
        urlConfiguration.urlCache = nil
        urlConfiguration.httpCookieStorage = nil
        urlConfiguration.urlCredentialStorage = nil
        let isolatedSession = URLSession(configuration: urlConfiguration)
        defer { isolatedSession.invalidateAndCancel() }
        let sessionFlow = ConfiguredProviderSpeech(repository: routeRepo,
            transport: URLSessionSpeechTransport(session: isolatedSession))
        let sessionSource = FixturePCMSource(), sessionLease = FixtureLease()
        let sessionRouter = CandidateSpeechRouter(flow: sessionFlow,
            store: SpeechChoiceStore(defaults: routeDefaults, key: "test.speech.session"), systemFactory: { FixtureSystemVoice() },
            providerFactory: { mayFinish, onEnd, transcribe in
                ProviderPCMVoiceDriver(source: sessionSource, coordinator: sessionLease, mayFinish: mayFinish,
                                       onEnd: onEnd, transcribe: transcribe)
            })
        let interceptedBefore = LocalSpeechURLProtocol.recorder.snapshot().count
        try await sessionRouter.selectProvider(rawBaseURL: "https://changed.invalid/v1", kind: .openAICompatible,
                                               model: "selected-session-model")
        let sessionID = UUID()
        var sessionEvent: VoiceInputEvent?
        sessionRouter.start(id: sessionID, mayContinue: { true }, emit: { _, event in sessionEvent = event })
        _ = sessionSource.buffer!.append([Float](repeating: 0.125, count: 8_000), sampleRate: 16_000, channels: 1)
        sessionRouter.finish(id: sessionID)
        for _ in 0..<200 where sessionEvent == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let intercepted = LocalSpeechURLProtocol.recorder.snapshot()
        check(sessionEvent == .final("local transcript") && intercepted.count == interceptedBefore + 2,
              "real URLSession task dispatches probe and synthetic recording through local interceptor")
        let sentRequest = intercepted.last!
        check(sentRequest.url?.absoluteString == "https://changed.invalid/v1/audio/transcriptions" &&
              sentRequest.httpBody?.range(of: Data("selected-session-model".utf8)) != nil &&
              sentRequest.httpBody?.range(of: Data("RIFF".utf8)) != nil &&
              sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer changed" &&
              !sentRequest.httpShouldHandleCookies && !sessionLease.held,
              "actual dispatch uses selected destination/model, WAV and credential with cookies disabled")
        print("PASS configured provider flow: \(count) checks; isolated defaults, fixture credentials and fake transport")
    }
}
