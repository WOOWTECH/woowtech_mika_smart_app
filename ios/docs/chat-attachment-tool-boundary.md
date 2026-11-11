# Attachment, MCP and memory: staged boundary

This candidate is an offline building block. It does not enable attachments
with MCP or memory in `ChatSession`, change the composer, or establish Android
feature parity. The existing refusal and draft preservation remain in place.

## Android evidence and differences

Android `ChatViewModel.sendWithAttachments` imports selected items into the
conversation workspace and appends `/workspace/inbox/…` attachment lines to
the task. `app/.../cap/sandbox/Attachments.kt` describes the persistent copy
and its 200 MB per-file bound. `SandboxGroup` exposes `read_file` to the agent;
the task's model/tool loop can therefore read that file and incorporate results
into later model calls. `AttachmentLines` documents storing those path lines in
the conversation. `UserWords.typed` removes attachment lines and quoted text;
`UserWords.said` also permits a quote of the user's own earlier words. These
are Android's actual sources of evidence, not proof that iOS has the same
storage or authorization semantics. This iOS candidate deliberately retains
the existing stricter current-draft-only authorization and no implicit file
archive or replay.

## Implemented boundary

`OneShotAttachmentModelClient` adapts an opt-in lifetime-bound completion
client to the existing text-oriented MCP and memory runners. It validates the
exact reviewed message sequence, endpoint, model, token limit, vision
declaration and credential on every call; messages supplied by the runner must
not already carry an attachment. It consumes the selected attachment before
the first asynchronous call, attaches it to that call's last user message,
and permits only strictly extended, attachment-free subsequent transcripts.
Failure, cancellation, invalid input or a changed binding ends the wrapper;
concurrent calls are rejected. A failed first call is never retried even when
the provider's receipt is unknown. The wrapper intentionally exposes only
`ChatModelClient`: the existing structured-streaming fallback cannot replay
the attachment. This stage therefore has no streaming support for these runs.

The checks exercise the actual MCP runner and `UserProfileChatFlow` with
synthetic clients, and serialize their requests with the actual OpenAI wire
encoder. They check image and text placement, multi-call tool/search flows,
remote approval, current-user memory grounding, context/key/model changes,
unknown vision, failure, cancellation and a deterministic concurrent call.
The test does not send a network request or prove that any provider received,
understood or retained a file. Serialization success is not delivery proof.

The gate does **not** establish that attachment-derived information can never
leave the model: a model can copy file contents into a proposed tool argument,
a response, or later text. MCP approvals must show the complete exact action,
arguments and destination before dispatch, explaining that these may include
file-derived information. Local memory/profile authorization must use the
captured user's actual typed draft, never an attachment, quote, model output,
catalog or tool result; writes still require their existing explicit review.
Neither model instructions nor an attachment label alone enforce authority.

## Before enabling the product path

1. Extend attachment review to describe memory context, the selected MCP
   connection/catalog and the possibility of later model/tool disclosures.
   Bind these and their revisions, together with the existing destination,
   key revision, draft, quote/source, history, archive record, learning and
   vision snapshots. Switching any reviewed input requires a fresh review.
2. Capture the original typed draft separately for the existing `MemoryToolRun`
   and profile validators. Never use a model-generated command as evidence.
   Preserve normal authorized memory changes and their receipts; do not feed
   attachment bytes or model answers to automatic extraction.
3. Integrate the gate at the host's reviewed-send boundary. Revalidate just
   before request start and acquire the cross-store cooperative archive lease
   with the existing record and quote-source checks. A read followed by an
   unguarded async client call is insufficient. The MCP runner can return on
   cancellation before its worker stops; the lease must remain owned by the
   actual producer until it can no longer start transport. The gate alone does
   not manage the lease, observe external state changes, cancel the producer,
   or make uncooperative stores/clients safe.
4. Fence each later request and action against changes to reviewed state;
   explicitly account for revision changes caused by this turn's own approved
   commits and keep their receipts if a later call fails. Avoid holding the
   archive lease indefinitely while waiting for user approval. On a conflict,
   cancellation, provider failure, denied approval or uncertain dispatch,
   stop without automatic retry; preserve draft and report any already
   approved action/commit and the need to reselect the consumed attachment.
5. Add deterministic session-level races for external store changes and
   cancellation at each request/action boundary, exact MCP approval and
   attachment-derived data, memory provenance, UI disclosure in three
   languages, streaming/fallback, and native picker/background lifecycle. A
   separate streaming adapter needs producer-lifetime retention and must never
   fall back by replaying an attachment-bearing request.

Native iOS compilation, picker interaction, real model delivery and real MCP
service behavior have not been tested by this offline fixture.
