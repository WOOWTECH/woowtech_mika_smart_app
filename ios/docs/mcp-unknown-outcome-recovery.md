# MCP cancellation and uncertain outcomes

The production chat path at `6d74328` obtains an `MCPSession` connection, asks
for the exact proposed tool/resource operation, and invokes the shared
`MCPConversationRunner`. The runner's timeout/cancellation race can return
while an executor is still active. Cancelling the local HTTP task does not
retract a remote request or guarantee that the server has stopped working.
A tool transport failure or an invalid/unusable result can also leave effects
unknown; no automatic retry is safe.

The candidate reserves an exclusive, empty marker in the app's scoped
conversation support directory before the first executor dispatch in a turn.
It syncs the file and directory before allowing the dispatch, and a failed
reservation prevents executor entry. Other `MCPSession` instances using the
same storage check the marker before starting an MCP chat, and a second
reservation cannot acquire it. The marker contains no endpoint, user text,
arguments or result. A successful full turn removes it. Cancellation,
timeout, an executor failure, invalid result or a later failed/denied model
turn leaves it in place, because earlier operations may already have happened.
The existing draft and any already received tool results are retained. A
three-language warning says the result is unknown, the action may still take
effect, and new MCP operations are paused; it does not say the remote action
was reversed. A new conversation, reconnect, changed model or normal app
restart cannot silently retry the operation. Plain chat remains available.
Because the marker deliberately contains no operation identity or arguments,
after a restart the app cannot reconstruct which operation requires checking;
the user must inspect the service's own records. A future recovery design must
address that usability gap without storing credentials or unbounded arguments.

The runner independently serializes dispatch reservation with its cancellation
and timeout race, and reports `executionOutcomeUnknown` if it stops while an
entered or conservatively reserved executor has no published result. A worker
that ignores cancellation can still run after the caller has returned; the
marker remains even when its late result arrives. The API's default reservation
callback is a no-op for other hosts: those hosts must supply their own durable
fence and user-facing recovery. The executor protocol cannot guarantee server
rollback, server-side idempotency, or that an implementation has stopped all
unstructured producer work when it returns.

There is deliberately no automatic marker expiry or UI button to clear this
state. Checking a server too early does not prove an in-flight action cannot
complete later, and a generic MCP server offers no universal transactional
status or idempotency key. This is a conservative availability tradeoff: the
candidate can leave MCP unavailable indefinitely until a separately designed,
explicit recovery procedure establishes safety. Do not erase the marker as a
routine retry. Device storage deletion/reinstall, noncooperating writers, and
other clients are outside the fence. The synced marker is not a claim of
power-loss durability on every filesystem.

`CheckMCPLocalTools.sh` exercises the real runner with synthetic executor
cancellation and timeout, including an effect that occurs only after the
caller returned and a failed reservation that prevents dispatch.
`check_chat_streaming_app.py --focused` exercises the real ChatSession and two
MCPSession objects over one isolated marker, verifies retention and restart-like
reconstruction, and verifies a late fake side effect without retry. These local
checks do not test real service behavior, physical devices, native UI rendering,
or server-side cancellation/idempotency.
