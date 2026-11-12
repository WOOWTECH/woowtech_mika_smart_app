import Foundation

@MainActor
final class FakeMixedSession: MixedVoiceAudioSession {
    let original = VoiceAudioSettings(category: "ambient", mode: "default", options: 0)
    let mixed = VoiceAudioSettings(category: "playAndRecord", mode: "default", options: 5)
    let external = VoiceAudioSettings(category: "external", mode: "movie", options: 8)
    var current: VoiceAudioSettings
    var log: [String] = []
    var readOK = true
    var reads = 0
    var onSettings: (() -> Void)?
    var configureOK = true
    var activateOK = true
    var restoreOK = true
    var onConfigure: (() -> Void)?
    var onActivate: (() -> Void)?
    var onRestore: (() -> Void)?
    var webKitPlaying = false
    var engineRecording = false
    var inOperation = false
    init() { current = original }
    func settings() -> VoiceAudioSettings? {
        log.append("settings"); reads += 1; onSettings?(); return readOK ? current : nil
    }
    func configureMixedRecording() -> Bool {
        log.append("configure"); inOperation = true; current = mixed; onConfigure?(); inOperation = false
        return configureOK
    }
    func isMixedRecording(_ settings: VoiceAudioSettings) -> Bool { settings == mixed }
    func activate() -> Bool {
        log.append("activate"); inOperation = true; onActivate?(); inOperation = false
        return activateOK
    }
    func restore(_ settings: VoiceAudioSettings) -> Bool {
        precondition(!engineRecording && !inOperation, "restore before recording stops or during operation")
        log.append("restore"); onRestore?(); if restoreOK { current = settings }; return restoreOK
    }
}

@MainActor
final class FakeMixedDriver: VoiceInputDriver {
    private let session: FakeMixedSession
    private let slot: VoiceAudioLeaseSlot
    var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var latest: UUID?
    init(session: FakeMixedSession, coordinator: MixedVoiceAudioCoordinator) {
        self.session = session; self.slot = VoiceAudioLeaseSlot(coordinator: coordinator)
    }
    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        latest = id; callbacks[id] = emit
        guard mayContinue() else { return }
        guard slot.acquire(onRevoked: { [weak self] in
            self?.session.engineRecording = false; self?.slot.release(); emit(id, .failed(.audio))
        }), mayContinue(), slot.activateForRecording() else { emit(id, .failed(.audio)); return }
        guard mayContinue() else { slot.release(); return }
        session.engineRecording = true
    }
    func finish(id: UUID) {
        session.engineRecording = false; slot.release(); callbacks[id]?(id, .final("spoken"))
    }
    func cancel(id: UUID) { session.engineRecording = false; slot.release() }
}

