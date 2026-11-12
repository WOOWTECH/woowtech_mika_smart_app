import Foundation

actor SyntheticTransport: SpeechProviderTransport {
    private var requests: [URLRequest] = []
    private var waiting: [Int: CheckedContinuation<(Data, Int), Never>] = [:]
    private var cancellationObserved: [Int: Bool] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let id = requests.count
        requests.append(request)
        // Intentionally ignores cancellation so the coordinator must reject
        // late results even from a non-cooperative injected transport.
        let result: (Data, Int) = await withCheckedContinuation { continuation in
            Task { self.install(continuation, id: id) }
        }
        cancellationObserved[id] = Task.isCancelled
        return result
    }
    private func install(_ continuation: CheckedContinuation<(Data, Int), Never>, id: Int) {
        waiting[id] = continuation
    }
    func count() -> Int { requests.count }
    func hasWaiting(_ id: Int) -> Bool { waiting[id] != nil }
    func observedCancellation(_ id: Int) -> Bool { cancellationObserved[id] == true }
    func request(_ id: Int) -> URLRequest { requests[id] }
    func release(_ id: Int, status: Int = 200, text: String = "synthetic") {
        guard let continuation = waiting.removeValue(forKey: id) else { fatalError("missing synthetic request") }
        let body = try! JSONSerialization.data(withJSONObject: ["text": text])
        continuation.resume(returning: (body, status))
    }
}

