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
