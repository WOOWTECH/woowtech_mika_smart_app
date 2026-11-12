# Attachment tool-session integration: next bounded stage

This worktree does not enable attachment plus MCP or memory. It adds
`AttachmentToolLeasedClient` beside `ChatSession` and exercises it with the
real multi-call MCP runner, the one-shot model adapter and two archive stores.
The adapter takes a synchronous main-actor validation supplied by a future
host and rechecks it before and after acquiring the archive's cooperative
lease. When a store exists, each model call rereads the exact conversation and
quote-source while locked. The lease stays alive until the lifetime-bound model client returns,
even when the MCP runner's cancellation or deadline returns first. It is not
held while waiting for a tool approval. The current tests supply a synthetic
validator, not `ChatSession.validateAttachmentStart`; this is not yet an
end-to-end session integration.

Without a store, the adapter rejects every request by default. It can be
explicitly marked `unarchivedNewConversation` only when both the expected
archived conversation and quote source are absent. This is reserved for a
brand-new conversation with no prior history and no quote. The trusted host
must verify that fact when forming the reviewed binding: the flag does not
prove that omitted sources never existed. An absent store with either source,
or a new-unarchived declaration alongside a store, is rejected before the
client is entered. None of this protects a caller that lies about its inputs or
a writer that does not cooperate with the archive lock.

For a future host, compose the client in this order:

1. Keep the existing explicit selection, import, vision declaration and
   `ChatAttachmentReviewContext`; review the exact destination, history,
   quote source, typed draft, settings and learning snapshots. Extend that
   review to cover the selected MCP connection, immutable selected catalog,
   enabled memory context, disclosures and later tool approvals.
2. Capture the actual typed draft separately from the composed prompt. Pass
   only that draft to `MemoryToolRun` and `UserProfileToolRequest.prepare`.
   Quotes, attachments, tool results, catalogs and model output never become
   the user's words. Keep the existing exact-change approval and receipts.
3. Only after explicit confirmation, take the attachment once. Wrap the
   lifetime-bound HTTP completion client in `AttachmentToolLeasedClient`,
   whose validation captures the active request ID and exact reviewed session
   binding, and wrap that client in `OneShotAttachmentModelClient`. Give the
   resulting client to `UserProfileChatFlow` or `MCPConversationRunner`. The
   first request carries the attachment; a later request has only the
   transcript and cannot replay the attachment object. A failure or uncertain
   receipt consumes it; preserve the draft and require reselection or removal.
4. The archive lease closes the cooperating archive-store read/start gap, but
   the validation closure by itself does not freeze mutable settings or MCP
   state after the main-actor hop and before a deferred transport starts. Do
   not enable this path until the host and actual transport have an explicit
   start fence for cancellation and other reviewed changes. Treat a prior
   successful model call as a disclosure even if a later action fails.
5. Revalidate the same applicable binding immediately after each approval and
   before any remote dispatch or synchronous local commit. Reacquire and
   retain the archive lease through the actual producer, including cancellation
   and timeout. The existing model-only adapter does **not** guard the MCP
   executor or local commits. The MCP runner can return before its worker;
   a general `MCPConversationExecuting` implementation currently provides no
   lifetime-bound dispatch contract. Add and test such a contract instead of
   assuming a returned consumer means the executor has stopped. A noncooperating
   producer can keep a lease indefinitely; a writer bypassing the vault lock
   is outside this guarantee.
6. An approved memory/profile mutation changes the reviewed learning state.
   Track only the exact host-committed revision and receipt as an allowed
   transition, with no suspension between the final lease/revision check and
   commit. Stop on all other changes; preserve prior committed receipts and
   avoid repeating an operation after cancellation or uncertain dispatch.
7. MCP confirmation must display the full immutable operation and arguments,
   a user-recognizable destination, and a warning that arguments can contain
   information derived from the attachment. `MCPApprovalView` already shows
   operation and arguments, but the complete configured MCP URL is treated as
   a credential, including its host and path. A future implementation needs a
   user-recognizable connection label bound to an opaque connection revision;
   neither a server-provided name nor exposing the webhook credential proves
   the destination. Show the disclosure and action in Traditional Chinese,
   Simplified Chinese and English, with accessible labels and exact-argument
   review. Revalidate the connection and selected catalog after approval.
   `MCPSession.onConnectionChange` is a single callback: do not replace another
   owner's observer and assume invalidation still works. Introduce an
   independently checked connection/selection revision or safely multiplex
   observation before wiring this into chat.
8. Add session-level tests for stale quote/conversation and settings before
   each model or tool start, explicit model and MCP connection switches,
   positive and negative typed-utterance evidence, failed selection and draft
   preservation, denied approvals, memory commits followed by failures,
   concurrent stores, cancellation and timeout at each boundary, and actual
   UI review in all three languages. Test any eventual streaming adapter with
   a producer-retained lease and no attachment-bearing fallback request.

The model may echo file content in a tool proposal, result, or final answer;
the one-shot wrapper prevents implicit retransmission of the attachment object,
not every disclosure of derived information. A selected action still requires
independent explicit approval. An answer remains subject to the existing
user-authorized archive and history behavior.

The local test fixtures use synthetic files and clients. They do not contact a
real service, confirm provider receipt, execute a real device picker, or build
or exercise the native iOS UI.
