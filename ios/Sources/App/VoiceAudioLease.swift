import Foundation

/// A coordinator must be the authority for *all* app audio users, including
/// WebKit. It may grant a lease only when recording can coexist safely. It owns
/// all session changes, knows its active clients, and must never restore a
/// stale snapshot over newer work. `release` is idempotent at its boundary.
/// A failed activation must leave shared audio safe; if that cannot be assured,
/// acquisition must be denied. The coordinator revokes before another client
/// can change any audio state required by this lease.
@MainActor
protocol VoiceAudioLease: AnyObject {
    func activateForRecording() -> Bool
    func release()
}

@MainActor
protocol VoiceAudioCoordinating: AnyObject {
    /// May call onRevoked synchronously. A nil result grants no audio access.
    func acquire(onRevoked: @escaping () -> Void) -> (any VoiceAudioLease)?
}

/// Production default: no shared audio coordinator has been validated yet.
@MainActor
final class UnavailableVoiceAudioCoordinator: VoiceAudioCoordinating {
    func acquire(onRevoked: @escaping () -> Void) -> (any VoiceAudioLease)? { nil }
}

/// Serializes ownership and ignores callbacks from released/replaced leases.
/// All methods and revocation callbacks execute on MainActor.
@MainActor
final class VoiceAudioLeaseSlot {
    private let coordinator: any VoiceAudioCoordinating
    private var lease: (any VoiceAudioLease)?
    private var generation: UInt64 = 0

    init(coordinator: any VoiceAudioCoordinating) { self.coordinator = coordinator }

    func acquire(onRevoked: @escaping () -> Void) -> Bool {
        let previousGeneration = generation
        release()
        // Releasing an old lease may synchronously install a newer one.
        guard generation == previousGeneration &+ 1 else { return false }
        let current = generation
        let acquired = coordinator.acquire { [weak self] in
            guard let self, self.generation == current else { return }
            self.release()
            onRevoked()
        }
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
        guard let lease else { return false }
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