@main
struct MixedVoiceAudioChecks {
    @MainActor static func main() {
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard value() else { fatalError("FAIL: \(message)") }
        }
        do {
            let session = FakeMixedSession(); session.webKitPlaying = true
            let owner = MixedVoiceAudioCoordinator(session: session)
            let slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { session.engineRecording = false; slot.release() }),
                  "voice lease available while fake WebKit is playing")
            check(session.log.isEmpty, "acquire does not prompt or change audio")
            check(owner.acquire(onRevoked: {}) == nil, "another voice session is serialized")
            check(slot.activateForRecording(), "mixed category and activation succeed")
            session.engineRecording = true
            session.engineRecording = false; slot.release(); slot.release()
            check(session.webKitPlaying && session.current == session.original,
                  "fake WebKit remains playing and prior category is attempted")
            check(owner.lastCleanup == .restoredSettingsActiveStateUnknown, "active state explicitly unknown")
            check(session.log == ["settings", "configure", "settings", "activate", "settings", "restore"],
                  "no deactivation and restore occurs after capture stops")
            check(slot.acquire(onRevoked: { slot.release() }), "new gesture can retry")
            slot.release()
            check(owner.lastCleanup == .noChange, "unused lease never modifies audio")
        }
        do {
            let controlled = FakeMixedSession(), policy = MixedVoiceAudioCoordinator(session: controlled)
            let slot = VoiceAudioLeaseSlot(coordinator: policy)
            check(slot.acquire(onRevoked: { slot.release() }) && slot.activateForRecording(), "external change setup")
            controlled.current = controlled.external
            slot.release()
            check(controlled.current == controlled.external && !controlled.log.contains("restore"),
                  "do not overwrite another client's changed settings")
            check(policy.lastCleanup == .settingsChangedElsewhere, "external change reported")
        }
        do {
            let session = FakeMixedSession()
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) , "external change during setup lease")
            session.onConfigure = { session.current = session.external }
            check(!slot.activateForRecording(), "external settings during setup reject activation")
            check(session.current == session.external && !session.log.contains("restore") && owner.lastCleanup == .installationNotOwned,
                  "external settings are never adopted and overwritten")
        }
        do {
            let session = FakeMixedSession(); session.readOK = false
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "missing snapshot refuses to modify")
            check(session.log == ["settings"] && owner.lastCleanup == .noChange, "no writes without snapshot")
        }
        do {
            let session = FakeMixedSession()
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}), "setup read failure lease")
            session.onSettings = { if session.reads == 2 { session.readOK = false } }
            check(!slot.activateForRecording(), "unavailable installed settings stop activation")
            check(!session.log.contains("activate") && !session.log.contains("restore") && owner.lastCleanup == .installationNotOwned,
                  "unknown installed settings cannot authorize overwrite")
        }
        do {
            let session = FakeMixedSession(); session.configureOK = false
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "configuration failure ends gesture")
            check(!session.log.contains("restore") && owner.lastCleanup == .configurationFailedStateUnknown,
                  "partial failed configuration does not overwrite unknown session")
            check(slot.acquire(onRevoked: {}) , "configuration failure does not cause permanent denial")
            slot.release()
        }
        do {
            let session = FakeMixedSession()
            let owner = MixedVoiceAudioCoordinator(session: session)
            let old = owner.acquire(onRevoked: {})!
            check(old.activateForRecording(), "stale release setup")
            var blockedDuringRestore = false
            session.onRestore = { blockedDuringRestore = owner.acquire(onRevoked: {}) == nil }
            old.release()
            let fresh = owner.acquire(onRevoked: {})!
            old.release()
            check(blockedDuringRestore && !old.activateForRecording() && fresh.activateForRecording(),
                  "cleanup blocks reentry and stale lease cannot affect newer session")
            fresh.release()
        }
        do {
            let session = FakeMixedSession(); session.activateOK = false
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && !slot.activateForRecording(), "activation failure ends gesture")
            check(session.current == session.original && owner.lastCleanup == .restoredSettingsActiveStateUnknown,
                  "conditional restore after activation failure reports unknown active state")
        }
        do {
            let session = FakeMixedSession()
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && slot.activateForRecording(), "cleanup read failure setup")
            session.readOK = false
            slot.release()
            check(!session.log.contains("restore") && owner.lastCleanup == .settingsUnavailable,
                  "unknown current settings are left alone")
        }
        do {
            let session = FakeMixedSession(); session.restoreOK = false
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: {}) && slot.activateForRecording(), "restore failure setup")
            slot.release()
            check(owner.lastCleanup == .restoreFailed && slot.acquire(onRevoked: {}), "restore failure reported and retry allowed")
            slot.release()
        }
        do {
            let session = FakeMixedSession()
            let policy = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: policy)
            var notices = 0
            check(slot.acquire(onRevoked: { notices += 1; session.engineRecording = false; slot.release() }), "interrupt setup")
            check(slot.activateForRecording(), "interrupt active")
            session.engineRecording = true
            policy.revokeForSystemChange(); policy.revokeForSystemChange()
            check(notices == 1 && !session.engineRecording && policy.lastCleanup == .restoredSettingsActiveStateUnknown,
                  "interruption stops capture before cleanup once")
            check(slot.acquire(onRevoked: { slot.release() }), "next deliberate gesture allowed after interruption")
            slot.release()
        }
        do {
            let session = FakeMixedSession()
            let coordinator = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: coordinator)
            var notices = 0
            check(slot.acquire(onRevoked: { notices += 1 }), "unacknowledged interruption setup")
            check(slot.activateForRecording(), "unacknowledged interruption active")
            session.engineRecording = true; coordinator.revokeForSystemChange(); coordinator.revokeForSystemChange()
            check(notices == 1 && coordinator.acquire(onRevoked: {}) == nil && !session.log.contains("restore"),
                  "unacknowledged stop never transfers or cleans up")
            session.engineRecording = false; slot.release()
            check(coordinator.acquire(onRevoked: {}) != nil, "release after stopping permits retry")
        }
        do {
            let session = FakeMixedSession(), owner = MixedVoiceAudioCoordinator(session: FakeMixedSession())
            _ = owner
            let coordinator = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: coordinator)
            check(slot.acquire(onRevoked: { slot.release() }), "configuration reentry setup")
            session.onConfigure = { coordinator.revokeForSystemChange(); coordinator.revokeForSystemChange() }
            check(!slot.activateForRecording(), "revocation during configure aborts")
            check(!session.log.contains("activate") && session.current == session.original,
                  "cleanup waits for configuration to return")
        }
        do {
            let session = FakeMixedSession()
            let owner = MixedVoiceAudioCoordinator(session: session), slot = VoiceAudioLeaseSlot(coordinator: owner)
            check(slot.acquire(onRevoked: { slot.release() }), "activation reentry setup")
            session.onActivate = { slot.release() }
            check(!slot.activateForRecording() && session.current == session.original,
                  "cancel waits for activation to return before restore")
        }
        do {
            var clock: TimeInterval = 1
            let session = FakeMixedSession(); session.webKitPlaying = true
            let owner = MixedVoiceAudioCoordinator(session: session)
            let driver = FakeMixedDriver(session: session, coordinator: owner)
            let machine = VoiceInputStateMachine(driver: driver, now: { clock })
            var draft = "typed"
            machine.onFinal = { draft = VoiceDraftJoin.join(draft, $0) }
            machine.begin(gestureStartedAt: clock)
            let oldID = driver.latest!
            check(session.engineRecording && session.webKitPlaying, "real state machine starts mixed fake driver")
            clock += 1; machine.release()
            check(draft == "typed spoken" && !session.engineRecording && session.webKitPlaying,
                  "normal gesture stops audio before adding final to draft")
            machine.begin(gestureStartedAt: clock)
            let cancelled = driver.latest!
            machine.cancel()
            driver.callbacks[cancelled]?(cancelled, .final("late"))
            driver.callbacks[oldID]?(oldID, .final("duplicate"))
            check(draft == "typed spoken" && !session.engineRecording && machine.state == .idle,
                  "cancel and stale results never change draft")
        }
        print("PASS MixedVoiceAudioCoordinator: \(assertions) assertions; fake session only")
    }
}
