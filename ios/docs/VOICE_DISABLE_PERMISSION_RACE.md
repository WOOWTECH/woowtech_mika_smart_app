# Voice setting and delayed permission race

Base: `b71c390b8acad15ce9fa12cff1d3e0738f8c2e30`. A standalone test using the
original controller and a synthetic delayed-permission driver reproduced:

```
REPRO delayed_permission_started_after_off=true result_was_fenced=true
```

A second defaults instance set voice to off before the fake permission callback;
the old controller prevented a result from reaching the draft but had not yet
canceled its driver, so the fake engine still started before the next tick.
This reproduction did not call Apple Speech or capture audio.

The preference model now publishes its observed authorization revision as well
as the displayed choice. The composer retains a binding that cancels an active
session on a changed revision, including system/off/system changes even when
the eventual choice is unchanged. The defaults notification can arrive later;
the production driver therefore also gets a per-session `mayContinue` guard.
That guard checks the current state-machine session and the current preference
revision directly, not a cached notification value. AppleVoiceInputDriver
checks it before permissions, after each permission callback, around audio
session activation, before creating a recognition task, and immediately before
starting the engine. It also checks that the application is active. The driver
cancels its own session and releases the audio lease if a check fails. Existing
scene and user cancellation revoke the state-machine session, so a retained
old permission callback cannot authorize a later session.

Run `bash ios/scripts/check_chat_voice.sh` and
`python3 ios/scripts/test_voice_input.py`. The actual controller, preference
store and binding are exercised with a fake driver that intentionally retains
permission callbacks after cancellation. Tests deliver callbacks before a
notification or tick, between speech and microphone permissions, during fake
audio activation, after an off/on ABA, after simulated background or cancel,
and after a new session starts. They also check normal permission/release and
that a real preference-notification delivery cancels without a tick. The Apple
source checks only assert guard placement; they are not a native runtime test.

**Native validation is outstanding.** This host has no iOS SDK and did not run
Apple permission dialogs, `AVAudioEngine`, a physical microphone or native scene
transitions. The application-level active check and existing per-scene host
cancellation are distinct: in a multi-window app, the platform may still report
the whole application active while an individual scene's change notification
is in transit. UserDefaults is not an interprocess atomic lock; an external
writer racing between the last snapshot check and the engine start is not
proven impossible. Actual iPhone/iPad tests must cover permission dialog return,
backgrounding, multiple scenes, setting changes during both permissions and
lease activation, cancellation, and normal authorized recording. The checks do
not claim secure erasure or change provider-speech behavior.
