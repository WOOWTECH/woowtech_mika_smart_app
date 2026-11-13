#if DEBUG
import Combine
import Foundation

/// Closed simulator-only test driver. Cancellation deliberately retains the
/// callback so tests can deliver an actually stale result deterministically.
@MainActor
final class VoiceUITestFixture: ObservableObject, VoiceInputDriver {
    static let flag = "-UITestVoiceFixture"
    static let shared = VoiceUITestFixture()
    static let result = "fixture voice"
    @Published private(set) var starts = 0
    @Published private(set) var finishes = 0
    @Published private(set) var cancellations = 0
    @Published private(set) var emissions = 0
    @Published private(set) var accessibilityAction = ""
    private var latest: UUID?
    private var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var activateAccessibility: (@MainActor () -> Bool)?
    var cancelAccessibility: (@MainActor () -> String?)?

    static func valid(arguments: [String], simulator: Bool) -> Bool {
        let allowed = [flag, "-UITestMode", "-UITestNamespace", "-UITestResetStorage"]
        guard simulator, arguments.filter({ $0 == flag }).count == 1,
              arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
              arguments.filter({ $0 == "-UITestResetStorage" }).count <= 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              !arguments.contains(where: { $0.hasPrefix("-UITest") && !allowed.contains($0) }),
              let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
              let uuid = UUID(uuidString: arguments[index + 1]),
              uuid.uuidString.lowercased() == arguments[index + 1].lowercased() else { return false }
        return true
    }
    static func selected(arguments: [String] = ProcessInfo.processInfo.arguments) -> VoiceUITestFixture? {
        guard arguments.contains(where: { $0.hasPrefix(flag) }) else { return nil }
        #if targetEnvironment(simulator) || VOICE_UI_FIXTURE_STANDALONE
        let simulator = true
        #else
        let simulator = false
        #endif
        precondition(valid(arguments: arguments, simulator: simulator), "Invalid isolated voice UI fixture")
        return shared
    }
    func start(id: UUID, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        latest = id
        callbacks[id] = emit
        starts += 1
    }
    func finish(id: UUID) { if callbacks[id] != nil { finishes += 1 } }
    func cancel(id: UUID) { if callbacks[id] != nil { cancellations += 1 } }
    func emitLatest() {
        guard let id = latest, let callback = callbacks[id] else { return }
        emissions += 1
        callback(id, .final(Self.result))
    }
    func performAccessibilityCancel() { accessibilityAction = cancelAccessibility?() ?? "missing" }
    var observation: String { "start=\(starts) finish=\(finishes) cancel=\(cancellations) emit=\(emissions)" }
}
#endif
