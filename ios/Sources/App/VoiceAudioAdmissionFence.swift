import Foundation

/// Source-level integration points. A route is covered only after its owner
/// registers every live object before creation and retains its ticket until
/// native evidence shows the object can no longer use audio. This enumeration
/// does not itself instrument WebKit.
enum VoiceAudioClientRoute: Hashable, CaseIterable {
    case browserSession       // manual tabs, popups and research
    case nativeAudio          // all current/future app-owned native audio clients
}

/// Concrete, opt-in fence for an isolated and fully controlled environment.
/// It is deliberately not installed in production: the current browser paths
/// do not yet register their WebViews or prevent creation under a lease.
@MainActor
final class VoiceAudioAdmissionFence: SharedVoiceAudioFenceProvider {
    private final class Reservation: SharedVoiceAudioFence {
        weak var owner: VoiceAudioAdmissionFence?
        let onConflict: VoiceAudioRevocation
        var conflictSent = false
        var systemStateUncertain = false
        // This is the new baseline established by a successful deactivation,
        // not a claim about the audio session's state before acquisition.
        var priorActivity: VoiceAudioPriorActivity { .inactive }
        init(owner: VoiceAudioAdmissionFence, onConflict: @escaping VoiceAudioRevocation) {
            self.owner = owner; self.onConflict = onConflict
        }
        func handoff(_ result: VoiceAudioHandoff) -> Bool {
            owner?.handoff(self, result: result) ?? false
        }
    }

    @MainActor final class ClientTicket {
        private weak var owner: VoiceAudioAdmissionFence?
        private let id: UUID
        fileprivate init(owner: VoiceAudioAdmissionFence, id: UUID) { self.owner = owner; self.id = id }
        /// Call only after native teardown has proved the client can no longer
        /// access audio. Deinit intentionally does not auto-release the ticket.
        func releaseAfterTeardown() { owner?.releaseClient(id) }
    }

    private let session: any VoiceAudioSessionAccess
    private var integratedRoutes = Set<VoiceAudioClientRoute>()
    private var sealed = false
    private var clients: [UUID: VoiceAudioClientRoute] = [:]
    private var reservation: Reservation?
    private var preparing = false
    private(set) var isQuarantined = false
    private(set) var lastHandoff: VoiceAudioHandoff?
    private(set) var baselineResetCount = 0

    init(session: any VoiceAudioSessionAccess) { self.session = session }

    /// A future host may attest a route only after instrumenting *every* path
    /// and providing native evidence. No route is marked by default.
    func attestIntegratedRoute(_ route: VoiceAudioClientRoute) {
        guard !sealed, reservation == nil, !isQuarantined else { return }
        integratedRoutes.insert(route)
    }

    @discardableResult
    func sealCoverage() -> Bool {
        guard !sealed, reservation == nil, !isQuarantined,
              integratedRoutes == Set(VoiceAudioClientRoute.allCases) else { return false }
        sealed = true
        return true
    }

    /// Register BEFORE creating or starting an audio-capable object. During a
    /// voice lease, request revocation and admit only after synchronous handoff.
    func admit(_ route: VoiceAudioClientRoute) -> ClientTicket? {
        guard !isQuarantined else { return nil }
        if let current = reservation {
            conflict(current)
            guard reservation == nil, !isQuarantined else { return nil }
        }
        let id = UUID()
        clients[id] = route
        return ClientTicket(owner: self, id: id)
    }

    func acquire(onConflict: @escaping VoiceAudioRevocation) -> (any SharedVoiceAudioFence)? {
        guard sealed, !isQuarantined, clients.isEmpty, reservation == nil else { return nil }
        let current = Reservation(owner: self, onConflict: onConflict)
        reservation = current
        lastHandoff = nil
        preparing = true
        // With all clients fenced, explicitly establish a new inactive baseline.
        // The original active state is unknowable and is not restored or claimed.
        let reset = session.deactivate()
        preparing = false
        guard reset else {
            current.systemStateUncertain = true
            isQuarantined = true
            lastHandoff = .uncertain
            return nil // retain reservation; no client may enter
        }
        baselineResetCount += 1
        // No caller may receive a fence already revoked during reset.
        if current.conflictSent {
            _ = handoff(current, result: .unchanged)
            return nil
        }
        return current
    }

    /// Future OS-interruption integration must call this before admitting
    /// competing work. An uncertain system transition requires reconciliation.
    func systemStateBecameUncertain() {
        guard let current = reservation else {
            isQuarantined = true; lastHandoff = .uncertain; return
        }
        current.systemStateUncertain = true
        conflict(current)
    }

    private func conflict(_ current: Reservation) {
        guard reservation === current, !current.conflictSent else { return }
        current.conflictSent = true
        current.onConflict()
    }

    private func handoff(_ current: Reservation, result: VoiceAudioHandoff) -> Bool {
        guard reservation === current, !preparing else { return false }
        guard result != .uncertain, !current.systemStateUncertain, !isQuarantined else {
            lastHandoff = .uncertain
            isQuarantined = true
            return false
        }
        // Coordinator "unchanged" only means it did not activate recording;
        // the fence already reset an unknown prior active state.
        lastHandoff = result == .unchanged ? .baselineReset : result
        reservation = nil
        return true
    }

    private func releaseClient(_ id: UUID) { clients.removeValue(forKey: id) }
}
