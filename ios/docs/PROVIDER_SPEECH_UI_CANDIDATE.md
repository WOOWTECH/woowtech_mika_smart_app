# Speech settings and chat host candidate

This stage builds on `f809a18`. Settings exposes only system on-device speech
and off; the provider selection remains unavailable. These choices use the
same `SpeechChoiceStore` and revision as the candidate router. The chat host
constructs the router with its own `ChatSession` model repository and the same
isolated preferences suite, and defaults to the existing Apple on-device
driver. A stored provider choice is treated as unavailable by the public UI;
no App source calls `selectProvider`. This is not an enabled provider feature.

Each settings action performed through `VoiceChoiceStore` publishes its change
synchronously on MainActor after the store lock is released. All in-process
preference observers refresh, cancel the previous gesture and reload the
router before returning. The permission gate also reads the actual preference
and model revisions directly, so an old permission callback cannot start audio
after an off/on or model edit even before an asynchronous notification or tick.
The chat host cancels and invalidates on disappearance, conversation switch,
explicit cancellation and scene background; a changed saved model on this
session also cancels. Other-window model changes are checked at permission and
tick, not guaranteed to stop an already-running engine synchronously.
Cross-process or direct storage mutation still lacks a synchronous signal.

`check_chat_voice.sh` compiles Debug and Release fake-driver checks including
the real preference store and binding, delayed permissions, model revisions,
background/cancel and stored-provider fail-closed cases. The simulator-only
`WoowAssistantUITests/ChatVoiceUITests/testVoiceSettingOffAndDeviceChoiceControlActualComposer`
uses an isolated namespace and fake driver to check off, restart persistence,
and switching back to system. It does not use Apple Speech or a microphone.
The candidate router's synthetic provider data path remains covered by
`check_configured_provider_speech.sh`, including local URLProtocol interception.

The settings view, actual SwiftUI host and iOS factory have not been built or
tested with an iOS SDK on this host. Provider UI, active lifecycle cancellation
for provider settings, Android's 20-second probe limit, verified persisted
provider authorization, actual microphone behavior and real service protocol
compatibility remain unfinished. A provider must not become selectable until
those constraints have been addressed and verified. Once sent to the network,
audio cannot be recalled.
