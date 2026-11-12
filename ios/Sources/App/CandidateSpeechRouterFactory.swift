#if os(iOS) && canImport(AVFoundation)
import AssistantModels
import Foundation

/// Production adapters, deliberately unreachable from settings and chat
/// until native lifecycle, destination disclosure and service tests pass.
@MainActor
enum CandidateSpeechRouterFactory {
    static func make(repository: ModelSettingsRepository, defaults: UserDefaults) -> CandidateSpeechRouter {
        let flow = ConfiguredProviderSpeech(repository: repository, transport: URLSessionSpeechTransport())
        return CandidateSpeechRouter(flow: flow, store: SpeechChoiceStore(defaults: defaults), systemFactory: { AppleMixedVoiceRuntime.makeDriver() },
            providerFactory: { mayFinish, onEnd, transcribe in
                AppleMixedVoiceRuntime.makeProviderPCMDriver(mayFinish: mayFinish, onEnd: onEnd, transcribe: transcribe)
            })
    }
}
#endif
