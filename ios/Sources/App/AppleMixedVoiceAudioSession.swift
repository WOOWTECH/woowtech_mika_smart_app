#if os(iOS) && canImport(AVFoundation)
import AVFoundation

/// iOS candidate: simultaneous recording/playback and mixing with other apps.
/// Bluetooth routing and WebKit interaction require native validation.
@MainActor
final class AppleMixedVoiceAudioSession: MixedVoiceAudioSession {
    private let session: AVAudioSession
    init(session: AVAudioSession = .sharedInstance()) { self.session = session }
    func settings() -> VoiceAudioSettings? {
        VoiceAudioSettings(category: session.category.rawValue, mode: session.mode.rawValue,
                           options: session.categoryOptions.rawValue)
    }
    func configureMixedRecording() -> Bool {
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            return true
        } catch { return false }
    }
    func isMixedRecording(_ settings: VoiceAudioSettings) -> Bool {
        // Bluetooth options are route preferences; their absence must not by
        // itself disable speech on devices that normalize category options.
        let expected = AVAudioSession.CategoryOptions.mixWithOthers.rawValue
        return settings.category == AVAudioSession.Category.playAndRecord.rawValue
            && settings.mode == AVAudioSession.Mode.default.rawValue
            && settings.options & expected == expected
    }
    func activate() -> Bool {
        do { try session.setActive(true); return true } catch { return false }
    }
    func restore(_ settings: VoiceAudioSettings) -> Bool {
        do {
            try session.setCategory(AVAudioSession.Category(rawValue: settings.category),
                                    mode: AVAudioSession.Mode(rawValue: settings.mode),
                                    options: AVAudioSession.CategoryOptions(rawValue: settings.options))
            return true
        } catch { return false }
    }
}

/// All candidate drivers in the App share one voice coordinator. The chat host
/// manages scene lifecycle; WebKit and physical routing still need native tests.
@MainActor
enum AppleMixedVoiceRuntime {
    private static let coordinator = MixedVoiceAudioCoordinator(session: AppleMixedVoiceAudioSession())
    static func makeDriver() -> AppleVoiceInputDriver {
        AppleVoiceInputDriver(audioCoordinator: coordinator)
    }
    static var lastCleanup: MixedVoiceAudioCleanup? { coordinator.lastCleanup }
    static func revokeForSystemChange() { coordinator.revokeForSystemChange() }
}
#endif
