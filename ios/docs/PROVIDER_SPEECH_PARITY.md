# Provider speech: Android data flow and isolated iOS core

Status: research and a standalone, unconnected core. The existing Apple Speech
candidate is not parity with Android's speech-model settings. No UI, recorder,
provider account, permission change or production network call was added here.
Android source reviewed at main worktree `220cadf` (the speech source matches
this worktree's Android snapshot). This worktree starts from iOS candidate
`970ee8f`; it does not include subsequent work on the main worktree.

## Android behavior

`SpeechModelScreen.kt` is reachable from model settings or the chat voice entry.
It groups eligible saved providers, lists models using name heuristics, preserves
a selected model absent from the list, and permits a typed model. `SpeechChoice.kt`
persists `auto`, `system`, `off` or `provider` with provider ID, model and
`TranscribeMethod`. `SpeechResolver.kt` does not automatically fall back to a
paid provider when system recognition fails or the selected provider disappears.
`SystemSpeech.kt` distinguishes offline from online system recognition; the
selected app language supplies the recognition tag.

`Transcriber.supports` accepts API-key-style OpenAI-compatible, OpenAI Responses,
and Gemini provider kinds only when `signIn == null`; it excludes Anthropic and
account-login providers. This is a protocol eligibility filter, not a claim that
all models or services in those categories transcribe correctly. Model-name
heuristics match tokens such as `asr`, `transcribe`, `whisper`, `paraformer`,
`sensevoice`, `stt` and `speech`, so listing is not capability proof.
Preset examples in the eligible kinds include OpenAI, Gemini, API-key OpenRouter,
Requesty, OpenCode Go, API-key xAI, Mistral and Groq, plus custom endpoints.
Android also lists local Ollama and LM Studio HTTP endpoints; the iOS foundation
below deliberately accepts HTTPS only and does not yet support those HTTP
presets. Account sign-in entries are excluded even when their API-key counterpart
uses an eligible kind. Listing a preset is not evidence its endpoint or any
particular model supports any of the five audio methods.

When choosing a provider model, `ModelSetupViewModel.pickSpeechModel` uploads a
one-second synthetic silent WAV with a 20-second probe timeout. The first
response with a parseable text field wins, including an empty string; model
verification and the selected method are saved only on success. It tries:

1. `POST <base>/audio/transcriptions`: multipart WAV, model, optional language.
2. `POST <base>/chat/completions`: base64 `input_audio` plus text instruction.
3. The same with an audio data URI plus instruction.
4. The same data URI without instruction, for audio-only models.
5. For Gemini, `POST <base>/v1beta/models/<model>:generateContent` with
   `inline_data`, audio MIME and a transcription instruction.

The Gemini path is an alternative to steps 1–4, not a fifth sequential retry.
An `OpenAiResponses` provider still uses transcription or chat-completions for
speech; it does not send this recording to `/responses`.
Provider requests include provider-specific headers and credentials; see
`ProviderStore.clientHeaders` and `Transcriber.builder`. Android retries another
method only for its mapped model-not-found or bad-response failures, not all
errors. Probe success alone cannot prove transcript accuracy or provider data
handling; it can consume quota, and probing general chat models can yield a
non-transcription answer. The official [OpenAI transcription guide](https://developers.openai.com/api/docs/guides/speech-to-text)
documents multipart transcription and current models; the current guide also
lists deprecation dates for several older examples. [Google's audio guide](https://ai.google.dev/gemini-api/docs/audio)
documents audio input to Gemini. The data-URI variants are Android compatibility
attempts for particular providers, not universal OpenAI or Gemini guarantees.

When the user presses and then releases, `ProviderSpeech` records at most 60 s
of 16 kHz mono PCM, ignores captures below 500 ms, packages WAV, and calls the
selected provider. It waits at most 30 seconds for transcription, reports
failure, and cancellation discards capture/cancels work. Network providers do
not provide the Android system recognizer's live partial transcript.

## iOS candidate and what is still missing

The Apple candidate requests microphone and Speech authorization, requires
`supportsOnDeviceRecognition` and sets `requiresOnDeviceRecognition`; it is
not an online Apple Speech or provider fallback. It uses the device locale
rather than Android's app-display-language mapping. It already has a mixed
`playAndRecord` audio-session candidate, whose WebKit interaction and prior
active state have not been verified. No Android provider list, provider setup,
model/manual picker, off choice UI, probe, provider recorder, PCM conversion,
or provider speech session is connected. The iOS existing model settings have
one endpoint/model and Keychain-backed credential reference, not Android's
multiple-provider inventory or session headers.

`ProviderSpeech.swift` adds only a composable data/transport foundation:

- Four choices and the five Android method names; choice stores a provider ID,
  model and method, never credentials. A corrupt saved choice fails explicitly
  rather than silently falling back to another destination. The caller supplies
  a `UserDefaults` suite; no production suite is selected by this core.
- 16 kHz mono 16-bit WAV encoding and validation, capped at 60 seconds.
- Synthetic-testable multipart, three chat-audio variants and Gemini request
  builders plus response parsing. A user-selected provider ID must match the
  endpoint. Credentials are supplied per call and are not stored here.
- HTTPS authority validation rejects empty, nonnumeric, overflowing,
  out-of-range and leading-zero explicit ports at both request construction
  and transport; bracketed IPv6 literals must parse as IPv6.
  The generated request must retain the exact serialized authority and intended
  path, and the URLSession transport validates it again before sending. Escaped
  authorities and scoped IPv6 literals are conservatively unsupported. This
  does not provide DNS pinning or establish user consent. Path normalization
  across URL loading, proxies and servers remains unresolved; comparing the
  serialized path is not proof that all parties interpret it identically.
- An injectable async transport and an ephemeral URLSession transport with
  30-second configured request/resource timeouts, rejected redirects, disabled
  cookies/cache/credential storage, bounded success response and sanitized
  errors. No automatic probe, retry or fallback is included.

This foundation is not proof that any endpoint/model accepts the protocol. It
does not validate transcripts, capture microphone input, ensure billing is off,
or perform the Android probe. Generic `SpeechProviderTransport` implementations
must provide their own timeout, cancellation, redirect and privacy guarantees.
The endpoint identity check does not detect a provider URL or credential change
under the same ID; a future integration must bind explicit upload consent to
the provider, exact destination and credential version, and invalidate consent
and require renewed review when any binding or relevant setting changes. It
must check that binding again immediately before upload. No such consent or
settings integration is implemented by this isolated core.
Provider-specific headers, model enumeration, Keychain provider inventory,
probe selection policy and error presentation remain to be designed and tested.

## Consent, privacy and native validation before integration

* Microphone capture needs `NSMicrophoneUsageDescription` and authorization;
  Apple Speech additionally needs `NSSpeechRecognitionUsageDescription` and
  `SFSpeechRecognizer` authorization, even when configured on device. Provider
  transcription that does not invoke Apple Speech does not require the Speech
  framework merely to upload WAV. Existing plist copy should be reviewed for
  the actual provider path and localized prompt selection before shipping.
* Clearly identify the destination and that recorded audio leaves the device,
  disclose possible provider charges and retention, obtain explicit user
  permission before sharing with a third party, and offer withdrawal. A silent
  probe can consume quota too; do not auto-probe without a user action and
  disclosure. Never silently switch from on-device to a provider. Apple's
  [App Review guidelines](https://developer.apple.com/app-store/review/guidelines/)
  address recording indication, consent and third-party data sharing; review
  [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
  against the app's actual collection and provider contracts.
* Use existing Keychain practices with origin-bound credentials; do not log,
  persist, or retain PCM/WAV/transcripts or authorization headers beyond the
  needed request lifecycle. Cancellation cannot retract bytes already uploaded.
  In-memory copies cannot be guaranteed securely erased by Swift `Data`.
* On a MacBook, run iOS 17 Debug/Release builds, synthetic network intercepts,
  permissions and cancellation UI tests. A later independently authorized test
  plan must cover real device microphone capture, hardware sample-rate conversion,
  denied/restricted permission, backgrounding, mixed WebKit playback, audio
  routes/interruption, provider errors, changed destination/credentials, and
  provider transcription accuracy/cost. No actual provider or microphone test
  was performed for this work.

Local reproducible check: `bash ios/scripts/check_provider_speech.sh`. It uses
small synthetic PCM, an injected fake transport and an intercepted URLSession;
it never sends audio or credentials over a network. Passing host tests is not
iOS SDK validation or evidence of service compatibility.
