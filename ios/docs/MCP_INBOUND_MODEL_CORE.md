# Inbound MCP model-task core: offline stage

Base: iOS `f463cf268265ae3252f5f37fa14503dd7e6d0535`; Android source is the
same monorepo revision. This stage is an isolated format/review core, not a
server or feature available in the app.

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
`tools/call` for `mika_run_task`. Input is capped at 32 KiB, 16 nested levels
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

There is **no listener, token generation/storage, network authentication,
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
