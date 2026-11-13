import Foundation

/// One shared owner is required for all registered clients and the voice
/// driver. Instantiation alone does not attest coverage or enable the feature.
@MainActor
final class VoiceAudioRuntimeCandidate {
    let fence: VoiceAudioAdmissionFence
    let coordinator: SharedVoiceAudioCoordinator

    init(session: any VoiceAudioSessionAccess) {
        let fence = VoiceAudioAdmissionFence(session: session)
        self.fence = fence
        self.coordinator = SharedVoiceAudioCoordinator(provider: fence, session: session)
    }
}

#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
@MainActor
extension VoiceAudioRuntimeCandidate {
    /// Unconnected candidate; the host must first instrument every route and
    /// pass native validation. The adapter's iOS SDK typecheck is still pending.
    static func appleCandidate() -> VoiceAudioRuntimeCandidate {
        VoiceAudioRuntimeCandidate(session: AppleVoiceAudioSessionAccess())
    }
    func makeVoiceDriver() -> AppleVoiceInputDriver {
        AppleVoiceInputDriver(audioCoordinator: coordinator)
    }
}
#endif