@main @MainActor struct SpeechUploadConsentChecks {
    static var checks = 0
    static func check(_ condition: Bool, _ description: String) {
        precondition(condition, description); checks += 1
    }
    static func expect(_ expected: SpeechUploadConsentError,
                       _ operation: () async throws -> Void) async {
        do { try await operation(); fatalError("expected consent error") }
        catch let error as SpeechUploadConsentError { check(error == expected, "wrong consent error") }
        catch { fatalError("unexpected error: \(error)") }
    }
    static func waitForRequests(_ count: Int, _ transport: SyntheticTransport) async throws {
        for _ in 0..<500 {
            if await transport.hasWaiting(count - 1) { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        fatalError("synthetic request did not start")
    }
    nonisolated static func tryStart(_ coordinator: SpeechUploadConsentCoordinator, _ id: UUID) async -> SpeechUploadAttempt? {
        try? await coordinator.start(reviewID: id)
    }
    nonisolated static func tryConfirm(_ coordinator: SpeechUploadConsentCoordinator, _ id: UUID) async -> Bool {
        do { try await coordinator.confirm(reviewID: id); return true } catch { return false }
    }
    static func main() async throws {
        let transport = SyntheticTransport()
        let coordinator = SpeechUploadConsentCoordinator(transport: transport)
        let endpoint = try SpeechProviderEndpoint.reviewNew(providerID: "p", kind: .openAICompatible,
                                                             rawBaseURL: "https://speech.example.invalid:443/v1")
        let selection = try SpeechProviderSelection(providerID: "p", model: "model-a", method: .audioTranscriptions)
        var source = try SpeechWAV.encode([1, 2, 3, 4])
        let original = source
        await expect(.inactive) { _ = try await coordinator.prepareReview() }
        await expect(.inactive) { try await coordinator.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a") }
        await coordinator.setForeground(true)
        await expect(.missingSettings) { _ = try await coordinator.prepareReview() }
        try await coordinator.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a", language: "en")
        await expect(.missingRecording) { _ = try await coordinator.prepareReview() }
        let recordingID = try await coordinator.setRecording(wav: source)
        source[source.count - 1] ^= 0xff
        let first = try await coordinator.prepareReview()
        let copiedFirst = first
        check(first.providerID == "p" && first.providerKind == .openAICompatible, "provider reviewed")
        check(first.destination == "https://speech.example.invalid:443/v1/audio/transcriptions", "exact final destination reviewed")
        check(first.model == "model-a" && first.method == .audioTranscriptions && first.language == "en", "model, method, language reviewed")
        check(first.recordingID == recordingID && first.audioBytes == original.count, "specific recording reviewed")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: first.id) }
        check(await transport.count() == 0, "review alone never sends")
        try await coordinator.confirm(reviewID: first.id)
        await expect(.staleReview) { try await coordinator.confirm(reviewID: copiedFirst.id) }
        let replaced = try await coordinator.prepareReview()
        check(first.id != replaced.id, "new review has new identity")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: copiedFirst.id) }
        try await coordinator.confirm(reviewID: replaced.id)
        let secondRecordingID = try await coordinator.setRecording(wav: original)
        check(secondRecordingID != recordingID, "identical bytes still a different recording")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: replaced.id) }
        let invalidation = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: invalidation.id)
        do { _ = try await coordinator.setRecording(wav: Data([0, 1])); fatalError("invalid audio accepted") }
        catch let error as SpeechProviderError { check(error == .invalidAudio, "invalid recording rejected") }
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: invalidation.id) }
        await expect(.missingRecording) { _ = try await coordinator.prepareReview() }
        _ = try await coordinator.setRecording(wav: original)

        // Changes are publications, not equality comparisons: even an ABA or
        // identical re-save invalidates the previous confirmation and version.
        let variantEndpoint = try SpeechProviderEndpoint.reviewNew(providerID: "p", kind: .openAICompatible,
                                                                    rawBaseURL: "https://speech.example.invalid/v1")
        let variantModel = try SpeechProviderSelection(providerID: "p", model: "model-b", method: .audioTranscriptions)
        let variantMethod = try SpeechProviderSelection(providerID: "p", model: "model-a", method: .chatInputAudio)
        let changes: [(SpeechProviderEndpoint, SpeechProviderSelection, String?, String?)] = [
            (variantEndpoint, selection, "fake-key-a", "en"),
            (endpoint, variantModel, "fake-key-a", "en"),
            (endpoint, variantMethod, "fake-key-a", "en"),
            (endpoint, selection, "fake-key-b", "en"),
            (endpoint, selection, "fake-key-a", "zh"),
            (endpoint, selection, "fake-key-a", "en"),
            (endpoint, selection, "fake-key-a", "en")
        ]
        for (newEndpoint, newSelection, key, language) in changes {
            let old = try await coordinator.prepareReview()
            try await coordinator.confirm(reviewID: old.id)
            try await coordinator.updateSettings(endpoint: newEndpoint, selection: newSelection, apiKey: key, language: language)
            await expect(.staleReview) { _ = try await coordinator.start(reviewID: old.id) }
            let fresh = try await coordinator.prepareReview()
            check(old.credentialVersion != fresh.credentialVersion, "each settings publication gets new credential version")
        }
        let cross = SpeechUploadConsentCoordinator(transport: transport)
        await cross.setForeground(true)
        try await cross.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a", language: "en")
        _ = try await cross.setRecording(wav: original)
        let foreign = try await cross.prepareReview()
        await expect(.staleReview) { try await coordinator.confirm(reviewID: foreign.id) }
        let cancelled = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: cancelled.id)
        await coordinator.cancel()
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: cancelled.id) }
        let retry = try await coordinator.prepareReview()
        check(retry.recordingID == cancelled.recordingID && retry.id != cancelled.id, "cancelled recording requires new review")
        try await coordinator.confirm(reviewID: retry.id)
        let attemptA = try await coordinator.start(reviewID: retry.id)
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: retry.id) }
        await expect(.invalidState) { _ = try await coordinator.prepareReview() }
        try await waitForRequests(1, transport)
        let actual = await transport.request(0)
        check(actual.url?.absoluteString == retry.destination, "sent exact reviewed destination")
        check(actual.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key-a", "sent reviewed credential snapshot")
        check(actual.httpBody?.range(of: original) != nil && actual.httpBody?.range(of: source) == nil, "sent copied recording bytes")
        check(actual.httpBody?.range(of: Data("model-a".utf8)) != nil, "sent reviewed model")

        // Old transport ignores cancellation and returns while the new attempt
        // is in flight. Await its handle to prove the callback has settled.
        try await coordinator.updateSettings(endpoint: variantEndpoint, selection: variantModel, apiKey: "fake-key-b", language: nil)
        let newReview = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: newReview.id)
        let attemptB = try await coordinator.start(reviewID: newReview.id)
        try await waitForRequests(2, transport)
        await transport.release(0, text: "stale")
        await attemptA.waitUntilSettled()
        check(await transport.observedCancellation(0), "settings change cancelled old task")
        check(await coordinator.state == .uploading, "late old result did not overwrite new upload")
        check(await coordinator.takeTranscript(attemptID: attemptA.id) == nil, "late old transcript discarded")
        let actualB = await transport.request(1)
        check(actualB.url?.absoluteString == newReview.destination && actualB.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key-b", "new settings bound to new request")
        await transport.release(1, text: "new")
        await attemptB.waitUntilSettled()
        check(await coordinator.state == .completed, "new attempt completed")
        check(await coordinator.takeTranscript(attemptID: attemptA.id) == nil, "wrong attempt cannot read transcript")
        check(await coordinator.takeTranscript(attemptID: attemptB.id) == "new", "correct attempt reads transcript")
        check(await coordinator.takeTranscript(attemptID: attemptB.id) == nil, "transcript consumed once")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: newReview.id) }
        check(await transport.count() == 2, "no implicit retry")

        let backgroundReview = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: backgroundReview.id)
        await coordinator.setForeground(false)
        await expect(.inactive) { _ = try await coordinator.start(reviewID: backgroundReview.id) }
        await coordinator.setForeground(true)
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: backgroundReview.id) }
        await expect(.missingSettings) { _ = try await coordinator.prepareReview() }
        try await coordinator.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a")
        await expect(.missingRecording) { _ = try await coordinator.prepareReview() }
        _ = try await coordinator.setRecording(wav: original)
        let backgroundSending = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: backgroundSending.id)
        let attemptC = try await coordinator.start(reviewID: backgroundSending.id)
        try await waitForRequests(3, transport)
        await coordinator.setForeground(false)
        await coordinator.setForeground(true)
        await transport.release(2, text: "background-late")
        await attemptC.waitUntilSettled()
        check(await transport.observedCancellation(2), "background cancelled active task")
        check(await coordinator.state == .idle, "background-late result suppressed")
        check(await coordinator.takeTranscript(attemptID: attemptC.id) == nil, "background-late transcript discarded")
        check(await transport.count() == 3, "background did not retry")

        // Two simultaneous starts with the same confirmed review: exactly one
        // attempt may consume the actor's confirmation.
        try await coordinator.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a")
        _ = try await coordinator.setRecording(wav: original)
        let raceReview = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: raceReview.id)
        async let x = tryStart(coordinator, raceReview.id)
        async let y = tryStart(coordinator, raceReview.id)
        let (xResult, yResult) = await (x, y)
        check((xResult == nil) != (yResult == nil), "confirmation consumed once under concurrent start")
        let raceAttempt = (xResult ?? yResult)!
        try await waitForRequests(4, transport)
        await transport.release(3, status: 500)
        await raceAttempt.waitUntilSettled()
        check(await coordinator.failure(attemptID: raceAttempt.id) == .provider(status: 500), "error sanitized and tied to attempt")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: raceReview.id) }
        let errorRetry = try await coordinator.prepareReview()
        check(errorRetry.id != raceReview.id, "failure retry requires new review")
        await coordinator.discardRecording()
        await expect(.staleReview) { try await coordinator.confirm(reviewID: errorRetry.id) }
        await expect(.missingRecording) { _ = try await coordinator.prepareReview() }
        _ = try await coordinator.setRecording(wav: original)
        let cancelReview = try await coordinator.prepareReview()
        try await coordinator.confirm(reviewID: cancelReview.id)
        let cancelledAttempt = try await coordinator.start(reviewID: cancelReview.id)
        try await waitForRequests(5, transport)
        await coordinator.cancel()
        await transport.release(4, text: "cancel-late")
        await cancelledAttempt.waitUntilSettled()
        check(await transport.observedCancellation(4), "user cancellation reached active task")
        check(await coordinator.state == .idle, "late callback after user cancellation rejected")
        check(await coordinator.takeTranscript(attemptID: cancelledAttempt.id) == nil, "cancelled attempt has no transcript")
        await expect(.staleReview) { _ = try await coordinator.start(reviewID: cancelReview.id) }
        let afterCancel = try await coordinator.prepareReview()
        check(afterCancel.recordingID == cancelReview.recordingID && afterCancel.id != cancelReview.id,
              "user retry of same recording needs fresh review")
        for _ in 0..<20 {
            let pending = try await coordinator.prepareReview()
            async let confirmation = tryConfirm(coordinator, pending.id)
            try await coordinator.updateSettings(endpoint: endpoint, selection: selection, apiKey: "fake-key-a")
            _ = await confirmation
            await expect(.staleReview) { _ = try await coordinator.start(reviewID: pending.id) }
        }
        check(await transport.count() == 5, "settings/confirmation races never start a request")
        print("PASS speech upload consent: \(checks) checks; synthetic transport only")
    }
}
