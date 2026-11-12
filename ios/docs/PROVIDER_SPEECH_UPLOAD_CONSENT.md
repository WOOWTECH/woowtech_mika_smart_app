# Provider speech upload consent: isolated state core

Status: **unconnected candidate, not provider speech functionality**. No UI,
recorder, scene observer, model-settings observer, Keychain adapter, microphone
permission, network service, or production caller is added here. The actor has
no default transport; tests inject a synthetic one. The older `ProviderSpeechClient`
and request/transport APIs remain independently callable and do not enforce this
state machine. Integrating those APIs directly would bypass this candidate.

`SpeechUploadConsentCoordinator` starts inactive. A future host must feed its
actual scene state; leaving the active scene revokes pending reviews, cancels the
in-flight task, discards the actor's recording and settings, and drops later
results. Returning active does not restore them. An explicit cancellation also
revokes and cancels, but keeps the recording for a possible newly confirmed
retry; `discardRecording` clears it. A Swift task or injected transport that
ignores cancellation may retain copies until it returns. Cancellation cannot
retrieve bytes already handed to networking, nor securely erase Swift values.

In the active scene the host publishes a reviewed endpoint, selection,
credential and optional language to the coordinator. Each publication cancels
and revokes previous work and creates a fresh, opaque in-memory credential
version, including identical or ABA publications. The actor privately owns that
credential and a validated, copied WAV snapshot; each new recording gets a new
ID even for identical bytes. A review uses the existing request builder to
present the exact serialized **final request URL**, provider, kind, model,
method, language, credential version, recording ID and WAV byte count. It does
not send. The UI must show the material fields, explain third-party audio
sharing and ask the person to explicitly confirm this specific review. The
`confirm` API is merely a state transition: it cannot establish that any UI
was shown or that a human pressed a button.

A review ID is checked against the actor's one current state; a copied or stale
ID confers no independent authority. Start rebuilds the request from the
actor-owned settings and recording, checks it against the review and consumes
confirmation before scheduling one transport attempt. Duplicate start and
confirmation calls fail. Retry, including after failure or cancellation,
requires another review and confirmation. A settings or recording publication,
scene inactivity or cancellation invalidates the old review; an in-flight
completion is accepted only while its exact attempt is still current. Once a
transport starts, cancellation and a scene change can race with already-sent
bytes. The coordinator never promises to retract those bytes.

The in-memory version is **not** an independently observed Keychain revision.
The host must own all settings and credential mutations through one serialized
authority, atomically publish changes to this coordinator before an upload can
start, and detect/invalidate external or other-window changes. A raw saved URL
cannot prove what the user entered: the host must obtain the original re-entry
required by `reviewNew`/`reviewSaved` and display the resulting final destination.
Separate coordinator instances, the current model-settings repository, scene
notifications, and direct transport calls are not automatically synchronized or
gated by this candidate. No durable credential-version protocol or native UI
has yet been implemented. Exact URL serialization is not DNS pinning or a proof
of how an intermediary interprets a path; transport-specific TLS, redirect,
timeout and data handling remain essential.

Run `bash ios/scripts/check_speech_upload_consent.sh`. Its synthetic transport
never connects to a network and deliberately ignores cancellation until a test
releases it. Checks cover copied/stale/foreign review IDs; exact URL, model,
credential and recording snapshots; changed and ABA settings; invalid recording;
background and cancellation; retries; two concurrent starts; and delayed old
results while a later attempt is in flight. The returned test attempt handle is
awaited so that a late callback has actually finished, not merely waited for a
timeout. These are host Swift checks; iOS build, lifecycle ordering, UI,
accessibility, Keychain change observation and device behavior require native
validation before integration.
