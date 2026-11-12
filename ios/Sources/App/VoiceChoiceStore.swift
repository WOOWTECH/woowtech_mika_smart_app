import Foundation

/// The choices that are actually available on iOS today. Unknown stored values
/// fail closed; they must never silently become a provider or Apple recognition.
enum VoiceChoice: String {
    case automatic, system, off, unavailable
    var allowsDeviceRecognition: Bool { self == .automatic || self == .system }
}

struct VoiceChoiceStore {
    static let key = "voice.choice.v1"
    static let productionSuite = "io.woowtech.assistant.voice-choice.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }

    struct Snapshot {
        let choice: VoiceChoice
        let revision: String
        var authorization: String? { choice.allowsDeviceRecognition ? revision : nil }
    }
    func snapshot() -> Snapshot {
        guard let value = defaults.object(forKey: Self.key) else {
            return Snapshot(choice: .automatic, revision: "initial")
        }
        guard let fields = value as? [String: String], fields.count == 2,
              let raw = fields["choice"], let choice = VoiceChoice(rawValue: raw),
              choice == .system || choice == .off,
              let revision = fields["revision"], UUID(uuidString: revision) != nil else {
            return Snapshot(choice: .unavailable, revision: "invalid")
        }
        return Snapshot(choice: choice, revision: revision)
    }
    func load() -> VoiceChoice { snapshot().choice }
    func select(_ choice: VoiceChoice) {
        guard choice == .system || choice == .off else { return }
        defaults.set(["choice": choice.rawValue, "revision": UUID().uuidString], forKey: Self.key)
    }

    static func suiteName(arguments: [String], debug: Bool) -> String? {
        guard debug else { return productionSuite }
        let modes = [("-UITestMode", "-UITestNamespace"), ("-LiveModelUITest", "-LiveModelUITestNamespace")]
        let hasTestArguments = arguments.contains { $0.hasPrefix("-UITest") || $0.hasPrefix("-Live") }
        guard hasTestArguments else { return productionSuite }
        let selected = modes.filter { arguments.contains($0.0) }
        guard selected.count == 1, let mode = selected.first,
              arguments.filter({ $0 == mode.0 }).count == 1,
              arguments.filter({ $0 == mode.1 }).count == 1,
              !modes.contains(where: { $0.1 != mode.1 && arguments.contains($0.1) }),
              let index = arguments.firstIndex(of: mode.1), arguments.indices.contains(index + 1),
              let namespace = UUID(uuidString: arguments[index + 1]) else { return nil }
        return productionSuite + ".test." + namespace.uuidString
    }
    static func application(arguments: [String] = ProcessInfo.processInfo.arguments) -> VoiceChoiceStore {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        guard let suite = suiteName(arguments: arguments, debug: debug),
              let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Voice preferences require an isolated test namespace")
        }
        #if DEBUG
        if arguments.contains("-UITestMode"), arguments.contains("-UITestResetStorage") {
            defaults.removePersistentDomain(forName: suite)
        }
        #endif
        return VoiceChoiceStore(defaults: defaults)
    }
}
