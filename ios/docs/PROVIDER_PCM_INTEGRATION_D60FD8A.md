# Provider PCM integration on d60fd8a

This integration takes the provider core and PCM source through `7cbc517`,
including its observer-before-engine regression. It keeps the provider factory
and settings/transport seam disconnected from the composer and settings UI.
The existing Apple on-device speech remains the active chat driver; its shared
driver interface has a live permission/cancellation check. Model settings now
also include the isolated provider dispatch revision and raw-port validation.
These changes are not a claim of Android speech parity or provider availability.

The non-Live GitHub full preflight and focused simulator workflow execute all
four provider standalone gates. Their logs and source commit are kept in the
existing workflow evidence artifacts. The Mac portable checks use synthetic
PCM, isolated defaults, fixture credentials and fake transports. They do not
exercise an Apple audio engine or a real provider.

## MacBook iOS simulator selectors

Use a full Xcode installation, XcodeGen and an available **iPhone simulator**.
After checking out the exact integration commit, choose its simulator UDID
from `xcrun simctl list devices available`, then run from `ios`:

```sh
xcodegen generate
mkdir -p build
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -resultBundlePath build/provider-pcm-simulator.xcresult \
  -only-testing:AssistantSkillsTests/ProviderPCMNativeAdapterTests \
  -only-testing:WoowAssistantUITests/ChatVoiceUITests test
```

Inspect the xcresult and confirm all five `ProviderPCMNativeAdapterTests` and
five `ChatVoiceUITests` ran without skips. The former creates synthetic
AVAudioPCMBuffer values and posts synthetic notifications; it does not create
an engine or request microphone access. The latter uses a Debug fake speech
driver, not Apple recognition. For broader regression, run the existing
non-Live `core` and `ui-startup` scopes on the same exact commit. Simulator
results do not verify real microphone permission, physical routes, audio quality,
CPU/power or service interoperability.

The source cannot observe events before registration or notifications the OS
never delivers. A delivered notification racing the last check and engine
start closes the collector and triggers cleanup but may permit a brief engine
start. The entry must remain closed pending native validation and resolution of
the documented lifecycle and production-service limitations.
