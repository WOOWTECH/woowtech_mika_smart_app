import Foundation

/// Apple session operations are injectable so the lifecycle is testable without
/// claiming an iOS SDK or live WebKit run. Implementations execute on MainActor.
@MainActor
protocol MixedVoiceAudioSession: AnyObject {
    func settings() -> VoiceAudioSettings?
    func configureMixedRecording() -> Bool
    func isMixedRecording(_ settings: VoiceAudioSettings) -> Bool
    func activate() -> Bool
    func restore(_ settings: VoiceAudioSettings) -> Bool
}

enum MixedVoiceAudioCleanup: Equatable {
    case noChange
    case restoredSettingsActiveStateUnknown
    case settingsChangedElsewhere
    case settingsUnavailable
    case configurationFailedStateUnknown
    case installationNotOwned
    case restoreFailed
}

/// User-initiated capture without requiring every WebView to be destroyed.
/// It serializes this app's voice sessions, not all OS or WebKit audio.
/// The previous active state is not observable: cleanup never deactivates the
/// shared session. This can leave it active; the host must disclose and test
/// this tradeoff rather than claim complete restoration.
@MainActor
final class MixedVoiceAudioCoordinator: VoiceAudioCoordinating {
    private enum Phase { case reserved, configuring, active, closing }
    private final class Reservation {
        var phase: Phase = .reserved
        var releaseRequested = false
        var revoked = false
        var prior: VoiceAudioSettings?
        var installed: VoiceAudioSettings?
        var configurationAttempted = false
        var configurationSucceeded = false
        let onRevoked: VoiceAudioRevocation
        init(onRevoked: @escaping VoiceAudioRevocation) { self.onRevoked = onRevoked }
    }
    private final class Lease: VoiceAudioLease {
        let owner: MixedVoiceAudioCoordinator
        let reservation: Reservation
        init(owner: MixedVoiceAudioCoordinator, reservation: Reservation) {
            self.owner = owner; self.reservation = reservation
        }
        func activateForRecording() -> Bool { owner.activate(reservation) }
        func release() { owner.release(reservation) }
    }

    private let session: any MixedVoiceAudioSession
    private var current: Reservation?
    private(set) var lastCleanup: MixedVoiceAudioCleanup?

    init(session: any MixedVoiceAudioSession) { self.session = session }

    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)? {
        guard current == nil else { return nil }
        let reservation = Reservation(onRevoked: onRevoked)
        current = reservation
        lastCleanup = nil
        return Lease(owner: self, reservation: reservation)
    }

    private func activate(_ reservation: Reservation) -> Bool {
        guard current === reservation, reservation.phase == .reserved, !reservation.revoked else { return false }
        reservation.phase = .configuring
        reservation.prior = session.settings()
        guard reservation.prior != nil, !reservation.releaseRequested, !reservation.revoked else {
            close(reservation); return false
        }
        reservation.configurationAttempted = true
        let configured = session.configureMixedRecording()
        reservation.configurationSucceeded = configured
        // Only claim our intended category/mode/options. A WebKit change during
        // setup must not become a snapshot we later mistake for our own.
        if configured, let actual = session.settings(), session.isMixedRecording(actual) {
            reservation.installed = actual
        }
        guard configured, reservation.installed != nil, !reservation.releaseRequested, !reservation.revoked else {
            close(reservation); return false
        }
        let active = session.activate()
        guard active, !reservation.releaseRequested, !reservation.revoked else { close(reservation); return false }
        reservation.phase = .active
        return true
    }

    /// The caller must synchronously stop its engine before releasing. If it
    /// doesn't, retain this reservation and reject another voice session.
    func revokeForSystemChange() {
        guard let reservation = current, !reservation.revoked, reservation.phase != .closing else { return }
        reservation.revoked = true
        if reservation.phase == .configuring { reservation.releaseRequested = true }
        reservation.onRevoked()
    }

    private func release(_ reservation: Reservation) {
        guard current === reservation else { return }
        switch reservation.phase {
        case .configuring: reservation.releaseRequested = true
        case .reserved, .active: close(reservation)
        case .closing: break
        }
    }

    private func close(_ reservation: Reservation) {
        guard current === reservation, reservation.phase != .closing else { return }
        reservation.phase = .closing
        let outcome: MixedVoiceAudioCleanup
        if !reservation.configurationAttempted {
            outcome = .noChange
        } else if let prior = reservation.prior, let installed = reservation.installed {
            if let actual = session.settings() {
                if actual != installed { outcome = .settingsChangedElsewhere }
                else if prior == installed { outcome = .restoredSettingsActiveStateUnknown }
                else if session.restore(prior) { outcome = .restoredSettingsActiveStateUnknown }
                else { outcome = .restoreFailed }
            } else { outcome = .settingsUnavailable }
        } else if reservation.configurationSucceeded {
            outcome = .installationNotOwned
        } else {
            // A throwing category change may have changed state; overwriting
            // it using an unverified snapshot could clobber another user.
            outcome = .configurationFailedStateUnknown
        }
        lastCleanup = outcome
        current = nil
    }
}
