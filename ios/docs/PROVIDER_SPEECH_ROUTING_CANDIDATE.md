# Isolated speech selection and routing candidate

This candidate starts at `dcbcab97fa363778fbca61fd25bae3f8c76f65e7`.
The later chat host constructs the router for system/off, but provider
selection remains unavailable; see `PROVIDER_SPEECH_UI_CANDIDATE.md`.
Android `SpeechModelScreen` presents device and off,
plus each supported configured provider and manual model entry. A tap probes
one second of silence, preserves the previous selection on failure, and uses
the selected method on subsequent recordings without a per-recording dialog.
Android limits the entire probe to 20 seconds; that limit is still absent here.

The iOS app currently stores one chat provider, with no provider catalog or
trustworthy provider kind. The candidate accepts an explicitly selected kind,
speech model and raw saved URL, probes through the existing authorized
dispatch boundary, and routes an explicit choice to a system driver, off, or a
PCM provider driver. The iOS-only factory wires the real shared Apple voice
coordinator, `AppleProviderPCMSource` and `URLSessionSpeechTransport`; the UI
does not select the provider path. A host must call `invalidate()` for scene
or settings changes, and must use a suitable finish timeout. The router
rechecks the selected settings on permission and dispatch, releases the lease
before upload, and fences stale callbacks. Switching choice cancels active
capture and outstanding provider work.

The choice store persists only provider ID, speech model and method,
or system/off; it does not store a key, destination or recording. A stored
provider choice is visible but cannot capture or dispatch after process restart
until an explicit new probe re-establishes the destination, credentials and
method. This is a known departure from Android and is not a completed settings
experience. Corrupt settings fail closed. Persisting the full authorization
binding safely and handling a real multi-provider inventory remain future work.

Choice writes through `SpeechChoiceStore` and model writes through
`ModelSettingsRepository` share one in-process recursive dispatch lock. A
choice revision changes on every store write, so an off/on change in another
window prevents an already staged recording or probe from dispatching, even if
the old value is restored. This does not coordinate out-of-process writers or
direct UserDefaults/Keychain mutation. The host still has to observe changes
and actively stop an already-running engine; checking at dispatch alone does
not provide that behavior.

`check_configured_provider_speech.sh` exercises the actual selection router,
repository binding, PCM driver and WAV/request construction with synthetic audio,
fake credentials and an injectable transport. It also runs actual
`URLSessionTask.resume()` using a custom URLProtocol that intercepts every URL
locally. These tests do not make DNS requests or contact a service. URLProtocol
is not evidence of real TLS, certificates, redirect behavior, actual network
cancellation or provider protocol compatibility. The factory and UI are not
iOS SDK typechecked or simulator-tested on this host; microphone permission,
actual AVAudioEngine, physical routes and provider services remain unverified.
Provider entry must remain closed pending these checks and lifecycle wiring.
Once bytes have reached URLSession/network they cannot be recalled.
