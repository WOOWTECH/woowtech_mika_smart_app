# Provider speech: isolated data-flow stage

Base: `26a0e61feffc852e61276e1ad0d52a6a4612aa18`. This is a reviewable
intermediate stage, not a provider speech feature. No settings entry, microphone,
composer, background notification, or service is connected to this flow. The
existing on-device Apple Speech selection and driver remain in use.

Android's `SpeechModelScreen.kt`, `SpeechOptions.kt`, `SpeechResolver.kt`,
`ModelSetupViewModel.kt`, `Transcriber.kt`, and `ProviderSpeech.kt` show a
real configured-provider list, device/off options and manual model entry. A
user-initiated selection sends a one-second silent WAV for method detection;
a failure retains the previous selection. The selected provider is used on
press/release without a new per-recording dialog. Recordings shorter than
500 ms are discarded, and capture is limited to 60 seconds. An unavailable
provider never silently falls back to a different paid provider. The current
integration and its validation limits are in `PROVIDER_PCM_INTEGRATION_D60FD8A.md`.

The iOS repository currently contains just one chat configuration, with no
provider catalog or reliable provider kind. The new seam therefore requires an
explicit caller-supplied kind, model and freshly re-entered exact saved base
URL. It uses the real model settings repository and reads its Keychain account
through the existing credential interface. A successful explicit probe selects
one supported method in memory. It can then construct a bounded WAV and a
request for a one-use recording ID, and parse the transcript through the same
provider core. A failed probe retains the prior selection if its binding is
still valid. There is no implicit network access on initialization, no invented
provider list, and no additional per-recording confirmation in this seam.

The binding includes the full saved URL, chat model, credential account and a
new write revision. Successful repository writes advance the revision, so an
edit followed by restoration of the old settings still invalidates old work.
A replaced Keychain credential receives a new account through the existing
repository. The revision is an in-process coordination aid, not proof against
out-of-band defaults or Keychain mutation or cross-process ordering. External
changes and any future provider-specific settings need their own binding and
notifications. It does not itself notify or cancel anything.

An explicit invalidation cancels the current task and rejects late results;
a newer gesture supersedes an older one. Cancellation cannot retract bytes
already sent. This seam is deliberately **not authorized for production audio**:
its owner must first connect settings changes, cancellation, app/scene
backgrounding and the existing permission/start race checks to cancellation,
including the interval before the request actually starts. It must also bind a
user-selected persistent provider/model/method, add the Android-style overall
20-second probe limit, integrate bounded 16 kHz PCM capture and the 30-second
transcription lifecycle, present accurate destination and upload disclosure,
and preserve existing on-device recognition. Those conditions require a real
UI and native lifecycle work; this stage does not advertise a provider choice.
The previous independent per-recording confirmation experiment is not used.

`check_configured_provider_speech.sh` compiles the real repository and seam with
an isolated UserDefaults suite, fake credentials and an injected in-memory
transport. It checks reviewed destinations, method detection/fallback, retained
selection, short audio, one-use recording IDs, new/old gesture interleavings,
settings edit-and-revert, credential replacement, cancellation and late results,
and explicit Gemini method construction. No service or microphone is used.
`check_provider_speech.sh` and `check_provider_speech_settings.sh` cover the
separate request, URL authority and saved-settings boundaries. The default
transport's actual iOS TLS, redirect, cancellation and timeout behavior, real
microphone permissions, audio conversion, UI and real provider compatibility
remain unverified on this host. Simulator/device tests and controlled service
tests are needed before enabling the feature.

A later isolated fix addresses a pre-dispatch settings race in this seam;
see `PROVIDER_SPEECH_DISPATCH_FENCE.md` for its ordering and limits.

A later isolated candidate adds an unconnected PCM source and driver; see
`PROVIDER_PCM_CAPTURE_STAGE.md`. It does not enable provider speech.
