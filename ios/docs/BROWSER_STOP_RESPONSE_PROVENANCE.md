# Stop and late WebKit response provenance

Status: **unresolved; do not merge the stop-loading candidate on the basis of
this investigation**. `fa893e1` fixes stale rejection overwriting page state,
but does not associate response policies with the issuing navigation.

## Reproducible boundary

Run `python3 ios/scripts/check_browser_stop_same_url.py` on macOS with the
Command Line Tools. This is an intentionally red regression until the issue is
fixed. It builds the app sources and DEBUG browser module and uses the existing
isolated, synthetic loopback PDF fixture and a nonpersistent website store. It
does not use a real site, user Keychain or external network. It captures two
real `WKNavigationResponse` instances and, using a test-only delegate proxy,
delays forwarding the first one until after stop and a new same-URL navigation.
The test verifies the new download really completes with the synthetic bytes.
It separately repeats the scenario in two distinct WebViews/sessions, then
requires the old same-WebView response policy to be `.cancel`.

On `fa893e1`, the new download completes but the old response receives
`.download`. With two distinct sessions, the old response is `.cancel` and the
new same-URL download completes. This exercises existing separate sessions, not
a production same-tab WebView swap. The proxy creates the ordering intentionally: this demonstrates
how the application handles it, not that native iOS WebKit naturally delivers
it. Whether an actual late callback leads to a `WKDownload` is unverified.

The macOS SDK's public `WKNavigationResponse` exposes the main-frame flag, a
`URLResponse`, and `canShowMIMEType`; the response-policy delegate receives a
`WKWebView` and that response, not a `WKNavigation`. `didStart`, `didFinish`,
and failure callbacks do carry a `WKNavigation`, but that identity cannot be
compared to the response. A `WKDownload` exposes its originating WebView and
original request, not the issuing navigation. Two same-URL responses in the
same WebView therefore cannot be safely attributed solely using these public
fields. Matching the response object at `didBecome` is useful to consume an
already issued permit, but does not establish which navigation was entitled to
that permit in the first place. This conclusion is based on the installed macOS
SDK headers; verify the target iOS SDK and callback behavior separately.

## Candidate isolation design, not implemented

One viable direction is to make the **WebView instance** an epoch boundary.
After stop, quarantine the old WebView and invalidate its download and document
authority; run the next explicitly initiated navigation on a fresh WebView with
a fresh delegate/session state. Check the callback's WebView identity at every
policy, navigation, download and UI delegate entry, and on asynchronous KVO
work. Never reuse a quarantined instance for a new epoch. A shared explicitly
selected `WKWebsiteDataStore` can retain site data, but it does not imply that
in-memory page state, session storage, popup relationships or WebKit's
back/forward list survive. Every old download or delayed callback needs its own
cancellation and teardown policy. Site-initiated navigation on the quarantined
page must not silently inherit new authority.

The app currently attaches a WebView once in `BrowserWebView.makeUIView`; its
`updateUIView` does not replace the view. A production change therefore also
needs a controlled host swap and published identity, plus a design for history,
partially loaded documents, form state, tabs, popups, media and accessibility.
Do not automatically replay POSTs or reconstruct a request from a response URL.
A simpler explicit new-tab/session recovery can retain existing download support,
but loses the old page's native history and is not transparent parity.

Another possible product flow is to cancel an ambiguous response and require a
new, explicit download action in an isolated single-use WebView. It must show
the destination and must not silently repeat a POST or one-time request; such
requests may not be recoverable. Cookie, authentication, redirect, same-site
and referrer behavior require testing. This is not a blanket ban on all later
downloads, but it changes the user flow and does not establish that every
previous download can be replayed safely.

Before integrating either approach, require regression coverage for old/new
same-URL response and action downloads, redirect chains, stale `didBecome`,
normal attachment downloads, page actions and POSTs, tab switch/close,
automation/research restrictions and native iOS WebKit/ATS behavior. No
identity inference from URL, timing, response order or a fixed delay is a
substitute for a provenance boundary.

## Scoped download recovery investigation

The broad old-view quarantine in `5179bbf` is not equivalent to the existing
browser: it prevents normal navigation in that view. This branch starts from
`e7a5539` instead, and makes no product-policy or UI change. The diagnostic
`python3 ios/scripts/check_browser_stop_redirect.py` builds DEBUG macOS
WebKit against synthetic loopback only. It first confirms the known-red
same-URL case, including a successful new download and the separate-view
control. It then holds an old real attachment response, stops, and starts a new
request at a **different** URL, whose 302 response leads to the same attachment
URL. The test proxy releases the old response after the redirected new response
is held. Both receive `.download`, and the new synthetic file completes. Thus
comparing only the two initial URLs misses this controlled case. The diagnostic
passes when it reproduces the unsafe current behavior; it is not a fix.

The proxy deliberately changes when the production delegate receives genuine
WebKit objects. It does not establish that iOS naturally delivers this order,
or that WebKit starts an old transfer after stop. In particular, neither test
proves a bounded period after which all stopped callbacks have drained. A
redirect destination can differ from the initial URL, and callbacks' URL or
object identity alone do not reveal their issuing `WKNavigation`. A larger
set of observed URLs may reduce prompts but has no demonstrated completeness
for unobserved or late redirects. Likewise, the action policy delegate also
lacks a `WKNavigation` parameter; treating every action as certainly fresh
needs separate evidence.

The least disruptive conservative UX to investigate is:

1. Keep the original WebView alive for ordinary pages, back/forward, form
   interactions and subsequent navigation. Stop itself does not replay a POST.
2. When a download decision in that view cannot be proven fresh, cancel that
   **individual** decision and offer an explicit, clearly labelled new GET in
   a dedicated single-use WebView. The user chooses whether to proceed; show
   the proposed destination and explain that this is a new request. Keep the
   existing URL, redirect, authentication and download gates; do not import
   an old response's headers, POST body, or authorization as proof of intent.
3. If the original action was a POST, a one-time link, or needs page-specific
   state, explain that this new GET may fail or have different effects. Let the
   user return to the original page to initiate the intended action. A shared
   website data store can retain some cookies and storage, but does not promise
   sessionStorage, native history, DOM/form state, referrer, HTTP authentication
   or equivalent server behavior in the new view.

This avoids blocking all page navigation and is not a blanket ban on downloads.
However, public response policy fields do not identify *only* the unsafe
responses in the same view. A conservative implementation may have to prompt
for otherwise legitimate response downloads after a stop, including different
initial URLs that redirect to a common final URL. An implementation that admits
other downloads without prompting needs a defensible provenance boundary for
each such path, including action downloads and delayed `didBecome` callbacks.
Otherwise it would silently trade away the safety goal. Do not present this
proposal as implemented, as equivalent to the original download, or as network
isolation of page scripts or subresources.

The loopback site-mode check also exercises the original view after stop: back,
forward, and a newly initiated form POST. It stops a held GET following a
completed POST document and checks that no additional POST action is issued.
On the local macOS run, all 37 assertions passed. This exercises current
behavior, not the proposed recovery UI. Native iOS SDK,
ATS, authentication, website data sharing, action-policy interleavings, tab
closure and the single-use flow itself remain to be implemented and tested.
