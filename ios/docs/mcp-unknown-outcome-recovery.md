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
Before unlinking the main pending marker, the host creates a second hard link to
the same version and syncs the directory. Either path blocks another turn. If
the first unlink or its subsequent sync fails, the backup remains reviewable
across process exit without attempting a compensating write. Both names must
refer to the same valid generation. A malformed, unreadable, nonregular or
unavailable marker stays blocked and produces a localized error. A subsequent
explicit review can clear a surviving backup when storage is healthy.

The last marker name must eventually be removed to unblock. If its removal has
an indeterminate sync outcome, the host attempts to recreate and sync the
marker; if that also fails it keeps the cooperative lock and a process-wide
fail-closed state until exit. **If the filesystem cannot persist the last marker
or its restoration, another process after exit may observe no marker and cannot
reconstruct the failed write.** The fault-injection checks demonstrate this
limit; this is not a guarantee against arbitrary I/O failure or sudden power
loss. Deleting app storage, reinstalling, noncooperating writers and other
clients are outside this local guarantee. Directory fsync and hard-link
behavior also require native iOS verification.

A recovery success notice is hidden whenever a marker is observed, and an
observed later block permanently clears the old notice. Cooperating stores in
one process notify one another synchronously; while the chat is visible and
active, it polls at one-second intervals for changes from other processes.
That polling is not an atomic cross-process UI guarantee: a short-lived change
between polls may not be displayed. Actual dispatch still rechecks under the
cooperative lock.

The runner independently coordinates executor entry with cancellation and
reports `executionOutcomeUnknown` when an entered or conservatively reserved
operation has no published result. The runner's reservation callback defaults
to a no-op for other hosts; those hosts must supply their own fence and recovery.
No implementation here proves that a generic executor has stopped all detached
work or that a server can undo or deduplicate an operation.

The local synthetic checks cover cancellation and timeout with a late effect,
confirmation cancellation, reconstructed sessions, manual recovery without
resend, stale confirmations, an independently approved new task, legacy markers,
malformed data, cross-instance notices, a fresh-process backup check, and
injected storage failures before and after removal. A separate-process test
also demonstrates the unrecoverable last-marker failure limitation. These
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
