import AssistantModels
import Foundation

private final class Credentials: ModelCredentialStoring {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values.removeAll() }
}

private actor FakeTransport: SpeechProviderTransport {
    struct Reply { let status: Int; let data: Data; let delayed: Bool }
    var replies: [Reply] = []
    var requests: [URLRequest] = []
    var waiting: CheckedContinuation<Void, Never>?
    func enqueue(_ status: Int, _ body: String = "{}", delayed: Bool = false) {
        replies.append(Reply(status: status, data: Data(body.utf8), delayed: delayed))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        precondition(!replies.isEmpty, "unexpected request")
        let reply = replies.removeFirst()
        if reply.delayed { await withCheckedContinuation { waiting = $0 } }
        return (reply.data, reply.status)
    }
    func release() { waiting?.resume(); waiting = nil }
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
                if await fake.isWaiting() { return }
                await Task.yield()
            }
            fatalError("fake transport did not receive request")
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
        check(await fake.count() == 0, "initialization must not contact a provider")
        do { _ = try flow.beginRecording(); fatalError("unverified") } catch ConfiguredProviderSpeech.Failure.unavailable { count += 1 }
        do { _ = try await flow.probe(rawBaseURL: "https://other.invalid/v1", kind: .openAICompatible, model: "speech-model"); fatalError("mismatched URL") }
        catch SpeechProviderError.invalidConfiguration { count += 1 }
        check(await fake.count() == 0, "unreviewed URL must not transmit")
        await fake.enqueue(404)
        await fake.enqueue(200, "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}")
        let method = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        check(method == .chatInputAudio, "fallback selects successful method")
        let first = await fake.request(0)
        check(first.url?.absoluteString == url + "/audio/transcriptions", "bound configured destination")
        check(first.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "uses stored fixture credential")
        check(first.httpBody?.range(of: Data("RIFF".utf8)) != nil, "probe includes WAV")
        let second = await fake.request(1)
        check(second.url?.absoluteString == url + "/chat/completions", "fallback endpoint")
        let short = try flow.beginRecording()
        let empty = try await flow.transcribe(recording: short, samples: [1, -1])
        let afterShort = await fake.count()
        check(empty == "" && afterShort == 2, "short recording must not be uploaded")
        let id = try flow.beginRecording()
        await fake.enqueue(200, "{\"choices\":[{\"message\":{\"content\":\" transcript \"}}]}")
        let text = try await flow.transcribe(recording: id, samples: [Int16](repeating: 1, count: 8_000))
        check(text == "transcript", "transcription returned")
        do { _ = try await flow.transcribe(recording: id, samples: [1]); fatalError("reused") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        await fake.enqueue(401)
        do { _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "other-model"); fatalError("unauthorized") }
        catch SpeechProviderError.unauthorized { count += 1 }
        let retained = try flow.beginRecording()
        let retainedText = try await flow.transcribe(recording: retained, samples: [1])
        check(retainedText.isEmpty, "failed probe retains prior selection")
        let old = try flow.beginRecording()
        let next = try flow.beginRecording()
        do { _ = try await flow.transcribe(recording: old, samples: [1]); fatalError("superseded") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        flow.invalidate()
        do { _ = try await flow.transcribe(recording: next, samples: [1]); fatalError("cancelled") }
        catch ConfiguredProviderSpeech.Failure.invalidAttempt { count += 1 }
        await fake.enqueue(401)
        do { _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model"); fatalError("unauthorized") }
        catch SpeechProviderError.unauthorized { count += 1 }
        check(await fake.count() == 5, "unauthorized does not fall back")
        await fake.enqueue(200, "{\"text\":\"ok\"}", delayed: true)
        let delayed = Task { try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model") }
        await waitForRequest(fake)
        _ = try repository.save(baseURL: url, model: "changed", newKey: "")
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "")
        await fake.release()
        do { _ = try await delayed.value; fatalError("ABA settings accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        do { _ = try flow.beginRecording(); fatalError("stale probe authorized") }
        catch ConfiguredProviderSpeech.Failure.unavailable { count += 1 }
        await fake.enqueue(200, "{\"text\":\"ok\"}", delayed: true)
        let cancelled = Task { try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model") }
        await waitForRequest(fake)
        flow.invalidate()
        await fake.release()
        do { _ = try await cancelled.value; fatalError("late success accepted") }
        catch is CancellationError { count += 1 }
        await fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let recording = try flow.beginRecording()
        await fake.enqueue(200, "{\"text\":\"late\"}", delayed: true)
        let result = Task { try await flow.transcribe(recording: recording, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        flow.invalidate()
        await fake.release()
        do { _ = try await result.value; fatalError("late transcript accepted") }
        catch is CancellationError { count += 1 }
        await fake.enqueue(200, "{\"text\":\"ok\"}")
        _ = try await flow.probe(rawBaseURL: url, kind: .openAICompatible, model: "speech-model")
        let previous = try flow.beginRecording()
        await fake.enqueue(200, "{\"text\":\"old\"}", delayed: true)
        let oldResult = Task { try await flow.transcribe(recording: previous, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        let newer = try flow.beginRecording()
        await fake.release()
        do { _ = try await oldResult.value; fatalError("superseded result accepted") }
        catch is CancellationError { count += 1 }
        let newText = try await flow.transcribe(recording: newer, samples: [1])
        check(newText.isEmpty, "newer attempt remains usable")
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "replacement-fixture")
        do { _ = try flow.beginRecording(); fatalError("changed credential accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        await fake.enqueue(200, "{\"candidates\":[{\"content\":{\"parts\":[]}}]}")
        let gemini = try await flow.probe(rawBaseURL: url, kind: .gemini, model: "gemini-fixture")
        check(gemini == .geminiInline, "explicit Gemini choice uses Gemini method")
        let lastIndex = await fake.count() - 1
        let geminiRequest = await fake.request(lastIndex)
        check(geminiRequest.url?.absoluteString == url + "/v1beta/models/gemini-fixture:generateContent", "Gemini destination")
        check(geminiRequest.value(forHTTPHeaderField: "x-goog-api-key") == "replacement-fixture", "new key used only after new probe")
        let changing = try flow.beginRecording()
        await fake.enqueue(200, "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"old\"}]}}]}", delayed: true)
        let changingResult = Task { try await flow.transcribe(recording: changing, samples: [Int16](repeating: 1, count: 8_000)) }
        await waitForRequest(fake)
        _ = try repository.save(baseURL: url, model: "chat-model", newKey: "third-fixture")
        await fake.release()
        do { _ = try await changingResult.value; fatalError("old credential result accepted") }
        catch ConfiguredProviderSpeech.Failure.stale { count += 1 }
        print("PASS configured provider flow: \(count) checks; isolated defaults, fixture credentials and fake transport")
    }
}
