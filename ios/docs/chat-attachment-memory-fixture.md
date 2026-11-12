# Attachment and memory session fixture

This candidate retains the production block on combining a general attachment
with memory or MCP. `ATTACHMENT_TOOL_SESSION_FIXTURE` is supplied only to the
offline Debug harness; it is absent from normal Debug/Release builds and the
fixture entry point accepts only a separately compiled synthetic-client marker.
There is no user-facing flag or real-service path.

The fixture runs the actual selected-file presenter, explicit confirmation,
ChatSession binding and cancellation, one-shot attachment client, archive
lease, structured profile/memory flow, memory review and encrypted test store.
It sends only the captured draft to memory authorization. The host can fence a
reviewed local commit by rereading the conversation under the cooperative
archive lease after the user approves and before the synchronous write. A
changed archive stops that commit. A declined or ungrounded proposal does not
write. A successful synthetic mutation currently invalidates the original
reviewed learning snapshot; the next model call stops, and the draft, receipt
and explicit reselection requirement remain. This is intentional fail-closed
fixture behavior, not a completed memory+attachment feature. This fixture does
not install a ChatSession deadline; runner timeout and producer lease coverage
remain separate tests, and a combined session timeout still needs validation.

## Remaining release blockers

* The model start validation crosses an async/actor boundary before transport
  can start. A model/connection/settings change in that interval requires a
  transport-start fence. Captured request values alone do not prove the user
  still wants transmission at the eventual start. The fixture also does not
  revalidate the full destination and source before publishing a final answer;
  production wiring needs that check and explicit archive-conflict handling.
* `LearningStore.persist` and other learning-vault writers do not all acquire
  the archive's cooperative lease or reread a shared snapshot. Local generation
  and revision checks do not detect an independent LearningStore instance
  writing the same vault. Add cross-store learning transactions and verify the
  full durable snapshot before context disclosure and each local commit; do
  not assume the conversation archive lease covers a different vault.
* `contextMessages(for:)` may persist memory use counts before it returns. A
  reviewed attachment run needs a side-effect-free preview or an explicitly
  bounded, versioned use-count transition; otherwise a relevant memory can
  change the binding while the host prepares its own request.
* Permit continuation after an approved memory/profile commit only by advancing
  an exact expected revision using the actual committed receipt. Preserve the
  receipt and distinguish an already-saved change from an unsent action on any
  later error, timeout or cancellation. Never feed file or answer content into
  automatic extraction, and never replay the attachment.
* MCP needs an explicit user-recognizable destination bound to a connection and
  catalog revision, full immutable action/argument review, and a disclosure
  that arguments may contain file-derived information. The endpoint is a
  credential; do not expose it as a label. Recheck the archive, session and
  connection after approval and immediately before every dispatch. A generic
  MCP executor has no producer-lifetime contract, so consumer cancellation
  alone cannot release a lease safely. No MCP attachment path is enabled here.
* The existing memory and profile permission views need localized fixed labels
  for Traditional Chinese, Simplified Chinese and English. Their displayed
  content, accessibility and language switching need native iOS verification;
  test model/provider delivery, real MCP behavior,
  cancellation and system picker lifecycle only in the appropriate isolated
  environment. The fixture never establishes those results.

No archive lock can constrain a process that bypasses its protocol, and a
noncooperative client may keep a lease until it actually returns. A model may
echo file-derived information in its answer or later tool arguments even though
the attachment object itself is not automatically resent.
