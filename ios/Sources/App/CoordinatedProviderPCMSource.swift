import Foundation

/// Platform calls are main-actor isolated. The engine must stop its tap and
/// engine synchronously, and may report an error synchronously during setup.
@MainActor
protocol ProviderPCMEngine: AnyObject {
    func install(buffer: ProviderPCMBuffer, onFailure: @escaping @MainActor () -> Void) throws
    func prepare()
    func start() throws
    func stop()
}

@MainActor
protocol ProviderPCMObservation: AnyObject { func cancel() }

@MainActor
protocol ProviderPCMPlatform: AnyObject {
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void)
    func makeEngine() throws -> any ProviderPCMEngine
    func observeSystemChanges(buffer: ProviderPCMBuffer,
                              onFailure: @escaping @MainActor () -> Void) -> any ProviderPCMObservation
}

/// Owns only a single capture engine and its observers. The driver owns the
/// audio lease and permission/session policy. No engine is made on init or
/// merely requesting permission. All platform calls can synchronously reenter.
@MainActor
final class CoordinatedProviderPCMSource: ProviderPCMSource {
    private let platform: any ProviderPCMPlatform
    private var engine: (any ProviderPCMEngine)?
    private var observation: (any ProviderPCMObservation)?
    private var activeBuffer: ProviderPCMBuffer?
    private var generation: UInt64 = 0
    private var stopping = false

    init(platform: any ProviderPCMPlatform) { self.platform = platform }

    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        platform.requestPermission(completion)
    }

    func start(buffer: ProviderPCMBuffer, activate: @escaping @MainActor () -> Bool,
               mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        guard engine == nil, !stopping else { throw SourceError.alreadyActive }
        generation &+= 1
        let current = generation
        let newEngine = try platform.makeEngine()
        guard generation == current, !stopping, engine == nil else {
            newEngine.stop(); return
        }
        engine = newEngine
        activeBuffer = buffer
        let failure: @MainActor () -> Void = { [weak self] in
            guard let self, self.isCurrent(current) else { return }
            onFailure()
            // An owner normally stops during onFailure. Defend against an
            // owner that does not, without affecting a replacement session.
            if self.isCurrent(current) { self.stop() }
        }
        do {
            // Arm before activating the lease or doing format/filter setup.
            // A notification closes the buffer synchronously, even when its
            // main-actor failure callback cannot run until activation returns.
            let token = platform.observeSystemChanges(buffer: buffer, onFailure: failure)
            guard isCurrent(current) else { token.cancel(); return }
            observation = token
            guard permitted(current, buffer: buffer, mayStart, failure: failure) else { return }
            let activated = activate()
            guard isCurrent(current) else { return }
            guard activated else { failure(); return }
            guard permitted(current, buffer: buffer, mayStart, failure: failure) else { return }
            try newEngine.install(buffer: buffer, onFailure: failure)
            guard permitted(current, buffer: buffer, mayStart, failure: failure) else { return }
            newEngine.prepare()
            guard permitted(current, buffer: buffer, mayStart, failure: failure) else { return }
            try newEngine.start()
            // Catch an interruption racing with start() without retaining the
            // engine or allowing the closed collector to be released.
            guard permitted(current, buffer: buffer, mayStart, failure: failure) else { return }
        } catch {
            if isCurrent(current) { stop() }
            throw error
        }
    }

    private func isCurrent(_ current: UInt64) -> Bool {
        generation == current && engine != nil && !stopping
    }
    private func permitted(_ current: UInt64, buffer: ProviderPCMBuffer, _ mayStart: () -> Bool,
                           failure: () -> Void) -> Bool {
        guard isCurrent(current) else { return false }
        guard buffer.isOpen else { failure(); return false }
        let allowed = mayStart()
        guard isCurrent(current) else { return false }
        if !allowed { stop(); return false }
        guard buffer.isOpen else { failure(); return false }
        return true
    }

    func stop() {
        guard !stopping else { return }
        stopping = true
        generation &+= 1
        let oldObservation = observation, oldEngine = engine
        let oldBuffer = activeBuffer
        observation = nil; engine = nil; activeBuffer = nil
        oldBuffer?.discard()
        oldObservation?.cancel()
        oldEngine?.stop()
        stopping = false
    }

    private enum SourceError: Error { case alreadyActive }
}
