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
  implemented by this offline core.
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
`tools/call` for `mika_run_task`, `mika_task_status`, `mika_list_tasks`, and
`mika_cancel_task`. Input is capped at 32 KiB, 16 nested levels
and 512 values; duplicate object keys, malformed UTF-8, malformed JSON,
unsupported methods, extra tool arguments, invalid IDs and oversized goals are
rejected. It validates only the shape of an optional conversation identifier;
that is not proof that a client owns or may access a conversation. This subset
is intentionally stricter than Android in some cases (unknown fields, invalid
version and missing arguments); it is not a complete MCP implementation.
There is no response serializer, advertised tool list, HTTP parsing, header
validation or 2026-07-28 protocol support.

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
`mika_list_tasks`, and `mika_cancel_task` for synthetic **queued records**.
Run requires a canonical `request_id`, a current connection and explicit local
review of the immutable task and destination/context revisions. Duplicate IDs
on the same live connection and same binding return the existing record;
different content or a different connection conflicts. Status/list/cancel
are restricted to the creating connection. Cancel only changes an inert queued
record; there is no dispatch or claim that an already sent request is undone.
No device, other-app, file, browser, network or memory tools are assembled.

Android's `mika_wait_task`, `mika_answer`, `mika_steer_task`, real model/task
execution, result/response serialization, remote conversation continuation,
durable request receipts and cross-restart idempotency are not implemented.
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
