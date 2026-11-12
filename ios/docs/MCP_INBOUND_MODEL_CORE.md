# Inbound MCP model-task core: offline stage

Base: iOS `f463cf268265ae3252f5f37fa14503dd7e6d0535`; Android source is the
same monorepo revision. This stage is an isolated access, format, review and
inert task core, not a server or feature available in the app.

## Android and iOS evidence

- Android `core/.../remote/RemoteAccess.kt` rejects Origin-bearing requests,
  rate-limits failed authentication, requires a bearer token (including a
  loopback-only token), and classifies private addresses. `McpSettings.kt`
  defaults network access off and stores the token encrypted; `McpModes.kt`
  distinguishes loopback and private networks. None of those protections are
  connected to an actual listener by this offline core.
- Android `core/.../mcp/McpRpc.kt` handles `/mcp` POST JSON-RPC with legacy
  initialize, tools/list and tools/call, plus a separate newer metadata/header
  protocol. `McpTaskTools.kt` exposes run/status/wait/answer/steer/cancel/list
  and can expose device tools. `RemoteTaskService.kt` bounds a trimmed goal at
  4,000 UTF-16 code units and accepts a canonical lowercase UUID request_id.
  The Android device/app tools are explicitly out of scope here.
- iOS `Sources/AssistantMCP/MCPClient.swift` is an outbound client, not an
  inbound server. `ContentView.swift` and `MCPToolsView.swift` cancel or
  disconnect MCP when the scene is no longer active. This stage changes none
  of those flows.
- Apple documents that apps can be suspended after entering the background:
  <https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence>.
  TCP listening/accepting alone does not require local-network privilege; other
  operations such as outgoing local connections or Bonjour may:
  <https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>.
  There is no assertion that a listener would run continuously in background.

## Implemented boundary

`MCPInboundFormat` reads only bounded JSON-RPC 2.0 bodies: legacy initialize
with one of three versions, initialized notification, ping, tools/list and
`tools/call` for `mika_run_task`, `mika_task_status`, `mika_list_tasks`,
`mika_cancel_task`, `mika_wait_task`, `mika_answer`, and `mika_steer_task`. Input is capped at 32 KiB, 16 nested levels
and 512 values; duplicate object keys, malformed UTF-8, malformed JSON,
unsupported methods, extra tool arguments, invalid IDs and oversized goals are
rejected. It validates only the shape of an optional conversation identifier;
that is not proof that a client owns or may access a conversation. This subset
is intentionally stricter than Android in some cases (unknown fields, invalid
version and missing arguments); it is not a complete MCP implementation.
The parser itself does not parse HTTP or support the 2026-07-28 protocol; the
separate access core checks already-parsed header values. A separate offline
legacy response encoder is described below.

`MCPInboundReviewState` holds one immutable parsed task in memory and returns
its exact task and binding in a review snapshot. It starts
closed, requires an explicit local enable and active foreground state, and
binds a local review to connection, model-destination and context revision
handles. The host must issue a fresh revision for every relevant change, even
when settings later return to an earlier value. Replacing, discarding, disabling,
leaving active state, or a mismatch
invalidates the old ticket/grant. An approved grant is consumed at most once
within the actor. Neither remote goal text nor a request_id is user approval.
The host must display the exact task and destination before invoking the local
approval method. UUID handles are host-provided revision markers, not peer
identity, authentication, or proof of data ownership.

There is **no listener, token generation/storage, real network authentication,
client pairing, UI, model dispatch, persistence, automatic retry, or device
operation** in this stage. In-memory grant consumption is not durable request
idempotency: repeating the same request_id after consume or restart still needs
an independently designed durable receipt and conflict policy. The actor does
not synchronize unrelated stores, network authorization, model configuration
changes or execution; a future host must atomically bind/revalidate those
boundaries and handle cancellation or unknown outcomes without duplicate work.
An app relaunch creates closed state; no background availability is promised.

Before any network integration, separately design and test secure transport,
peer identity, token/keychain rotation, origin/host and duplicate-header rules,
address/interface policy, request/body/time limits, replay and rate limits,
foreground lifecycle, local consent and visible destination, task ownership,
concurrent cross-store changes, cancellation/unknown outcomes, restrictions on
model tool/memory side effects, and safe response disclosure. Decide explicitly whether and how local-network privacy
applies to the actual transport; never treat it as client authentication.

## Access and inert task subset (candidate based on 05abecf)

`MCPInboundAccessTasks` is a separate in-memory actor. It does not call the
older `MCPInboundReviewState`: it combines request checks and its own review
state in one actor so a connection revocation cannot race a locally approved
queued record inside this core. The future host must use one authoritative
actor rather than treating the older independent review actor as authentication.

