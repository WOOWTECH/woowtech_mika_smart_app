# Android speech selection and iOS device/off data path

Comparison base: iOS `f463cf268265ae3252f5f37fa14503dd7e6d0535`. The Android
speech selection, resolver, options, recorder, transcriber and model-selection
sources at this base match Android main `de5be358c4e24b7eed46a95e46edf35a86881bff`. This is a partial candidate, not provider speech
parity. The existing Apple Speech driver remains the only iOS driver.

Android's `SpeechModelScreen.kt` offers device speech and off, and lists real
eligible configured providers grouped by provider with likely speech models and
a manual model field. `SpeechOptions.kt` filters the actual provider list using
`Transcriber.supports`; it does not manufacture providers. `ModelSetupViewModel.kt`
`pickSpeechModel` trims the chosen model and performs a one-second silent WAV
probe; it stores provider ID, model and detected method only on success. The
probe can contact a provider and consume quota. `SpeechResolver.kt` uses the
stored choice and current provider list. Auto uses a usable system recognizer,
never silently falls back to a paid provider, and a removed selected provider
is unavailable. Android's `ProviderSpeech.kt` records on press and sends after
release; sub-500 ms recordings are discarded and the request has a 30-second
transcription timeout. There is no additional dialog for each recording.
System recognition may be on-device or online on Android; the existing iOS
Apple driver explicitly requires on-device recognition.

On iOS, model settings currently contain a single chat base URL, chat model,
and Keychain account, not Android's provider inventory, provider kind, model
catalog or verified transcription method. A chat endpoint/model is not evidence
of a compatible speech provider. At the comparison base, the earlier `49b409f`
provider request core and `0b2ccb1` upload-consent experiment were separate
unmerged candidates: neither
is wired to iOS settings, a recorder, lifecycle notifications or the composer.
The earlier consent experiment requires an explicit confirmation per recording;
that flow must not be presented as Android parity or added blindly. A later
integration must reconcile the user's informed selection and press/release with
any required upload authorization, cancellation, settings/credential version
binding and retries, without inventing an extra confirmation on every press.
It must also review the raw destination serialization and path, actual
credential lifetime, provider capabilities, redirects, TLS, size limits and
scene/gesture races before sending audio.

A later isolated candidate imports the request core and adds an unconnected
settings-to-transport seam; see `PROVIDER_SPEECH_DATAFLOW_STAGE.md`. It still
does not enable provider recording or the per-recording consent experiment.

This candidate adds a real Settings > Model > Speech to text destination with
only two working selections: on-device recognition and off. An absent setting
retains the previous on-device behavior. It persists the selection in an
isolated voice defaults suite; UI and live-test modes use namespaced suites.
The actual composer controller consults this preference before driver start,
release, timer work and draft insertion. Each settings write changes a revision:
turning off then back on does not revive the previous recording's result. Off or
an unrecognized/corrupt saved choice cannot start the driver; a settings change
during capture actively cancels when the preference revision notification is
processed. Independently, the driver checks the live revision after permission
callbacks and immediately before starting capture, without waiting for a tick;
a late result cannot enter the draft. Details and native limits are in
[the permission-race regression](VOICE_DISABLE_PERMISSION_RACE.md). The existing scene, gesture, conversation and
recording-time cancellation behavior remains in place. No model or provider is
created or called, and no new upload/probe permission prompt is added.

`bash ios/scripts/check_chat_voice.sh` exercises the real choice store,
preferences and composer with a fake driver, including persistence, separate
store instances, invalid choices, off/on races, mid-capture cancellation and
restoring the device driver. `python3 ios/scripts/test_voice_input.py` checks
the existing voice state, audio coordination and fixture boundaries. The added
`ChatVoiceUITests` case is intended for an iOS simulator; it uses the existing
isolated fake voice driver and must be run with an iOS SDK. This host can compile
Foundation/Combine and parse iOS sources, not typecheck SwiftUI/UIKit against an
iOS SDK. Real microphone permissions, actual device recognizer availability,
scene delivery, UI accessibility, and audio interactions need native checks.
Provider selection, verified model detection, provider PCM capture/conversion,
network transport integration, policy/lifecycle coupling, provider errors and
actual service interoperability remain unimplemented here.
