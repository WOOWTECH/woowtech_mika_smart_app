import AssistantModels
import Foundation

/// An isolated integration seam, not yet connected to the composer or settings UI.
/// The owner must cancel it on settings, scene, and gesture changes before use
/// with real audio. Its transport may already have received bytes when canceled.
@MainActor
final class ConfiguredProviderSpeech {
    enum Failure: Error, Equatable { case unavailable, stale, invalidAttempt }
    typealias DispatchGate = (@escaping @MainActor () throws -> Void) throws -> Void

    private struct Binding: Equatable {
        let base: String
        let chatModel: String
        let account: String
        let revision: String
    }
    private struct Verified {
        let binding: Binding
        let endpoint: SpeechProviderEndpoint
        let selection: SpeechProviderSelection
    }
    private let repository: ModelSettingsRepository
    private let transport: any AuthorizedSpeechProviderTransport
    private var generation = UUID()
    private var verified: Verified?
    private var attempt: UUID?
    private var pending: (id: UUID, task: Task<String, Error>)?

    init(repository: ModelSettingsRepository, transport: any AuthorizedSpeechProviderTransport) {
        self.repository = repository
        self.transport = transport
    }

    private func current() throws -> (SavedModelSettings, Binding) {
        guard let record = try repository.load() else { throw Failure.unavailable }
        return (record, Binding(base: record.baseURL.absoluteString, chatModel: record.model,
                                account: record.credentialAccount, revision: repository.revision))
    }
    private func check(_ binding: Binding, generation: UUID) throws {
        try Task.checkCancellation()
        guard self.generation == generation, let (_, now) = try? current(), now == binding else {
            throw Failure.stale
        }
    }

    private func send(endpoint: SpeechProviderEndpoint, selection: SpeechProviderSelection,
                      key: String, wav: Data, binding: Binding, generation: UUID,
                      dispatchGate: DispatchGate? = nil) async throws -> String {
        let id = UUID()
        let request = try SpeechProviderRequest.make(endpoint: endpoint, selection: selection, apiKey: key, wav: wav)
        let permit = SpeechDispatchPermit { [weak self] dispatch in
            guard let self else { throw Failure.stale }
            try ModelSettingsRepository.withSpeechDispatchLock {
                try self.check(binding, generation: generation)
                if let dispatchGate { try dispatchGate(dispatch) }
                else { try dispatch() }
            }
        }
        let transport = self.transport
        let task = Task {
            try await withTaskCancellationHandler {
                let (data, status) = try await transport.send(request, permit: permit)
                try Task.checkCancellation()
                return try SpeechProviderRequest.parse(data, status: status, method: selection.method)
            } onCancel: { permit.cancellation.cancel() }
        }
        pending = (id, task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    /// Call only in response to a user choosing to test a disclosed destination.
    /// The one-second silence can use provider quota. No request is made on init.
    func probe(rawBaseURL: String, kind: SpeechProviderKind, model: String,
               dispatchGate: DispatchGate? = nil) async throws -> SpeechProviderMethod {
        // As on Android, a failed selection probe leaves the previous working
        // choice in place; it still has to match the live settings to be used.
        pending?.task.cancel()
        generation = UUID()
        attempt = nil
        let operation = generation
        let (record, binding) = try current()
        let endpoint = try SpeechProviderEndpoint.reviewSaved(providerID: "configured-model", kind: kind,
                                                                 rawBaseURL: rawBaseURL, savedBaseURL: record.baseURL)
        let key = try repository.key(for: record)
        let wav = try SpeechWAV.encode([Int16](repeating: 0, count: SpeechWAV.sampleRate))
        let methods: [SpeechProviderMethod] = kind == .gemini ? [.geminiInline] :
            [.audioTranscriptions, .chatInputAudio, .chatInputAudioURI, .chatInputAudioOnly]
        for method in methods {
            let selection = try SpeechProviderSelection(providerID: endpoint.providerID, model: model, method: method)
            try check(binding, generation: operation)
            do {
                _ = try await send(endpoint: endpoint, selection: selection, key: key, wav: wav,
                                   binding: binding, generation: operation, dispatchGate: dispatchGate)
                try check(binding, generation: operation)
                verified = Verified(binding: binding, endpoint: endpoint, selection: selection)
                return method
            } catch let error as SpeechProviderError {
                try check(binding, generation: operation)
                switch error {
                case .unsupported, .invalidResponse: continue
                default: throw error
                }
            }
        }
        throw SpeechProviderError.unsupported
    }

    /// One token per explicit recording gesture; a token is consumed before
    /// sending and cannot authorize another recording or an automatic retry.
    func beginRecording() throws -> UUID {
        guard let verified else { throw Failure.unavailable }
        try check(verified.binding, generation: generation)
        // A newer gesture supersedes any older response still in flight.
        pending?.task.cancel()
        generation = UUID()
        let id = UUID()
        attempt = id
        return id
    }

    /// Live snapshot check for permission and recording gates. A host must
    /// still call invalidate when settings or scene notifications arrive.
    func isCurrentSelection() -> Bool {
        guard let verified else { return false }
        return (try? check(verified.binding, generation: generation)) != nil
    }

    /// Abandon an unsent recording without discarding the verified provider.
    /// A stale recording must never revoke a newer gesture's authorization.
    func discardUnsentRecording(_ id: UUID) {
        guard attempt == id else { return }
        attempt = nil
        generation = UUID()
    }

    func transcribe(recording id: UUID, samples: [Int16], dispatchGate: DispatchGate? = nil) async throws -> String {
        guard let verified, attempt == id else { throw Failure.invalidAttempt }
        attempt = nil
        let operation = generation
        try check(verified.binding, generation: operation)
        // Match Android: accidental sub-500 ms recordings are not uploaded.
        if samples.count < SpeechWAV.sampleRate / 2 { return "" }
        let (record, _) = try current()
        let key = try repository.key(for: record)
        let wav = try SpeechWAV.encode(samples)
        try check(verified.binding, generation: operation)
        let text = try await send(endpoint: verified.endpoint, selection: verified.selection, key: key, wav: wav,
                                  binding: verified.binding, generation: operation, dispatchGate: dispatchGate)
        try check(verified.binding, generation: operation)
        return text
    }

    func invalidate() {
        pending?.task.cancel()
        generation = UUID()
        verified = nil
        attempt = nil
    }
}
