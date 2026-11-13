# Delayed model connection UI candidate

These three native XCTest methods exercise 測試並儲存 and 重新測試 in
Settings › 模型 through the actual UI, with an opt-in, DEBUG-only fixture and
an isolated UUID defaults and Keychain service. The fixture accepts only the
fixed synthetic URL, model and key used by these tests; it never performs
network I/O. It records only counts. The fixture is simulator-only and rejects
conflicting Live or UI fixture flags.

The tests start a test from the add-provider form (or 重新測試 on a provider's
page), perform a change, confirm cancellation was delivered, explicitly release
the noncooperative fixture, then wait for the actual connection worker to
settle before asserting that the old result neither asked for the AI-sharing
consent nor saved or marked a provider. The test-only deadline is 120 seconds
for native UI gestures; normal product requests retain 20 seconds.

- `testDelayedConnectionEditsCannotPublishOldResult`: edits the URL, model and
  key separately while a test runs. Afterwards a released test passes, the
  consent is agreed to, and the saved provider answers the synthetic chat
  client.
- `testDelayedConnectionCancelSaveAndLeaveCannotPublishOldResult`: leaves the
  page while a test runs; saves the provider without a test, adds it again and
  cancels that form while its test runs, so it stays untested; then 重新測試
  on the provider's page passes with the saved address, model and key.
- `testDelayedConnectionBackgroundCannotPublishOldResult`: backgrounds and
  foregrounds the simulator app, releases the stale result, then tests again
  and saves after the consent.

On the MacBook, use a disposable iOS simulator and the Debug scheme; for
example, after `xcodegen generate`, set `SIMULATOR_ID` to that simulator's UUID:

```sh
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:WoowAssistantUITests/WoowAssistantUITests/testDelayedConnectionEditsCannotPublishOldResult \
  -only-testing:WoowAssistantUITests/WoowAssistantUITests/testDelayedConnectionCancelSaveAndLeaveCannotPublishOldResult \
  -only-testing:WoowAssistantUITests/WoowAssistantUITests/testDelayedConnectionBackgroundCannotPublishOldResult test
```

Run `python3 scripts/check_model_connection_delayed_fixture.py` for the
non-native fixture, cancellation and DEBUG/Release exclusion checks. Neither
the native nor non-native tests contact a model provider. Native compilation,
accessibility timing and simulator execution still require Xcode.
