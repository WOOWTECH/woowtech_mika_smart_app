# Chat voice input: candidate and native validation

The chat composer uses the iOS Speech framework with **on-device recognition required**.
Press for 0.3 seconds to start; release after at least 0.5 seconds to finish,
or slide upward more than 70 points and release to cancel. A successful result
is appended to the current draft and is never sent automatically. VoiceOver
activation toggles start and finish; while active, its custom action “Cancel
voice input” discards the capture. An interruption or system permission
dialog may end a gesture; press again after returning to the app.

The speech locale is the device's current locale, independently of the App's
display-language setting. The App's UI messages support Traditional Chinese
and English; a Simplified Chinese system shows Traditional Chinese. The OS
chooses its own localized permission prompt. The Debug and Release plists
include both privacy keys; localized InfoPlist.strings provide their
translations, and zh-Hans.lproj carries the Traditional Chinese prompts so a
Simplified Chinese system gets those, not English (it also keeps that system's
current locale, and so its speech locale, Chinese). Recognition is not uploaded to a
provider by this implementation. If on-device recognition is unavailable, the
keyboard remains available. A provider transcription path, its explicit privacy
disclosure, consent, transport and tests are separate future work; unavailability
of on-device recognition does not establish that all speech options are unavailable.

The mixed session is a candidate: it uses playAndRecord/mixWithOthers and does
not assert exclusive control of WebKit. It conditionally restores category,
mode and options when still owned, and does not deactivate the shared session
because the previous activation state cannot be determined. Activation and
route changes can affect other audio and the session may remain active. Fake
tests cannot establish safety for WebKit or other apps.

## Debug simulator UI fixture

`VoiceUITestFixture` is compiled only in Debug and activates only with its
explicit flag, `-UITestMode`, a valid isolated UUID namespace, no other test
fixture or Live flags, and the simulator. It never requests speech or microphone
authorization. Its UI buttons deliver a fixed synthetic result, including
after cancellation; counters establish that a late callback was actually
delivered. A Debug bridge invokes the production button's
`accessibilityActivate()` and its installed cancel-action handler; this tests
those entry points, not the VoiceOver service or rotor behavior itself.

Run the simulator suite on the MacBook from `ios/`, with a disposable simulator:

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:WoowAssistantUITests/ChatVoiceUITests test
```

The background case sends the simulator Home and reactivates the app; do not
run this suite against a physical device. `python3 scripts/check_voice_ui_fixture.py`
tests the fixture gates and fake callback on the host and verifies that its
standalone Release object contains no fixture symbol, flag or synthetic result.
The actual Debug and Release app builds, UI suite, packaged Release binary and
VoiceOver rotor remain native validation tasks; none have run here.

## Evidence available without iOS SDK

Run `bash scripts/check_chat_voice.sh`, `python3 -m unittest discover -s scripts
-p test_voice_input.py`, `python3 scripts/generate_app_text.py`, and the existing
`CheckChatScrollFollow.swift` harness. The fake driver tests verify draft merging,
gesture cancellation, stale results, context identity, interruption, denial and
timeout. Parsing an iOS target is syntax checking only, not an SDK build or a UI test.

## MacBook validation, before considering the candidate verified

1. Generate the project with the repository's XcodeGen workflow and compile
   Debug and Release with the iOS 17 SDK. Confirm that the app bundle contains
   the en, zh-Hant and zh-Hans (Traditional text) InfoPlist.strings and both
   usage keys.
2. With a simulator where supported, run existing ChatStreamingUITests,
   ConversationArchiveUITests and the chat draft tests. Check typed multiline
   editing, keyboard dismissal, scroll-follow and text selection with the mic
   control present; verify VoiceOver activation and localized status text.
3. On a separately authorized test device with a test-only conversation, test
   fresh and previously denied speech/microphone permissions, Settings recovery,
   restricted authorization, offline/on-device availability and each display
   language. Confirm the prompt interruption requires a new press. Verify
   short press, held speech, slide away and back, slide cancel, no speech,
   60-second cap, timeout, final text merged after editing, and no automatic send.
4. During listening and finishing, switch conversations, open the drawer and
   attachment sheet, send a typed draft, leave the page, background the app,
   and interrupt the gesture; verify capture stops and no stale text appears.
5. With consent and local fixtures, test WKWebView audio before/during/after
   voice input, a separate audio app, audio routes including wired/Bluetooth,
   phone/system interruptions, route removal and media services reset. Record
   audible output, mic indicators, errors, route/category and post-capture behavior.
   Check whether the shared session remaining active has consequences. Do not
   infer universal WebKit or audio safety from one setup.

No iOS SDK build, simulator UI run, microphone recording, real account or
physical-device test was performed in this worktree's development environment.
