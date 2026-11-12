import Foundation

/// The source is controlled on the main actor; its audio callback may append
/// to the supplied thread-safe buffer from another thread. stop() must stop
/// capture synchronously before returning, including on lease revocation. A
/// source must arm interruption observation before calling activate, and check
/// mayStart immediately before starting its capture engine. An activation
/// failure must stop setup; callers clean up through onFailure or cancellation.
@MainActor
protocol ProviderPCMSource: AnyObject {
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void)
    func start(buffer: ProviderPCMBuffer, activate: @escaping @MainActor () -> Bool,
               mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws
    func stop()
}

/// Deliberately unconnected to settings, the composer, and real transport.
/// A host must supply one shared voice coordinator and cancel on scene/settings
/// changes. `mayFinish` checks the live authorization through the finishing
/// phase, independently of the state machine's listening-only mayContinue.
@MainActor
final class ProviderPCMVoiceDriver: VoiceInputDriver {
    typealias Transcribe = @MainActor (_ id: UUID, _ samples: [Int16]) async throws -> String
    private enum Phase { case permission, recording, finishing }
    private let source: any ProviderPCMSource
    private let lease: VoiceAudioLeaseSlot
    private let mayFinish: () -> Bool
    private let transcribe: Transcribe
    private let onEnd: (UUID) -> Void
    private var id: UUID?
    private var phase: Phase?
    private var emit: ((UUID, VoiceInputEvent) -> Void)?
    private var mayContinue: (() -> Bool)?
    private var buffer: ProviderPCMBuffer?
    private var sourceStarted = false
    private var deadline: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var cleaning = false
    private var generation: UInt64 = 0

    init(source: any ProviderPCMSource, coordinator: any VoiceAudioCoordinating,
         mayFinish: @escaping () -> Bool, onEnd: @escaping (UUID) -> Void,
         transcribe: @escaping Transcribe) {
        self.source = source; self.lease = VoiceAudioLeaseSlot(coordinator: coordinator)
        self.mayFinish = mayFinish; self.onEnd = onEnd; self.transcribe = transcribe
    }

    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        guard !cleaning else {
            onEnd(id)
            emit(id, .failed(.unavailable))
            return
        }
        generation &+= 1
        let currentGeneration = generation
        if self.id != nil { cleanup() }
        guard generation == currentGeneration else { return }
        self.id = id; phase = .permission; self.emit = emit; self.mayContinue = mayContinue
        guard permitted(id) else { return }
        guard lease.acquire(onRevoked: { [weak self] in self?.fail(.audio, id: id) }) else {
            fail(.unavailable, id: id); return
        }
        guard permitted(id) else { return }
        setDeadline(id: id, seconds: 60)
        source.requestPermission { [weak self] granted in self?.permission(granted, id: id) }
    }

    private func permitted(_ id: UUID) -> Bool {
        guard self.id == id, phase == .permission || phase == .recording else { return false }
        guard mayContinue?() == true, mayFinish() else { deliver(.cancelled, id: id); return false }
        return self.id == id && (phase == .permission || phase == .recording)
    }

    private func permission(_ granted: Bool, id: UUID) {
        guard permitted(id), phase == .permission else { return }
        guard granted else { fail(.microphoneDenied, id: id); return }
        let collector = ProviderPCMBuffer()
        buffer = collector
        // Set before starting so reentrant failure stops the source as well.
        sourceStarted = true
        phase = .recording
        do {
            try source.start(buffer: collector, activate: { [weak self] in
                guard let self, self.permitted(id) else { return false }
                guard self.lease.activateForRecording() else { self.fail(.audio, id: id); return false }
                return self.permitted(id)
            }, mayStart: { [weak self] in self?.permitted(id) == true },
                             onFailure: { [weak self] in self?.sourceFailed(id: id) })
            guard permitted(id) else { return }
        } catch { fail(.audio, id: id) }
    }

    func finish(id: UUID) {
        guard self.id == id, phase == .permission || phase == .recording else { return }
        if phase == .permission { deliver(.final(""), id: id); return }
        phase = .finishing
        let captured = buffer?.finish()
        buffer = nil
        stopSource()
        guard self.id == id, phase == .finishing else { return }
        lease.release()
        guard self.id == id, phase == .finishing else { return }
        guard let captured else { fail(.audio, id: id); return }
        guard authorizedToFinish(id) else { return }
        guard captured.count >= 8_000 else { deliver(.final(""), id: id); return }
        setDeadline(id: id, seconds: 30)
        let run = transcribe
        work = Task { [weak self] in
            do {
                try Task.checkCancellation()
                guard let self, self.authorizedToFinish(id) else { return }
                let text = try await run(id, captured)
                try Task.checkCancellation()
                guard self.authorizedToFinish(id) else { return }
                self.deliver(.final(text), id: id)
            } catch is CancellationError {
                self?.deliver(.cancelled, id: id)
            }
            catch {
                guard let self, self.authorizedToFinish(id) else { return }
                self.fail(.recognition, id: id)
            }
        }
    }

    private func authorizedToFinish(_ id: UUID) -> Bool {
        guard self.id == id, phase == .finishing else { return false }
        guard mayFinish() else { deliver(.cancelled, id: id); return false }
        return self.id == id && phase == .finishing
    }
    func cancel(id: UUID) {
        guard self.id == id else { return }
        generation &+= 1
        cleanup()
    }
    func timeout(id: UUID) { fail(.timeout, id: id) }
    private func sourceFailed(id: UUID) {
        guard self.id == id, phase == .recording else { return }
        fail(.audio, id: id)
    }
    private func setDeadline(id: UUID, seconds: UInt64) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            self?.timeout(id: id)
        }
    }
    private func stopSource() {
        guard sourceStarted else { return }
        sourceStarted = false
        source.stop()
    }
    private func fail(_ failure: VoiceInputFailure, id: UUID) { deliver(.failed(failure), id: id) }
    private func deliver(_ event: VoiceInputEvent, id: UUID) {
        guard self.id == id else { return }
        let callback = emit
        cleanup()
        callback?(id, event)
    }
    private func cleanup() {
        // Invalidate before stop/release: both may synchronously reenter.
        guard !cleaning else { return }
        cleaning = true
        defer { cleaning = false }
        let endingID = id
        id = nil; phase = nil; emit = nil; mayContinue = nil
        deadline?.cancel(); deadline = nil
        work?.cancel(); work = nil
        buffer?.discard(); buffer = nil
        stopSource()
        lease.release()
        if let endingID { onEnd(endingID) }
    }
}
