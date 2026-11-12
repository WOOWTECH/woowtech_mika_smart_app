import Foundation

/// A description to display for an explicit, per-recording upload decision.
/// The ID identifies actor-owned state, not a reusable authorization token.
public struct SpeechUploadReview: Sendable, Equatable {
    public let id: UUID
    public let providerID: String
    public let providerKind: SpeechProviderKind
    public let destination: String
    public let model: String
    public let method: SpeechProviderMethod
    public let credentialVersion: UUID
    public let recordingID: UUID
    public let audioBytes: Int
    public let language: String?
}

public enum SpeechUploadConsentError: Error, Equatable, Sendable {
    case inactive, missingSettings, missingRecording, invalidState, staleReview
}

public enum SpeechUploadConsentState: Equatable, Sendable {
    case inactive, idle, awaitingConfirmation, confirmed, uploading, completed, failed
}

/// Waiting for settlement has no authority to start, cancel, or retry a request.
public struct SpeechUploadAttempt: Sendable {
    public let id: UUID
    private let task: Task<Void, Never>
    fileprivate init(id: UUID, task: Task<Void, Never>) { self.id = id; self.task = task }
    public func waitUntilSettled() async { await task.value }
}

/// Isolated consent state for a future host integration. All settings and audio
/// for an attempt are owned by this actor, rather than supplied again by a caller
/// after confirmation. No default transport, recorder, persistence, or UI is used.
public actor SpeechUploadConsentCoordinator {
    private struct Settings {
        let endpoint: SpeechProviderEndpoint
        let selection: SpeechProviderSelection
        let apiKey: String?
        let language: String?
        let credentialVersion: UUID
    }
    private struct Recording {
        let id: UUID
        let wav: Data
    }
    private enum Phase {
        case idle
        case review(SpeechUploadReview)
        case confirmed(SpeechUploadReview)
        case sending(UUID)
        case completed(UUID, String)
        case failed(UUID, SpeechProviderError)
    }
    private let transport: any SpeechProviderTransport
    private var active = false
    private var settings: Settings?
    private var recording: Recording?
    private var phase: Phase = .idle
    private var activeTask: Task<Void, Never>?

    public init(transport: any SpeechProviderTransport) { self.transport = transport }
    deinit { activeTask?.cancel() }

    /// Start inactive. On leaving the active scene, revoke all reviews and
    /// in-flight work and discard both the recording and in-memory settings.
    public func setForeground(_ foreground: Bool) {
        active = foreground
        if !foreground {
            revoke()
            recording = nil
            settings = nil
        }
    }

    /// Every settings publication mints a new version, even when the key or
    /// other inputs appear unchanged. The host must route *all* settings/key
    /// changes through this authority and invalidate on external changes.
    public func updateSettings(endpoint: SpeechProviderEndpoint, selection: SpeechProviderSelection,
                               apiKey: String?, language: String? = nil) throws {
        revoke()
        settings = nil
        guard active else { throw SpeechUploadConsentError.inactive }
        settings = Settings(endpoint: endpoint, selection: selection, apiKey: apiKey,
                            language: language, credentialVersion: UUID())
    }

    /// Copy a canonical recording into this actor. A new recording always
    /// revokes the previous review, even if it contains identical bytes.
    @discardableResult
    public func setRecording(wav: Data) throws -> UUID {
        revoke()
        recording = nil
        guard active else { throw SpeechUploadConsentError.inactive }
        guard wav.count <= 44 + SpeechWAV.maxSamples * 2 else { throw SpeechProviderError.invalidAudio }
        let copied = wav.withUnsafeBytes { Data($0) }
        guard SpeechWAV.isCanonical(copied) else { throw SpeechProviderError.invalidAudio }
        let value = Recording(id: UUID(), wav: copied)
        recording = value
        return value.id
    }

    /// Preparing or re-preparing never starts a transfer. The exact URL shown
    /// is constructed by the same request builder used immediately before send.
    public func prepareReview() throws -> SpeechUploadReview {
        guard active else { throw SpeechUploadConsentError.inactive }
        if case .sending = phase { throw SpeechUploadConsentError.invalidState }
        return try makeReview()
    }

    private func makeReview() throws -> SpeechUploadReview {
        // A failed replacement cannot leave an older confirmation usable.
        revoke()
        guard let settings else { throw SpeechUploadConsentError.missingSettings }
        guard let recording else { throw SpeechUploadConsentError.missingRecording }
        let request = try SpeechProviderRequest.make(endpoint: settings.endpoint, selection: settings.selection,
                                                     apiKey: settings.apiKey, wav: recording.wav, language: settings.language)
        guard let destination = request.url?.absoluteString else { throw SpeechProviderError.invalidConfiguration }
        let review = SpeechUploadReview(id: UUID(), providerID: settings.selection.providerID,
            providerKind: settings.endpoint.kind, destination: destination, model: settings.selection.model,
            method: settings.selection.method, credentialVersion: settings.credentialVersion,
            recordingID: recording.id, audioBytes: recording.wav.count, language: settings.language)
        phase = .review(review)
        return review
    }

    /// Only an explicit host UI action should invoke this method. The actor
    /// rejects stale, copied, repeated, replaced, or backgrounded reviews.
    public func confirm(reviewID: UUID) throws {
        guard active else { throw SpeechUploadConsentError.inactive }
        guard case .review(let review) = phase, review.id == reviewID else { throw SpeechUploadConsentError.staleReview }
        phase = .confirmed(review)
    }

    /// Consume one confirmation, re-create and revalidate the exact request,
    /// and start at most one attempt. A retry requires a fresh review.
    public func start(reviewID: UUID) throws -> SpeechUploadAttempt {
        guard active else { throw SpeechUploadConsentError.inactive }
        guard case .confirmed(let review) = phase, review.id == reviewID else { throw SpeechUploadConsentError.staleReview }
        guard let settings, let recording,
              settings.credentialVersion == review.credentialVersion, recording.id == review.recordingID else {
            revoke(); throw SpeechUploadConsentError.staleReview
        }
        let request: URLRequest
        do {
            request = try SpeechProviderRequest.make(endpoint: settings.endpoint, selection: settings.selection,
                                                      apiKey: settings.apiKey, wav: recording.wav, language: settings.language)
            guard request.url?.absoluteString == review.destination,
                  settings.selection.providerID == review.providerID, settings.endpoint.kind == review.providerKind,
                  settings.selection.model == review.model, settings.selection.method == review.method,
                  settings.language == review.language, recording.wav.count == review.audioBytes else {
                throw SpeechUploadConsentError.staleReview
            }
        } catch {
            revoke(); throw error
        }
        let id = UUID(), method = settings.selection.method, transport = self.transport
        phase = .sending(id)
        let task = Task { [weak self] in
            let result: Result<String, SpeechProviderError>
            do {
                try Task.checkCancellation()
                let (data, status) = try await transport.send(request)
                try Task.checkCancellation()
                result = .success(try SpeechProviderRequest.parse(data, status: status, method: method))
            } catch let error as SpeechProviderError { result = .failure(error) }
            catch { result = .failure(.transport) }
            await self?.settle(id: id, result: result)
        }
        activeTask = task
        return SpeechUploadAttempt(id: id, task: task)
    }

    /// Cancel invalidates confirmation and any active attempt. The recording is
    /// retained for an explicit retry; discardRecording removes it instead.
    public func cancel() { revoke() }
    public func discardRecording() { revoke(); recording = nil }

    public var state: SpeechUploadConsentState {
        guard active else { return .inactive }
        switch phase {
        case .idle: return .idle
        case .review: return .awaitingConfirmation
        case .confirmed: return .confirmed
        case .sending: return .uploading
        case .completed: return .completed
        case .failed: return .failed
        }
    }

    /// A stale attempt cannot retrieve the result of a later attempt.
    public func takeTranscript(attemptID: UUID) -> String? {
        guard case .completed(let id, let text) = phase, id == attemptID else { return nil }
        phase = .idle
        return text
    }
    public func failure(attemptID: UUID) -> SpeechProviderError? {
        guard case .failed(let id, let error) = phase, id == attemptID else { return nil }
        return error
    }

    private func revoke() {
        activeTask?.cancel(); activeTask = nil
        phase = .idle
    }
    private func settle(id: UUID, result: Result<String, SpeechProviderError>) {
        guard active, case .sending(let current) = phase, current == id else { return }
        activeTask = nil
        switch result {
        case .success(let text): phase = .completed(id, text)
        case .failure(let error): phase = .failed(id, error)
        }
    }
}
