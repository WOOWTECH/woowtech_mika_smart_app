# MCP model-call limit: native UI test candidate

Base: `8a73e4d621b89be3fa665cd95568d641b7c8ea5b`; this branch adds UI
tests, not a product or limit change. No UI test has been run in this host.

The existing `SelfConfigurationView` uses a SwiftUI Form Picker and the
`AppLanguageUITests`/`SelfConfigurationUITests` use the existing
`revealLearningElement` and `navigateMikaSection` helpers to reach its
accessibility element. Prior repository evidence for the *language* Picker
records a Button role on three iPhone runtimes (iOS 17.0.1, 18.5 and 26.2):
[three-platform evidence](evidence/ui-language-ae7a1e2-three-platforms.json).
That observation is not an observation of the new MCP Picker or an iPad AX
tree. No iPad AX evidence for this Picker was found in the repository; this
host has neither an iOS SDK nor `simctl`. Its actual role and menu presentation
on each iPhone/iPad remain to be measured natively.

The tests use the existing navigation and bounded visibility helpers, prefer a
Button by the product's exact picker identifier, and otherwise inspect the
identified element. An actual picker wheel is adjusted if observed; otherwise
the test taps an exact labelled actionable button, menu item, cell or static
text. No coordinate fallback, injected preference value, skipped assertion or
fake selection is used. If the role, option or selected value is not exposed,
the test fails with the picker description so a native AX capture can inform a
specific correction. Successful runs also attach the observed picker and
selected option or wheel type to the XCTest result. The accepted role paths are test hypotheses until run.

`testMCPModelCallLimitPersistsThroughSettingsAndRelaunch` opens the real
Settings destination, checks the default 12 and local/remote explanation,
selects 3, reads the changed value on both detail and returned Settings row,
terminates the process, relaunches without reset using the same fresh UUID,
and reads 3 again. `testMCPModelCallLimitExplanationsInThreeLanguages` opens
separate fresh isolated suites for Traditional Chinese, Simplified Chinese and
English, and checks that approval/6 limit are attributed to remote MCP tools and
resources, with distinct local-search and local-change rules. The test does
not make model or MCP requests.

Run both methods on the desired iPhone and iPad simulator destinations using the
existing `WoowAssistant` scheme and `WoowAssistantUITests` target, for example:

```
xcodebuild test -project WoowAssistant.xcodeproj -scheme WoowAssistant \\
  -destination 'platform=iOS Simulator,name=<device>' \\
  -only-testing:WoowAssistantUITests/AppLanguageUITests/testMCPModelCallLimitPersistsThroughSettingsAndRelaunch \\
  -only-testing:WoowAssistantUITests/AppLanguageUITests/testMCPModelCallLimitExplanationsInThreeLanguages
```

Generate the Xcode project according to the repository's usual instructions
first. Record the actual device, OS, AX picker type and `.xcresult` for each
run. Do not mark iPad or iPhone accepted until those exact runs pass.
