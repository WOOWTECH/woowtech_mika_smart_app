import Foundation

@MainActor
final class FakeFence: SharedVoiceAudioFence {
    var priorActivity: VoiceAudioPriorActivity = .inactive
    var outcomes: [VoiceAudioHandoff] = []
    var accept = true
    var onHandoff: (() -> Void)?
    func handoff(_ result: VoiceAudioHandoff) -> Bool {
        outcomes.append(result); onHandoff?(); return accept
    }
}

@MainActor
final class FakeFenceProvider: SharedVoiceAudioFenceProvider {
    var next: FakeFence?
    var callbacks: [VoiceAudioRevocation] = []
    var onAcquire: (() -> Void)?
    func acquire(onConflict: @escaping VoiceAudioRevocation) -> (any SharedVoiceAudioFence)? {
        callbacks.append(onConflict); onAcquire?(); return next
    }
}

@MainActor
final class FakeSession: VoiceAudioSessionAccess {
    var log: [String] = []
    var configuration = VoiceAudioSettings(category: "playback", mode: "default", options: 3)
    var readOK = true
    var configOK = true
    var activateOK = true
    var deactivateOK = true
    var restoreOK = true
    var inActivate = false
    var recording = false
    var onSettings: (() -> Void)?
    var onConfigure: (() -> Void)?
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?
    func settings() -> VoiceAudioSettings? { log.append("settings"); onSettings?(); return readOK ? configuration : nil }
    func configureRecording() -> Bool { log.append("configure"); onConfigure?(); return configOK }
    func activate() -> Bool {
        log.append("activate.begin"); inActivate = true; onActivate?(); inActivate = false
        log.append("activate.end"); return activateOK
    }
    func deactivate() -> Bool {
        precondition(!recording && !inActivate, "deactivate before engine stopped or during activation")
        log.append("deactivate"); onDeactivate?(); return deactivateOK
    }
    func restore(_ settings: VoiceAudioSettings) -> Bool {
        precondition(!recording && !inActivate, "restore before engine stopped or during activation")
        log.append("restore"); precondition(settings == configuration); return restoreOK
    }
}

