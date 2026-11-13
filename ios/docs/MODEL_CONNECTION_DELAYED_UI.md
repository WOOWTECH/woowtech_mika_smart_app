# Delayed model connection UI candidate

These three native XCTest methods exercise the saved-model settings through the
actual UI, with an opt-in, DEBUG-only fixture and an isolated UUID defaults and
Keychain service. The fixture accepts only the fixed synthetic URL, model and
key used by these tests; it never performs network I/O. It records only counts.
The fixture is simulator-only and rejects conflicting Live or UI fixture flags.

The tests observe a pending request, perform the change, confirm cancellation
was delivered, explicitly release the noncooperative fixture, then wait for
the actual connection worker to settle before asserting the old result did not
change the UI. The last successful fixture request checks that the original
synthetic saved URL, model and key remain usable. The test-only deadline is 120
seconds for native UI gestures; normal product requests retain 20 seconds.

- `testDelayedConnectionEditsCannotPublishOldResult`: edits URL, model and key
  separately, relaunches against the same isolated saved settings, then tests
  and uses those settings with the existing synthetic chat client.
- `testDelayedConnectionCancelSaveAndLeaveCannotPublishOldResult`: cancel,
  save and leave the detail view while a request is pending, with a fresh
  request and synthetic chat afterwards.
- `testDelayedConnectionBackgroundCannotPublishOldResult`: backgrounds and
  foregrounds the simulator app, releases the stale result and tests again.

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
