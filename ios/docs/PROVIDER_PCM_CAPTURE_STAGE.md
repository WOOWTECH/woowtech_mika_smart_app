# Provider PCM capture stage

The original capture candidate `6dc7d87de70710bf6b1c9f8a8ea68972194766db`
was based on `00259358d75cce62a0e8f565db3d2b3e7023c80c` and incorporated
the earlier PCM candidate `151f377`. A later isolated candidate adds the
native-source seam and FIR described below.
It adds capture and lifecycle components, but does not add a selectable
provider or connect a real recorder to the composer, settings or transport.
The dispatch-fence and prior data-flow candidates are under independent
review and are not assumed to be approved for production audio.

Android's `PcmRecorder.kt` captures mono 16-bit 16 kHz PCM. Its
`ProviderSpeech.kt` sends after release, ignores recordings shorter than
500 ms and bounds recording and transcription. This candidate provides:

* An injectable source and `ProviderPCMVoiceDriver` implementing the existing
  `VoiceInputDriver` contract. A source is permitted only after the shared
  audio lease, microphone permission, live listening check and authorization
  checks. It rechecks immediately before engine start. Release closes the
  buffer and stops the source before releasing the lease or invoking the
  injected transcriber. An unavailable lease denies capture.
* Bounded `ProviderPCMBuffer` conversion from interleaved Float samples at an
  integer 8–192 kHz, 1–8 channels, to signed 16-bit mono 16 kHz. It clips,
  mixes channels and uses a bounded streaming low-pass FIR before downsampling,
  with integer timing and quantized fractional-phase banks. It rejects malformed
  samples and a mid-stream format change. The buffer discards on the 60-second
  sample limit rather than treating that limit as user release. Filter
  measurements, startup delay, and limits are in `PROVIDER_PCM_NATIVE_FIR.md`.
* An iOS `AppleProviderPCMSource` using an AVAudioEngine input tap, an injectable
  `CoordinatedProviderPCMSource` for source lifecycle, plus a factory on the
  same `AppleMixedVoiceRuntime` coordinator as device speech.
  The factory is not used by the app. Source interruption, relevant route
  changes and media-service reset fail capture. Buffer closure precedes source
  stop, so a late audio callback cannot add to the finished recording.
* Cancellation and independent 60-second capture / 30-second finishing
  deadlines. Cancel closes the buffer, stops capture, releases the lease and
  cancels pending transcription; stale permission, audio and completion
  callbacks cannot deliver a result. `ChatVoiceController` now accepts an
  optional finishing timeout; its existing five-second device default is
  unchanged. A future provider host must explicitly choose 30 seconds. The
  driver calls its required `onEnd` callback once with the capture ID, so its
  owner can discard that recording's still-unused provider token without
  invalidating a newer token or the verified provider selection. Stopping an
  already-started upload still relies on cancellation of the transcription task.

`check_provider_pcm.sh` compiles the real driver, conversion, mixed-audio
coordinator and composer with injected source, fake session and fake
transcriber. It covers conversion across chunk boundaries, sample limits,
permission/setting races, competing device and provider leases, synchronous
revocation, cancellation, timeouts, source failures, reentrant cleanup and
late callbacks. `check_configured_provider_speech.sh` also feeds synthetic
PCM through this driver and the earlier real settings/WAV/request/response
seam, with isolated defaults, fixture credentials and a fake transport. It
checks the resulting WAV sample and transcript, and verifies that changing
settings or cancelling after capture but before dispatch sends nothing. It
also verifies that cancellation during capture discards the unused token and
that a stale cancellation cannot revoke a newer recording. No microphone or
service is used. Existing device speech and mixed-audio standalone checks run too.

Before product integration, the owner must route scene/background, gesture,
conversation and settings changes to cancellation, supply a live authorization
check through the finishing phase, and bind the selected model, destination,
credential revision and recording ID to the transcriber. In particular a
settings change must actively cancel an in-flight task; checking on completion
alone does not retract an upload. Cancellation cannot recall already-sent
bytes and a noncooperative transcriber may retain its input until it returns.
The main-actor timeout and audio-error callbacks can be delayed while that
actor is blocked; the bounded collector prevents further data growth but is
not a hard real-time hardware deadline. The shared mixed coordinator serializes
these app voice clients, not every OS or WebKit audio user, and does not prove
restoration of the AVAudioSession active state.

This host has no iOS SDK. The native AVFoundation branch has not been
SDK-typechecked or run, and permission prompts, audio routes, engine stop,
interruptions, background transitions, audio quality and physical-device
behavior need native tests. There has been no real microphone, provider or
network request in these tests. Real provider selection, persistence, Android's
20-second overall probe deadline, and production transport/lifecycle wiring
remain separate work.