@main
struct VoiceAudioCoordinatorChecks {
    @MainActor static func main() {
        var assertions = 0
        func check(_ expression: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard expression() else { fatalError("FAIL: \(message)") }
        }
        func context(_ prior: VoiceAudioPriorActivity = .inactive) -> (SharedVoiceAudioCoordinator, FakeFenceProvider, FakeFence, FakeSession) {
            let provider = FakeFenceProvider(), fence = FakeFence(), session = FakeSession()
            fence.priorActivity = prior; provider.next = fence
            return (SharedVoiceAudioCoordinator(provider: provider, session: session), provider, fence, session)
        }
        do {
            let (owner, provider, _, session) = context()
            provider.next = nil
            check(owner.acquire(onRevoked: {}) == nil && session.log.isEmpty, "missing fence cannot touch audio")
        }
        for prior in [VoiceAudioPriorActivity.active, .unknown] {
            let (owner, _, fence, session) = context(prior)
            check(owner.acquire(onRevoked: {}) == nil, "unknown and active baselines deny")
            check(session.log.isEmpty && fence.outcomes == [.unchanged], "denial does not mutate system state")
        }
        do {
            let (owner, provider, fence, session) = context()
            var slot: VoiceAudioLeaseSlot!
            slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { session.recording = false; slot.release() }), "exclusive fence acquired")
            check(owner.acquire(onRevoked: {}) == nil, "second audio client excluded")
            check(slot.activateForRecording(), "known inactive session activated")
            session.recording = true
            var observedDuringHandoff = false
            fence.onHandoff = { observedDuringHandoff = owner.acquire(onRevoked: {}) == nil }
            provider.callbacks[0]()
            provider.callbacks[0]()
            check(!session.recording && fence.outcomes == [.restorationAttempted], "revoke stops engine and hands off once")
            check(session.log == ["settings", "configure", "activate.begin", "activate.end", "deactivate", "restore"],
                  "stop precedes deactivate and configuration restoration attempt")
            check(observedDuringHandoff && !owner.isQuarantined, "handoff cannot overlap a new acquisition")
            slot.release()
            check(fence.outcomes.count == 1, "duplicate release is harmless")
            let nextFence = FakeFence(); provider.next = nextFence
            check(slot.acquire(onRevoked: { slot.release() }), "new session after accepted handoff")
            provider.callbacks[0]()
            check(nextFence.outcomes.isEmpty, "stale revocation cannot touch the new owner")
            slot.release()
            check(nextFence.outcomes == [.unchanged], "unactivated lease makes no session changes")
        }
        do {
            let (owner, provider, firstFence, _) = context()
            let old = owner.acquire(onRevoked: {})!
            old.release()
            let nextFence = FakeFence(); provider.next = nextFence
            let next = owner.acquire(onRevoked: {})!
            old.release()
            check(firstFence.outcomes == [.unchanged] && nextFence.outcomes.isEmpty,
                  "old lease release cannot hand off the current fence")
            next.release()
            check(nextFence.outcomes == [.unchanged], "current lease can still release")
        }
        do {
            let (owner, provider, fence, session) = context()
            provider.onAcquire = { provider.callbacks.last?() }
            var revoked = 0
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(!slot.acquire(onRevoked: { revoked += 1 }), "synchronous conflict during acquisition denies")
            check(revoked == 1 && session.log.isEmpty && fence.outcomes == [.unchanged], "no changes after acquisition conflict")
        }
        do {
            let (owner, provider, fence, session) = context()
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { slot.release() }), "snapshot conflict setup")
            session.onSettings = { provider.callbacks.last?() }
            check(!slot.activateForRecording(), "snapshot conflict cancels activation")
            check(session.log == ["settings"] && fence.outcomes == [.unchanged], "snapshot conflict has no mutations")
        }
        do {
            let (owner, provider, fence, session) = context()
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { slot.release() }), "configure conflict setup")
            session.onConfigure = { provider.callbacks.last?(); provider.callbacks.last?() }
            check(!slot.activateForRecording(), "configure conflict cancels activation")
            check(session.log == ["settings", "configure", "restore"] && fence.outcomes == [.restorationAttempted],
                  "configure conflict rolls back without activating")
        }
        do {
            let (owner, provider, fence, session) = context()
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { slot.release() }), "activation conflict setup")
            session.onActivate = { provider.callbacks.last?() }
            check(!slot.activateForRecording(), "conflict during activation cancels")
            check(session.log == ["settings", "configure", "activate.begin", "activate.end", "deactivate", "restore"],
                  "deactivation waits until activation returns")
            check(fence.outcomes == [.restorationAttempted], "activation conflict completes one handoff")
        }
        do {
            let (owner, _, fence, session) = context()
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { slot.release() }), "cancellation during activation setup")
            session.onActivate = { slot.release() }
            check(!slot.activateForRecording(), "cancel during activation cannot succeed")
            check(session.log.suffix(2).elementsEqual(["deactivate", "restore"]) && fence.outcomes.count == 1,
                  "cancel defers rollback and hands off once")
        }
        do {
            let (owner, provider, fence, session) = context()
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            var notices = 0
            check(slot.acquire(onRevoked: { notices += 1 }), "unacknowledged conflict setup")
            check(slot.activateForRecording(), "unacknowledged conflict starts")
            session.recording = true
            provider.callbacks.last?(); provider.callbacks.last?()
            check(notices == 1 && fence.outcomes.isEmpty && owner.acquire(onRevoked: {}) == nil,
                  "unacknowledged revoke retains fence")
            session.recording = false; slot.release()
            check(fence.outcomes == [.restorationAttempted], "handoff only after explicit stop and release")
        }
        do {
            let (owner, _, fence, session) = context()
            session.readOK = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "snapshot failure denies activation")
            check(session.log == ["settings"] && fence.outcomes == [.unchanged], "snapshot failure makes no changes")
        }
        do {
            let (owner, _, fence, session) = context()
            session.configOK = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "configuration failure denies activation")
            check(session.log == ["settings", "configure", "restore"] && fence.outcomes == [.restorationAttempted],
                  "potential partial configure failure attempts restoration")
        }
        do {
            let (owner, _, fence, session) = context()
            session.activateOK = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "activation failure with safe rollback")
            check(session.log.suffix(2).elementsEqual(["deactivate", "restore"]) && fence.outcomes == [.restorationAttempted],
                  "activation failure attempts both cleanup steps")
        }
        do {
            let (owner, _, fence, session) = context()
            session.activateOK = false; session.deactivateOK = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "activation failure denied")
            check(session.log == ["settings", "configure", "activate.begin", "activate.end", "deactivate"],
                  "failed deactivation does not overwrite category")
            check(fence.outcomes == [.uncertain] && owner.isQuarantined && owner.acquire(onRevoked: {}) == nil,
                  "uncertain active state quarantines fence and blocks further use")
        }
        do {
            let (owner, _, fence, session) = context()
            session.restoreOK = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && slot.activateForRecording(), "restore failure setup")
            slot.release()
            check(fence.outcomes == [.uncertain] && owner.isQuarantined, "restore failure quarantines")
        }
        do {
            let (owner, _, fence, _) = context()
            fence.accept = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && slot.activateForRecording(), "restoration handoff rejection setup")
            slot.release()
            check(fence.outcomes == [.restorationAttempted] && owner.isQuarantined,
                  "attempted restoration is not automatically accepted as verified")
        }
        do {
            let (owner, _, fence, _) = context()
            fence.accept = false
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}), "handoff rejection setup")
            slot.release()
            check(fence.outcomes == [.unchanged] && owner.isQuarantined && owner.acquire(onRevoked: {}) == nil,
                  "authority refusal quarantines even an unchanged session")
        }
        // Exercise the concrete opt-in admission fence with the actual
        // coordinator and a synthetic system session.
        do {
            let session = FakeSession()
            let runtime = VoiceAudioRuntimeCandidate(session: session)
            let gate = runtime.fence
            let slot = VoiceAudioLeaseSlot(coordinator: runtime.coordinator)
            check(!gate.sealCoverage() && !slot.acquire(onRevoked: {}), "unattested coverage denies")
            check(session.log.isEmpty, "unsealed gate does not reset session")
            gate.attestIntegratedRoute(.browserSession)
            check(!gate.sealCoverage(), "missing native route cannot seal")
            gate.attestIntegratedRoute(.nativeAudio)
            check(gate.sealCoverage(), "all explicit attestations can seal isolated gate")
            for route in VoiceAudioClientRoute.allCases {
                let ticket = gate.admit(route)!
                check(!slot.acquire(onRevoked: {}) && session.log.isEmpty, "registered client blocks voice reset")
                ticket.releaseAfterTeardown(); ticket.releaseAfterTeardown()
            }
            let oldTicket = gate.admit(.browserSession)!
            oldTicket.releaseAfterTeardown()
            let liveTicket = gate.admit(.browserSession)!
            oldTicket.releaseAfterTeardown()
            check(!slot.acquire(onRevoked: {}) && session.log.isEmpty, "stale ticket cannot remove a new client")
            liveTicket.releaseAfterTeardown()
            var stopped = false
            check(slot.acquire(onRevoked: { stopped = true; session.recording = false; slot.release() }),
                  "controlled empty environment grants real fence")
            check(session.log == ["deactivate"] && gate.baselineResetCount == 1,
                  "explicit reset establishes new baseline without claiming prior state")
            check(slot.activateForRecording(), "real fence can activate through coordinator")
            session.recording = true
            let browser = gate.admit(.browserSession)
            check(stopped && browser != nil && !session.recording, "browser admitted only after voice stops")
            check(gate.lastHandoff == .restorationAttempted && !gate.isQuarantined,
                  "handoff records attempted restoration only")
            check(session.log == ["deactivate", "settings", "configure", "activate.begin", "activate.end", "deactivate", "restore"],
                  "baseline reset and guarded lifecycle are ordered")
            check(!slot.acquire(onRevoked: {}), "retained browser still blocks new voice lease")
            browser?.releaseAfterTeardown()
            check(slot.acquire(onRevoked: { slot.release() }) && gate.baselineResetCount == 2,
                  "voice can be used again after native client teardown")
            slot.release()
            check(gate.lastHandoff == .baselineReset, "unactivated lease reports the baseline reset")
        }
        do {
            let session = FakeSession()
            let gate = VoiceAudioAdmissionFence(session: session)
            for route in VoiceAudioClientRoute.allCases { gate.attestIntegratedRoute(route) }
            check(gate.sealCoverage(), "unacknowledged conflict gate setup")
            let owner = SharedVoiceAudioCoordinator(provider: gate, session: session)
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            var notices = 0
            check(slot.acquire(onRevoked: { notices += 1 }), "unacknowledged conflict voice lease")
            check(slot.activateForRecording(), "unacknowledged conflict voice activation")
            session.recording = true
            check(gate.admit(.browserSession) == nil && gate.admit(.browserSession) == nil && notices == 1,
                  "competing WebView denied until engine is stopped")
            session.recording = false; slot.release()
            let ticket = gate.admit(.browserSession)
            check(ticket != nil, "competing WebView may enter after release")
            ticket?.releaseAfterTeardown()
        }
        do {
            let session = FakeSession()
            let gate = VoiceAudioAdmissionFence(session: session)
            for route in VoiceAudioClientRoute.allCases { gate.attestIntegratedRoute(route) }
            check(gate.sealCoverage(), "baseline conflict gate setup")
            let owner = SharedVoiceAudioCoordinator(provider: gate, session: session)
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            var deniedDuringReset = false
            session.onDeactivate = {
                session.onDeactivate = nil
                deniedDuringReset = gate.admit(.browserSession) == nil
            }
            check(!slot.acquire(onRevoked: { slot.release() }) && deniedDuringReset,
                  "reentrant browser creation blocked during baseline reset")
            check(gate.lastHandoff == .baselineReset && !gate.isQuarantined && session.log == ["deactivate"],
                  "conflicted baseline is reported as reset, not unchanged")
        }
        do {
            let session = FakeSession()
            let gate = VoiceAudioAdmissionFence(session: session)
            for route in VoiceAudioClientRoute.allCases { gate.attestIntegratedRoute(route) }
            check(gate.sealCoverage(), "uncertainty during reset setup")
            let owner = SharedVoiceAudioCoordinator(provider: gate, session: session)
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            session.onDeactivate = { session.onDeactivate = nil; gate.systemStateBecameUncertain() }
            check(!slot.acquire(onRevoked: { slot.release() }) && gate.isQuarantined,
                  "system uncertainty during baseline reset quarantines")
            check(gate.admit(.browserSession) == nil, "uncertain reset retains client fence")
        }
        do {
            let session = FakeSession(); session.deactivateOK = false
            let gate = VoiceAudioAdmissionFence(session: session)
            for route in VoiceAudioClientRoute.allCases { gate.attestIntegratedRoute(route) }
            check(gate.sealCoverage(), "baseline failure setup")
            let owner = SharedVoiceAudioCoordinator(provider: gate, session: session)
            check(owner.acquire(onRevoked: {}) == nil && gate.isQuarantined,
                  "failed baseline reset quarantines without claiming active state")
            check(gate.admit(.browserSession) == nil && owner.acquire(onRevoked: {}) == nil,
                  "failed reset prevents browser and voice admission")
            check(session.log == ["deactivate"] && gate.baselineResetCount == 0 && gate.lastHandoff == .uncertain,
                  "failed reset not retried and state remains uncertain")
        }
        do {
            let session = FakeSession()
            let gate = VoiceAudioAdmissionFence(session: session)
            for route in VoiceAudioClientRoute.allCases { gate.attestIntegratedRoute(route) }
            check(gate.sealCoverage(), "interruption setup")
            let owner = SharedVoiceAudioCoordinator(provider: gate, session: session)
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { session.recording = false; slot.release() }) && slot.activateForRecording(),
                  "interruption starts controlled capture")
            session.recording = true
            gate.systemStateBecameUncertain()
            check(!session.recording && gate.isQuarantined && owner.isQuarantined,
                  "system uncertainty stops capture and quarantines handoff")
            check(gate.admit(.nativeAudio) == nil && !slot.acquire(onRevoked: {}),
                  "system uncertainty blocks all later admission")
        }
        print("PASS SharedVoiceAudioCoordinator: \(assertions) assertions; fake fence and fake session only")
    }
}
