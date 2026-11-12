# MCP cancellation and recovery

The production chat path at `6d74328` asks for each exact MCP operation before
entering the executor. Cancellation or a timeout can return to the caller
while an executor or server continues work. A sent operation may already have
happened or may take effect later; an error does not prove rollback.

The host reserves a durable marker before executor entry. An unfinished turn
keeps that marker across a normal restart and blocks another MCP turn; it does
not automatically resend an operation or the retained draft. The marker holds
only a random version UUID, not an endpoint, operation, arguments or result.
Legacy empty `f62849a` markers are upgraded under the same lock before review.
A completed turn removes its own matching marker. Plain chat remains available.

A user can choose “Unblock MCP after checking” and sees one confirmation that
the outcome is unknown, the operation may still happen later, and sending the
same request again may duplicate it. Confirming unblocks future use but sends
nothing. Cancelling leaves the block and draft. The user must decide whether a
later request is appropriate; the app cannot establish server-side idempotency
or undo an already sent operation. Because the marker contains no operation
details, after a restart the user may need to inspect the service's records.

Review and acknowledgement are bound to the same random marker version. A
cooperative cross-store lock serializes marker creation, review, acknowledgement
and successful-turn cleanup; a stale confirmation cannot clear a newer marker.
The lock is advisory and does not constrain noncooperating writers. A malformed,
unreadable, nonregular or unavailable marker stays blocked and produces a
localized error. Storage failures do not report successful recovery; if a
failure occurs after removal, the host tries to restore the original marker and
keeps a process-wide fail-closed state and retains the cooperative lock until
process exit if restoration fails. Cooperating stores treat the held lock as a
block. No software-only fallback can guarantee durable state across process
exit if the filesystem cannot persist either removal or restoration; storage
repair and independent review are then needed.
Deleting app storage, reinstalling, other clients and filesystem behavior after
sudden power loss are outside this local guarantee.

The runner independently coordinates executor entry with cancellation and
reports `executionOutcomeUnknown` when an entered or conservatively reserved
operation has no published result. The runner's reservation callback defaults
to a no-op for other hosts; those hosts must supply their own fence and recovery.
No implementation here proves that a generic executor has stopped all detached
work or that a server can undo or deduplicate an operation.

The local synthetic checks cover cancellation and timeout with a late effect,
confirmation cancellation, reconstructed sessions, manual recovery without
resend, stale confirmations, an independently approved new task, legacy markers,
malformed data and injected storage failures before and after removal. These
checks do not verify native iOS UI/accessibility, real services, server-side
cancellation or idempotency.

## Synthetic native UI regression

`MCPRecoveryUITests` launches the Debug app with an explicit
`-UITestMCPRecovery` flag, a fresh UUID namespace, the existing in-process
model fixture and an in-process MCP fixture. The fixture publishes only an
executor-entry count and delays its reply; no endpoint or tool arguments are
shown by this probe. Invalid recovery-fixture flags fail closed, and Release
excludes the fixture. The tests wait until the fake executor has entered,
cancel, inspect the unknown-outcome warning, dismiss review, and explicitly
unblock. They assert the current draft remains and is not automatically sent.
A separate relaunch test checks that the block persists, can be dismissed and
then cleared, and starts no fake call on relaunch. It does not assert that an
unsent in-memory draft survives process termination.

On a Mac with Xcode, XcodeGen and an installed iOS Simulator, from `ios/`:

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:WoowAssistantUITests/MCPRecoveryUITests test
```

Select a simulator UUID in `SIMULATOR_ID`. These are synthetic tests, not a
real MCP or model service test. This candidate has not yet been built or run
with the iOS SDK; SwiftUI accessibility and simulator behavior remain to be
verified there.
