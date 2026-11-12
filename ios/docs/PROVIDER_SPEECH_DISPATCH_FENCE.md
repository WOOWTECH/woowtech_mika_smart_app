# Provider speech dispatch boundary

This isolated fix is based on `9bb1a244320211624aa5fdf39e30367babe30092`.
The earlier seam is not a product feature and remains disconnected from
settings UI, microphone, scene notifications and composer.

The review fixture `/tmp/woow-speech-9bb1a24-review.swift` reproduced that a
transport could suspend after receiving a request, the settings and credential
could change, and the transport could still dispatch the old request. A later
stale-result check did not prevent the disclosure. The fixture uses only
synthetic audio and credentials. The existing test for a failed selection probe
also used a short recording, which never exercised the retained selection.

`ConfiguredProviderSpeech` now requires the separate trusted
`AuthorizedSpeechProviderTransport` contract. Each probe and recording gets a
one-use dispatch permit. Immediately before actual dispatch, the permit checks
its cancellation, current generation, exact saved URL, chat model, credential
account and revision. The check and the synchronous dispatch operation run
while holding the same process-wide lock used by model repository saves and
removals. Cancellation has a synchronized gate as well. A failed credential
removal advances the revision before attempting the operation, so a partial
Keychain mutation cannot leave the prior request valid. A failed probe still
retains the prior verified choice when its settings remain current.

The authorized URLSession implementation constructs a suspended data task and
uses `resume()` as the dispatch operation inside that boundary. Its per-request
delegate refuses redirects, caps successful responses while streaming, and
avoids reading error bodies. A separately injected transport is trusted to call
the permit at its own actual dispatch operation and to propagate cancellation;
calling the permit before a later delayed send violates the contract. The old
general `ProviderSpeechClient` and its transport interface are not an
acceptable substitute for this authorization boundary.

The ordering guarantee is scoped to in-process writes through
`ModelSettingsRepository` and callers that use this authorized transport.
Direct defaults writes, external Keychain changes, other processes, and future
provider-specific settings need their own coordination before integration.
Settings changes invalidate a staged request at its dispatch gate; this stage
does not subscribe to changes to cancel an already resumed request immediately.
Once `resume()` wins the race, URLSession has been handed the request. Cancel
is best effort and cannot retract bytes already handed to the network. A later
settings change still prevents the old result from being used.

`check_configured_provider_speech.sh` exercises delayed synthetic dispatch
with destination/key replacement, edit-and-revert, cancellation, partially
failed credential removal, a delayed probe, and a request already dispatched.
It also sends a full synthetic recording after a failed probe and verifies the
original endpoint, model and fixture credential. A concurrent writer test
checks that a repository mutation cannot interleave with dispatch.
`check_provider_speech.sh` tests the authorized URLSession path through an
intercepting URLProtocol, including denied/cancelled gates, one-use permits,
redirects and oversized responses. No real microphone or service is used.
Native iOS SDK compilation, URLSession timing/TLS on iOS, background and
settings notification wiring, and real service interoperability remain
unverified; do not enable provider capture on the strength of this stage.
