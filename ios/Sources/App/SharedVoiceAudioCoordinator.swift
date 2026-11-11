import Foundation

/// These are claims by the exclusive owner, not AVAudioSession observations.
enum VoiceAudioPriorActivity { case inactive, active, unknown }
enum VoiceAudioHandoff { case unchanged, baselineReset, restorationAttempted, uncertain }

struct VoiceAudioSettings: Equatable {
    let category: String
    let mode: String
    let options: UInt
}

/// The fence provider must prevent ALL app audio clients (including retained
/// WebViews) from entering or changing the session, and report interference
/// before it can occur. It must know the prior activity through its own
/// continuous ownership; inferring it from category or WebKit is insufficient.
@MainActor
protocol SharedVoiceAudioFence: AnyObject {
    var priorActivity: VoiceAudioPriorActivity { get }
    /// The provider must retain the fence when the result is uncertain or it
    /// returns false, until independently reconciled. Returning true accepts
    /// the handoff; restorationAttempted is not proof of OS active state.
    func handoff(_ result: VoiceAudioHandoff) -> Bool
}

@MainActor
protocol SharedVoiceAudioFenceProvider: AnyObject {
    func acquire(onConflict: @escaping VoiceAudioRevocation) -> (any SharedVoiceAudioFence)?
}

/// A narrow injectable boundary. A failed mutation may still have side effects.
@MainActor
protocol VoiceAudioSessionAccess: AnyObject {
    func settings() -> VoiceAudioSettings?
    func configureRecording() -> Bool
    func activate() -> Bool
    func deactivate() -> Bool
    func restore(_ settings: VoiceAudioSettings) -> Bool
}

/// Isolated candidate. No production fence provider currently exists; it must
/// not be connected until all WebKit/native clients and interruptions are owned.
@MainActor
final class SharedVoiceAudioCoordinator: VoiceAudioCoordinating {
    private enum Phase { case acquiring, reserved, activating, active, closing }
    private final class Reservation {
        var phase: Phase = .acquiring
        var fence: (any SharedVoiceAudioFence)?
        var revoked = false
        var releaseRequested = false
        var settings: VoiceAudioSettings?
        var categoryAttempted = false
        var activationAttempted = false
        let onRevoked: VoiceAudioRevocation
        init(onRevoked: @escaping VoiceAudioRevocation) { self.onRevoked = onRevoked }
    }
    private final class Lease: VoiceAudioLease {
        private let owner: SharedVoiceAudioCoordinator
        private let reservation: Reservation
        init(owner: SharedVoiceAudioCoordinator, reservation: Reservation) {
            self.owner = owner; self.reservation = reservation
        }
        func activateForRecording() -> Bool { owner.activate(reservation) }
        func release() { owner.release(reservation) }
    }

    private let provider: any SharedVoiceAudioFenceProvider
    private let session: any VoiceAudioSessionAccess
    private var current: Reservation?
    private var quarantinedFence: (any SharedVoiceAudioFence)?
    private(set) var isQuarantined = false

    init(provider: any SharedVoiceAudioFenceProvider, session: any VoiceAudioSessionAccess) {
        self.provider = provider; self.session = session
    }

    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)? {
        guard current == nil, !isQuarantined else { return nil }
        let reservation = Reservation(onRevoked: onRevoked)
        current = reservation
        let fence = provider.acquire { [weak self, weak reservation] in
            guard let self, let reservation else { return }
            self.revoke(reservation)
        }
        guard let fence else { current = nil; return nil }
        reservation.fence = fence
        let priorActivity = fence.priorActivity
        guard !reservation.revoked, !reservation.releaseRequested,
              priorActivity == .inactive else {
            close(reservation)
            return nil
        }
        reservation.phase = .reserved
        return Lease(owner: self, reservation: reservation)
    }

    private func activate(_ reservation: Reservation) -> Bool {
        guard current === reservation, reservation.phase == .reserved,
              !reservation.revoked else { return false }
        reservation.phase = .activating
        let prior = session.settings()
        reservation.settings = prior
        var ok = prior != nil && !reservation.releaseRequested && !reservation.revoked
        if ok {
            reservation.categoryAttempted = true
            ok = session.configureRecording()
        }
        if ok && !reservation.releaseRequested && !reservation.revoked {
            reservation.activationAttempted = true
            ok = session.activate()
        } else { ok = false }
        guard ok, !reservation.releaseRequested, !reservation.revoked else {
            close(reservation)
            return false
        }
        reservation.phase = .active
        return true
    }

    private func revoke(_ reservation: Reservation) {
        guard current === reservation, !reservation.revoked, reservation.phase != .closing else { return }
        reservation.revoked = true
        if reservation.phase == .acquiring || reservation.phase == .activating {
            reservation.releaseRequested = true
        }
        // For an active engine, the driver must stop it and call release here.
        // If it doesn't, leave the fence held; never silently transfer it.
        reservation.onRevoked()
    }

    private func release(_ reservation: Reservation) {
        guard current === reservation else { return }
        switch reservation.phase {
        case .acquiring, .activating: reservation.releaseRequested = true
        case .reserved, .active: close(reservation)
        case .closing: break
        }
    }

    private func close(_ reservation: Reservation) {
        guard current === reservation, reservation.phase != .closing, let fence = reservation.fence else { return }
        reservation.phase = .closing
        var outcome: VoiceAudioHandoff = .unchanged
        if reservation.categoryAttempted {
            if reservation.activationAttempted && !session.deactivate() {
                outcome = .uncertain
            } else if let prior = reservation.settings, session.restore(prior) {
                outcome = .restorationAttempted
            } else {
                outcome = .uncertain
            }
        }
        let accepted = fence.handoff(outcome)
        if !accepted || outcome == .uncertain {
            isQuarantined = true
            quarantinedFence = fence
        }
        current = nil
    }
}