The state defaults disabled and requires an active foreground plus explicit
local enable. The host supplies raw IPv4/IPv6 socket peer bytes and a
43-character base64url token; it must securely generate and manage that token.
The actor keeps an HMAC verification value rather than the token itself. It
accepts only loopback, or the selected Android-like private ranges; IPv4-mapped
IPv6 is canonicalized. It rejects Origin-bearing requests, duplicate bearer
headers, malformed headers, wrong tokens and public peers. Five failed token
checks cause a per-peer 60-second cooldown, including for the correct token;
state is bounded to 256 peers and fails closed when full. Every request
rechecks the token, peer and connection. A connection expires after five minutes.
Closing, background/inactive, local disable or token rotation invalidates
connections and reviews; returning active requires the user to enable again.
No headers, token values, task contents or endpoint data are logged here.

This code assumes the host passes the actual socket peer, unambiguous bounded
headers, a monotonic clock, and locally trusted calls to enable and approve.
It has no socket, HTTP parser, Host validation, TLS, token/keychain storage,
network identity or mechanism to authenticate these host inputs. The HMAC
comparison uses CryptoKit's verification API; no independent timing audit is
claimed. In-memory rate limits and connection state reset at process exit.
A future network adapter must not infer peer identity from forwarding headers;
interface binding, IPv6 link-local scope, DNS rebinding, TLS/confidentiality,
HTTP framing, limits, local-network policy and authentication still need
implementation and native security review.

The parser and actor cover `mika_run_task`, `mika_task_status`,
`mika_list_tasks`, `mika_cancel_task`, `mika_wait_task`, `mika_answer`, and
`mika_steer_task` for **in-memory records**.
Run accepts Android’s original `{goal}` format, with optional canonical `request_id`,
a current connection and explicit local review of the immutable task and
destination/context revisions. Without an ID each approved submission receives a
new server ID; repeated submissions are indistinguishable and require fresh review. Duplicate IDs
on the same live connection and same binding return the existing record;
different content or a different connection conflicts. Status/list/cancel
are restricted to the creating connection. Cancel changes only the in-memory
record; there is no dispatch or claim that an already sent request is undone.
No device, other-app, file, browser, network or memory tools are assembled.

Actual model/task execution, durable request receipts and cross-restart
idempotency are not implemented. Limited in-memory continuation and response
formatting are described below.
The Android device tools are deliberately excluded. Record state disappears on
connection closure, disable, token rotation, background or process exit; a
subsequent submission requires a fresh connection and local review, and there
is no durable protection against duplicate remote operations. Natural-language
text is untrusted and cannot authorize tools or override these limits. A future
model-only execution adapter must prevent device/other-app capabilities and
independently handle model-destination changes, cancellation, result uncertainty
and persistence before exposing this over a network.

The actor is not connected to the UI, app lifecycle, network transport or
model settings. Native iOS build, concurrency behavior, Keychain, UI approval,
local-network behavior and background behavior remain unverified. No claim of
continuous background availability or complete Android parity is made.


## Waiting, answers, and steering

Android waits for a state change or terminal status, with a default 30 seconds
and maximum 50; a timeout does not cancel the task. This actor provides the
same bounds with a maximum of 16 simultaneous waits and polls every 250 ms
while scheduled. A wait authenticates its peer and bearer at entry; after each
suspension it rechecks the same connection, revocation and peer lockout.
Rotation and inactivity revoke the session. It does not replay authentication
on each internal poll, because doing so could reset an attacker's failure count.
A cancelled wait has no task side effect. Cancellation and timeout depend on a
cooperative sleeper, advancing monotonic clock and the process being scheduled;
these are not guarantees while iOS suspends an app.

Android accepts `mika_answer(task_id, text)` while a question is open, and
`mika_steer_task(task_id, text)` while running; neither authorizes a protected
local action. Both original argument formats are accepted here. This candidate
also accepts optional canonical `question_id`/`request_id` for answer and
optional `request_id` for steer as **iOS-only extensions**, not Android schema.
Without a client ID an answer retry while running is rejected, but an identical
delayed retry can answer a later open question; repeated steering submissions
are separately queued. No deduplication or exactly-once promise applies to these
original Android requests. Text is trimmed and limited to 2,000 UTF-16 units for
answers and 4,000 for steering.

The host-only state callbacks model running, a specific question, local
approval, finished and cancellation; they execute nothing. Remote answers are
accepted only for the current question and cannot resolve local approval.
Steers are accepted only while running. Reusing an explicitly supplied extension ID with identical contents
returns its existing receipt without adding another item; conflicting reuse is
rejected, including across answer and steer. Each task retains up to 64 answer
receipts and 64 steer receipts without eviction and permits up to 16 pending
steers. Capacity is rejected rather than silently forgetting deduplication.
A host consumes each queued input at most once in this actor. Deduplication
receipts retain the answer or instruction text in process memory until the
record is removed; there is no secure memory-erasure guarantee. A receipt means
only that text was queued, not that any model used it or that an action was
approved. Host-only methods must never be mapped to remote requests.

The actor does not protect work after the host takes an input, across crashes,
restarts, reconnections or other processes. Durable exactly-once semantics,
model-executor lifecycle, effects already dispatched, error/result disclosure,
real local UI approval and transport integration remain unimplemented. The
host must revalidate the actual connection, user approval, destination and
context at the execution boundary; these in-memory revision handles are not a
cross-store lease. Device and other-app controls remain excluded.

