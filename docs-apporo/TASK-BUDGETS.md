# Bounded task execution (Apporo and WOOWTECH)

This change is shared in `core` and `app/src/main`; neither brand overrides it.
Both production TaskRun entry points (main and child) explicitly supply TaskBudget.
The embeddable core keeps a nullable policy for legacy/test callers; new budget tests
opt into the same policy rather than advancing old unlimited-wait fixtures to a deadline.
It responds to prolonged successful rereads, accumulating conversation usage, and
model calls that remained in retry/streaming for too long.

## Behavior

- A task has a default 15-minute elapsed allowance, including user waits. The last
  30 seconds are reserved for a single tool-free handoff. Cancellation cleanup and
  already dispatched non-cancellable operations may extend wall-clock completion;
  a timeout is never proof that an external operation did not take effect.
- The work allowance is 2,000,000 input plus output tokens (cached input included).
  Exploration stops at 1,980,000, reserving 20,000 for delivery. The threshold is
  checked between calls/actions, not a provider-enforced billing cap. In-flight
  requests and concurrently running child calls can exceed it; missing usage is
  estimated, and failed requests may have unknown provider charges.
- Metered calls share an in-memory ledger with child coroutines, including calls
  outside the main loop. Unmetered scripted models have a local fallback counter.
- A logical main-model request has a 180-second total deadline, including retry
  delays, streaming and light-to-main fallback. Parent cancellation is preserved.
- Successful identical reads warn after three duplicates and stop research after
  six. The detector stores at most 16 pairs of hashed arguments/results. It covers
  native file reads/search and a conservative whitelist of simple read commands,
  including read-only `;` / `&&` chains. Changed content, unknown commands, writes,
  truncated output and identified polling paths do not count. This is not general
  semantic proof of progress, and arbitrary implicit polling is still ambiguous.
- Explicit standalone requests such as `先給我目前結果`,
  `你直接給我目前現況的網頁`, and `give me the results so far` enter delivery mode.
  A pending question or approval is withdrawn, never answered/approved. Initial
  delivery requests are checked before route replay. General paraphrases still
  depend on model interpretation; quoted/negated instructions are not triggers.
- Delivery cannot execute tools or replay a proposed action. It describes available
  results and uncertainty. A failed/timed-out summary gives a deterministic receipt
  and points to timeline records; existing files are retained. Partial handoffs
  remain incomplete outcomes, with selectable Markdown and copy in the UI.

The step-limit setting still limits step count only. Its explanatory text now
also discloses the elapsed/token allowances. Token totals shown in the chat remain
conversation totals, not a single request's context size or a price estimate.

## Verification design

Core tests use virtual time and scripted models for stalled requests/streams,
retry exhaustion, cancellations, missing usage, child accounting, long conversations,
repeated reads, changed results, delivery requests and unanswered approvals.
`RunMetrics` assertions separate model time, tool time, calls and token totals.

The opt-in `-PbrandBudgetTests` build enables branded Android instrumentation without
changing normal release builds. `task-budget-device.yml` installs both branded
APKs on a disposable API 36 x86_64 emulator and runs only `TaskBudgetDeviceTest`.
This is deterministic-model testing on the real Android runtime, not live gateway,
arm64 sandbox, physical-device audio, or full visual acceptance. Receipts include
commit, APK hashes, instrumentation output and emulator cleanup.

Validation results are recorded in the PR/CI; this document describes the contract,
not a claim that an unfinished run passed. No release is performed by this workflow.
