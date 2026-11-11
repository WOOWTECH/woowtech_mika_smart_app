import Foundation

typealias VoiceAudioRevocation = @MainActor () -> Void

/// A coordinator must be the authority for *all* app audio users, including
/// WebKit. It may grant a lease only when recording can coexist safely. It owns
/// all session changes, knows its active clients, and must never restore a
/// stale snapshot over newer work. `release` is idempotent at its boundary.
/// A failed activation must either leave shared audio safe or retain the fence
/// in quarantine; acquisition must be denied when exclusive control or the
/// prior state cannot be established. Revoke before another client can change
/// any audio state required by this lease.
@MainActor
protocol VoiceAudioLease: AnyObject {
    func activateForRecording() -> Bool
    func release()
}

@MainActor
protocol VoiceAudioCoordinating: AnyObject {
    /// May call onRevoked synchronously. The consumer must synchronously stop
    /// capture before returning from onRevoked. A nil result grants no access.
    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)?
}

/// Production default: no shared audio coordinator has been validated yet.
@MainActor
final class UnavailableVoiceAudioCoordinator: VoiceAudioCoordinating {
    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)? { nil }
}

/// Serializes ownership and ignores callbacks from released/replaced leases.
/// All methods and revocation callbacks execute on MainActor.
@MainActor
final class VoiceAudioLeaseSlot {
    private let coordinator: any VoiceAudioCoordinating
    private var lease: (any VoiceAudioLease)?
    private var generation: UInt64 = 0
    private var revokedGeneration: UInt64?
    private var acquiringGeneration: UInt64?

    init(coordinator: any VoiceAudioCoordinating) { self.coordinator = coordinator }

    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> Bool {
        // Replacing a live lease could hand off an engine still recording.
        // The owner must stop capture and explicitly release first.
        guard lease == nil, acquiringGeneration == nil else { return false }
        generation &+= 1
        let current = generation
        acquiringGeneration = current
        let acquired = coordinator.acquire { [weak self] in
            guard let self, self.generation == current,
                  self.revokedGeneration != current else { return }
            self.revokedGeneration = current
            // The consumer stops capture and explicitly calls release. If it
            // fails to do so, keep the fence held and refuse another lease.
            onRevoked()
            // During synchronous acquisition no lease has been installed yet;
            // invalidate the pending return without handing off a live engine.
            if self.generation == current, self.lease == nil { self.generation &+= 1 }
        }
        if acquiringGeneration == current { acquiringGeneration = nil }
        guard let acquired else {
            // No lease exists, so any later revocation from this attempt is stale.
            if generation == current { generation &+= 1 }
            return false
        }
        // The coordinator may revoke before returning the lease.
        guard generation == current else { acquired.release(); return false }
        lease = acquired
        return true
    }

    func activateForRecording() -> Bool {
        guard let lease, revokedGeneration != generation else { return false }
        let current = generation
        let activated = lease.activateForRecording()
        guard generation == current else { return false }
        if !activated { release() }
        return activated
    }

    func release() {
        generation &+= 1
        let previous = lease
        lease = nil
        previous?.release()
    }
}
