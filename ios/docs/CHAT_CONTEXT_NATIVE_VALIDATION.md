# Native validation for chat context fencing

This is a test plan, not a claim that an iOS SDK build, simulator, device, or
multi-window UI run passed. The local synthetic gate compiles the actual App
sources with isolated temporary encrypted files and fake model transport.
The requested order is GitHub iOS simulator gates first, then iPad validation;
do not schedule or report iPad acceptance before the required simulator gates
have passed for the exact candidate commit. Keep their run links and xcresults.

## Hosted iOS test already wired

`AssistantSkillsTests` includes `scripts/CheckProfileChatApp.swift`. Its
`ProfileChatAppIntegrationTests.testChatContextDispatchFences` uses a fresh
UUID for each temporary vault and defaults suite, two actual `LearningStore`
instances, and a controlled in-process model. It exercises ordinary/profile,
MCP, stream cancellation, late replies, and extraction. It is a hosted App
integration test, **not** a two-window UI test. The companion
`testMCPExecutorDispatchFences` covers post-event stale data, tool and resource
dispatch, cancellation, failure, and cooperative lease lifetime. On a Mac with XcodeGen and an
available iOS simulator, from `ios/`:

```sh
make project
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:AssistantSkillsTests/ProfileChatAppIntegrationTests/testChatContextDispatchFences \
  -only-testing:AssistantSkillsTests/ProfileChatAppIntegrationTests/testMCPExecutorDispatchFences test
```

Replace the placeholder with an available simulator UUID and retain the
`.xcresult`, actual runtime version, test counts and any failures or skips.

## Real two-window UI test still to build and run

The source declares a SwiftUI `WindowGroup`, but neither checked-in Info plist
nor `project.yml` explicitly sets `UIApplicationSupportsMultipleScenes`. Check
the generated app's Info.plist and `UIApplication.shared.supportsMultipleScenes`
on the chosen iPad simulator before assuming a second window is available.
Apple's [scene configuration documentation](https://developer.apple.com/documentation/uikit/specifying-the-scenes-your-app-supports)
describes the opt-in and shared-state responsibilities. Do not enable multiple
scenes in a production target solely to make this test pass.

The future UI fixture must use one fresh `-UITestNamespace <UUID>` for both
scenes, `-UITestMode`, fake model transport, and **no** `-UITestResetStorage`.
The reset flag currently runs during each store/repository initialization, so
creating another scene with that flag can reset the same test namespace again.
Use a new UUID for each run; never point at the personal namespace or a real
model. Assert two distinct `UIWindowScene` session identities and independent
`ContentView`/`LearningStore` instances before calling it a cross-window test.

Add a DEBUG-only, UUID-scoped, controllable pre-dispatch gate and scene-specific
accessibility identifiers before running the following cases:

1. In scene A capture a profile-bearing chat; pause before acquiring the model
   dispatch lease. In scene B disable memory, then resume A. Verify zero fake
   model dispatches, no new reply, retained draft and conflict feedback.
2. Pause A's real fake-model producer after lease acquisition but before its
   dispatch signal. Verify B reports busy; cancel A and verify B remains busy
   until the producer actually finishes. Then verify B can disable memory.
3. Repeat with structured streaming and MCP; after a dispatch, change the peer
   and verify a late response is not published. Dispatched bytes cannot be
   recalled, so this case does not claim that no network bytes were sent.
4. Verify the test namespace contains B's change and existing encrypted data;
   exercise both foreground and background/scene closure on supported runtimes.

If the runtime cannot create or identify both scenes, report the case as
blocked or skipped with the reason; a single scene or two stores in one scene
must not be reported as a passed cross-window UI test.
