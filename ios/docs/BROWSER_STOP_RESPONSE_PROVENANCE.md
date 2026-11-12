# Stop and download response provenance

Status: **isolated candidate; not merged; native iOS validation required**. The
original `e7a5539` regression showed a stopped response getting `.download`
after a new same-URL navigation. `8b949dd` additionally reproduced this when
the new initial URL differed but redirected to the same attachment. The test
proxy holds genuine WebKit policy objects and controls their delivery order; it
does not establish that iOS naturally produces that order or that the old
transfer actually starts.

## Candidate behavior

After a manual stop, the original WebView stays alive and remains available for
page navigation, history and form actions. Its download provenance remains
ambiguous for the rest of that view's lifetime: the public action and response
policy APIs do not identify the issuing `WKNavigation`, and a time limit or
initial URL comparison cannot prove that old callbacks have drained. Main-frame
attachment/unsupported-MIME responses and download actions from this view are
cancelled instead of being given a download permit. When otherwise eligible,
the selected tab presents a list of untrusted candidates, with a separate
confirmation for each. This includes callbacks whose origin may be an old
navigation; displaying one is never permission to start a request. Up to 16
candidates are retained. Further candidates are cancelled and an explicit
overflow message tells the user to return to the page and retry. Repeated
delivery of the same policy object does not create another offer. Automated/research work is not
offered this flow. Action requests other than GET do not offer recovery.

The confirmation displays the proposed URL and explains that proceeding starts
a **new GET** in a single-use WebView. It never reconstructs the old request,
POST body, authorization header, referrer, form or sessionStorage. It uses the
same website data store, so cookies may be shared, but authentication, session
state and one-time URLs may behave differently. The existing download manager
still applies its HTTPS/URL, redirect, TLS, size and storage checks. The
isolated WebView does not provide network-level isolation of the original page,
its scripts, DNS or subresources.

A confirmation is single-use. Dismissing an offer discards that offer; closing
the list discards all unconfirmed offers. Starting another explicit navigation
also discards the list. Tab switching, page/tab closure, website-data retirement and starting automation revoke pending offers and a
pending isolated-download handoff. Closing the list alone does not retract a
GET the user already confirmed. If the asynchronous WebKit callback arrives
later, the returned download is cancelled. A GET already handed to WebKit can
reach the server before cancellation; this is not a promise to undo a request.
An accepted download is subsequently managed by the existing download manager.
The original view is never reloaded automatically, and stop does not replay POST.

This is a deliberate tradeoff: a legitimate action or response download after a
stop may require an extra confirmation and a new GET, even at a different
initial URL. A download requiring POST or page-specific state may not be
recoverable. Before any stop, existing manual download behavior is unchanged.
This does not claim parity with Android or prove that other callback sequences
are impossible. Only selected eligible responses create offers; other ambiguous
callbacks are cancelled without consuming a later permit.

## Local verification

Run `python3 ios/scripts/check_browser_stop_redirect.py` on macOS with command
line tools. Its synthetic loopback fixture and nonpersistent website store use
no external site, personal keychain or real credentials. It runs same-URL and
redirect response-policy interleavings, checks the old response is cancelled,
and checks a user-confirmed isolated GET completes. Two distinct real WebKit
actions are held and delivered old-first: both offers remain visible and each
requires a separate GET. A bounded-state check covers overflow and tab-switch
revocation. The close test holds a real WebKit download handoff, closes the page,
then synchronously observes its rejection. The suite exercises ordinary
action download before stop, action confirmation afterward, delayed action and
response `didBecome` callbacks, duplicate confirmation, dismissal, page closure,
and the prior loopback checks for back, forward and a new form POST after stop.
The callback proxy injects ordering and is not an iOS timing proof.

Resource generation and localization checks cover Traditional Chinese,
Simplified Chinese and English. The available local compiler can parse iOS
syntax, but there is no iOS SDK in this environment. iOS SwiftUI typechecking,
native WebKit and ATS, authentication and cookie behavior, backgrounding,
accessibility and device-level cancellation require further validation before
integration. URL-policy checks are not a DNS-rebinding or connection sandbox.
