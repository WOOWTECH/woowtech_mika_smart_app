#if os(iOS) && canImport(AVFoundation)
import AVFoundation

/// Candidate adapter only. The caller still needs an authoritative exclusive
/// fence; AVAudioSession doesn't provide the prior active-state claim here.
@MainActor
final class AppleVoiceAudioSessionAccess: VoiceAudioSessionAccess {
    private let session: AVAudioSession
    init(session: AVAudioSession = .sharedInstance()) { self.session = session }
    func settings() -> VoiceAudioSettings? {
        VoiceAudioSettings(category: session.category.rawValue, mode: session.mode.rawValue,
                           options: session.categoryOptions.rawValue)
    }
    func configureRecording() -> Bool {
        do { try session.setCategory(.record, mode: .measurement, options: []); return true }
        catch { return false }
    }
    func activate() -> Bool {
        do { try session.setActive(true); return true } catch { return false }
    }
    func deactivate() -> Bool {
        do { try session.setActive(false, options: .notifyOthersOnDeactivation); return true }
        catch { return false }
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
#endif