## Android tool schema audit and remaining gaps

The Android source of truth is `core/src/main/kotlin/com/wangzan101/mika/core/mcp/McpTaskTools.kt`
and `core/src/main/kotlin/com/wangzan101/mika/core/remote/RemoteTaskService.kt`.
The following is the Android schema, not an advertised iOS tool list:

| Tool | Android required arguments | Android optional arguments |
| --- | --- | --- |
| `mika_run_task` | `goal` | `request_id`, `conversation` |
| `mika_task_status` | `task_id` | — |
| `mika_wait_task` | `task_id` | `timeout_s` (default 30, 1–50) |
| `mika_answer` | `task_id`, `text` | — |
| `mika_steer_task` | `task_id`, `text` | — |
| `mika_cancel_task` | `task_id` | — |
| `mika_list_tasks` | — | `limit` (default 10, 1–50) |

Android schemas disallow extra properties. This parser accepts the original
answer/steer arguments plus the explicitly documented iOS-only optional IDs.
Task identifiers are parsed as nonempty strings; the inert host only creates
UUID records. A future adapter must map other strings to missing, never infer
authorization from them. Android supports persistent `conversation`; this actor only allows the bounded
in-memory subset below. Android's persisted request receipts, actual tool
results and full execution semantics are not implemented. The 32 KiB request and
in-memory capacity limits are additional restrictions. The optional iOS receipt
extensions remain bounded to a live record and have no cross-restart guarantee.

On each monotonic clock check the actor removes every expired connection and
its own review/records before assessing capacity. A stale approval callback
can neither approve nor clear a different current review. No background timer
is promised; cleanup occurs on the next relevant actor operation. The tests
are synthetic and do not start a listener or contact a service.

## Offline conversation and legacy response candidate (base 34808fc)

Android `RemoteTaskService.start` trims `conversation`, treats a blank value
as a new chat and otherwise checks canonical `mcp-<lowercase UUID>` syntax.
`RemoteTaskHub.launch` creates that identifier for a new task and stores receipts
in SQLite; its receipt layer and real task service supply the actual app history.
Unlike Android, this candidate only accepts a conversation issued by the same
live connection, with the same destination and context revision, after its prior
task is terminal and a new local review. Another connection, changed revision,
unknown ID, concurrent task or revoked state is rejected. It does not claim the
identifier alone proves ownership. Android's receipt layer checks identifier
shape and does not provide this candidate's same-connection restriction.

For the strictly bounded synthetic subset, a local host can explicitly attest
that a completed task consisted of precisely the single input goal and final
answer; only then can its retained goal/answer pair be continued. `reviewConversation`
provides the exact retained pairs for display before approval, and
`hostConversation` exposes the same pairs only to the corresponding live host
lease. The actor will not allow continuation after questions, steers, local
approval, cancellation after start, or a completion without that explicit
attestation, because this representation cannot faithfully reconstruct those
contexts. A host-supplied Boolean is not proof: a future real executor must
independently establish that no system/tool/other messages were omitted and
atomically revalidate connection, review, actual data and destination. Up to
20 pairs and 64 KiB total UTF-8 are held in memory, with a 32 KiB final-answer
limit; an oversized completion is rejected without committing it. The host may
finish without retained context or cancel. Queued cancellation has no turn to
retain. All state vanishes on connection closure, expiry, disable, rotation,
background/inactive or process exit; no cross-restart continuation, receipt,
replay protection or exactly-once behavior is provided.

`MCPInboundResponses` formats legacy initialize, ping, original seven tools/list
schemas and JSON-RPC tool result envelopes. For success the text content is JSON
for the same `structuredContent` object; errors are `isError` without structured
content. Run/status/wait/list/answer/steer/cancel payloads use Android field
names; tests decode actual JSON and compare both representations. Only
authenticated actor snapshots should be supplied; encoding does not authorize
or revalidate them, and a future transport must address revocation between
snapshot, serialization and send. Returned data can contain goals, questions
and answers; it must not be logged or disclosed to another connection.

Differences from Android: only legacy protocol response helpers are present,
not modern metadata/header negotiation, actual routing, HTTP status mapping or
complete Android error strings/statuses. Queued is represented as `starting`;
running uses synthetic `step: 0` since this core has no executor progress. An
old-style host completion without an answer has no `answer` field; protected
local approval uses Android's `waiting_on_phone` status but an iOS-local note.
Steer status is `received` until a cancelled queued input becomes `not_applied`:
host dequeue alone does not prove Android's `joined` state. No failure,
verification metadata, options or device-specific states are fabricated.
Initialization wording and tool descriptions are iOS-specific, while Android's
original argument schemas and annotations are retained. Output is bounded to
256 KiB per encoded JSON document. These helpers neither listen nor execute
models; native iOS, actual networking, settings, UI and background behavior
remain unverified.
