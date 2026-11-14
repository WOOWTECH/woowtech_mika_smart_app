import Foundation
import WebKit
import AssistantBrowser

/// The tab a web task from chat works in. It is not in the browser's tab list
/// and ends with the task. It shares the built-in browser's website data, so
/// sites the user signed in to in the app stay signed in (owner decision,
/// 2026-11-13). Every main-frame navigation, redirects included, follows
/// ChatWebTaskPolicy and must be a GET, except a form the task itself just
/// sent under the money rule; no downloads, pop-ups, camera, microphone or
/// page dialogs. WebKit runs normally only while the view is in a window, so
/// the chat keeps it in its small preview.
@MainActor final class ChatWebTaskTab: NSObject, ChatWebTaskExecuting, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let fixtureOrigin: URL?
    private enum LoadState { case idle, loading, finished, failed(Error) }
    private var state = LoadState.idle
    private var committed = false
    private var stoppedBy: ChatWebExecutionError?
    private var httpStatus: Int?
    private var terminated = false
    private var loadedOnce = false
    private var idleSince: Date?
    private var requestedURL: URL?
    /// A form the task just sent may load with POST for a few seconds.
    private var submissionAllowedUntil: Date?
    /// While the user has the page (我來處理), their own forms may load too.
    var userControlled = false
    private var navigationStarted = false
    /// The last message a page tried to show in a dialog; dialogs close at once.
    private(set) var lastDialog: String?

    init(dataStore: WKWebsiteDataStore, fixtureOrigin: URL? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        #endif
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        self.fixtureOrigin = fixtureOrigin
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if os(iOS)
        webView.accessibilityIdentifier = "chat.web.page"
        #endif
    }

    var currentURL: URL? {
        guard let url = webView.url, url.scheme != "about" else { return nil }
        return url
    }

    /// Stops loading and leaves a blank page, so nothing keeps running.
    func close() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    // MARK: ChatWebTaskExecuting

    func load(_ url: URL) async throws -> ChatWebLoad {
        try Task.checkCancellation()
        prepareNavigation()
        requestedURL = url
        webView.load(URLRequest(url: url))
        return try await waitForPage(timeout: loadedOnce ? 25 : 45)
    }

    func capture() async throws -> ChatWebPageCapture {
        try Task.checkCancellation()
        if terminated { try await reloadAfterTermination() }
        guard let url = currentURL else { throw ChatWebExecutionError.pageUnavailable }
        await settle()
        let raw = try await evaluate(Self.captureScript, timeout: 10)
        guard let data = raw.data(using: .utf8), let page = try? JSONDecoder().decode(Capture.self, from: data) else {
            throw ChatWebExecutionError.pageUnavailable
        }
        let links = page.links.compactMap { link -> ChatWebCapturedLink? in
            guard let target = URL(string: link.u) else { return nil }
            let title = link.t.isEmpty ? (target.host ?? link.u) : link.t
            return ChatWebCapturedLink(title: String(title.prefix(120)), url: target)
        }
        return ChatWebPageCapture(url: currentURL ?? url, title: page.title, text: page.text, truncated: page.truncated,
                                  links: links, hasPasswordField: page.password, hasCaptcha: page.captcha,
                                  omittedRegions: page.omitted)
    }

    func scroll(_ direction: ChatWebScrollDirection) async throws -> Bool {
        try Task.checkCancellation()
        if terminated { try await reloadAfterTermination() }
        guard currentURL != nil else { throw ChatWebExecutionError.pageUnavailable }
        let sign = direction == .down ? "1" : "-1"
        let moved = try await evaluate(Self.scrollScript.replacingOccurrences(of: "SIGN", with: sign), timeout: 5) == "true"
        // Let content that loads on scrolling arrive before the next read.
        try await Task.sleep(nanoseconds: 800_000_000)
        return moved
    }

    func goBack() async throws -> ChatWebLoad? {
        try Task.checkCancellation()
        guard webView.canGoBack else { return nil }
        prepareNavigation()
        webView.goBack()
        return try await waitForPage(timeout: 25)
    }

    func waitFor(_ condition: ChatWebWaitCondition, value: String, seconds: Int) async throws -> Bool {
        let end = Date().addingTimeInterval(TimeInterval(min(max(seconds, 1), ChatWebCommand.maximumWaitSeconds)))
        let literal = String(decoding: (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8), as: UTF8.self)
        repeat {
            try Task.checkCancellation()
            switch condition {
            case .urlContains:
                if webView.url?.absoluteString.contains(value) == true { return true }
            case .textPresent, .textAbsent:
                let present = (try? await evaluate("String(!!(document.body && document.body.innerText.includes(\(literal))))", timeout: 3)) == "true"
                if present == (condition == .textPresent) { return true }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        } while Date() < end
        return false
    }

    // MARK: Controls

    func observe() async throws -> ChatWebControls {
        try Task.checkCancellation()
        if terminated { try await reloadAfterTermination() }
        guard let url = currentURL else { throw ChatWebExecutionError.pageUnavailable }
        await settle()
        let raw = try await controls(mode: "snapshot", request: [:])
        guard let data = raw.data(using: .utf8), data.count <= 512 * 1024,
              let page = try? JSONDecoder().decode(Snapshot.self, from: data) else { throw ChatWebExecutionError.pageUnavailable }
        return ChatWebControls(snapshotID: page.snapshotId, url: URL(string: page.url) ?? url,
                               controls: page.controls.map {
                                   ChatWebControl(ref: $0.ref, kind: $0.kind, label: $0.label, enabled: $0.enabled,
                                                  checked: $0.checked, options: $0.options ?? [])
                               }, truncated: page.truncated)
    }

    func act(_ action: ChatWebControlAction, snapshot: String, allowsSubmission: Bool) async throws -> ChatWebActResult {
        try Task.checkCancellation()
        var request: [String: Any] = ["snapshotId": snapshot]
        switch action {
        case .tap(let ref): request["ref"] = ref; request["kind"] = "tap"
        case .type(let ref, let text, let enter): request["ref"] = ref; request["kind"] = "type"; request["text"] = text; request["pressEnter"] = enter
        case .select(let ref, let option): request["ref"] = ref; request["kind"] = "select"; request["option"] = option
        }
        let before = webView.url
        navigationStarted = false
        submissionAllowedUntil = allowsSubmission ? Date().addingTimeInterval(10) : nil
        defer { submissionAllowedUntil = nil }
        state = .finished; committed = false; stoppedBy = nil; httpStatus = nil; idleSince = nil
        let outcome = try await controls(mode: "perform", request: request)
        guard outcome == "dispatched" else { throw ChatWebExecutionError.actionRefused(outcome) }
        // Give the page a moment to start a navigation of its own.
        for _ in 0..<15 where !navigationStarted && !webView.isLoading && stoppedBy == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // A navigation the rules refused (a form outside an action, a log-out
        // path) never starts; say so instead of reporting nothing happened.
        if let stoppedBy { throw stoppedBy }
        if navigationStarted || webView.isLoading {
            if case .finished = state { state = .loading }
            let load = try await waitForPage(timeout: 25)
            return ChatWebActResult(navigated: true, load: load)
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        guard webView.url != before, let url = currentURL else { return ChatWebActResult(navigated: false, load: nil) }
        // A page that changes its address without loading (single-page sites).
        return ChatWebActResult(navigated: true, load: ChatWebLoad(url: url, title: webView.title ?? "", httpStatus: httpStatus, settled: true))
    }

    /// The fixed controls script in the app's own script world; values reach
    /// it only through WebKit's arguments.
    private func controls(mode: String, request: [String: Any]) async throws -> String {
        let pending = PendingEvaluation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                pending.deadline = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    pending.finish(.failure(ChatWebExecutionError.readTimedOut))
                }
                webView.callAsyncJavaScript(Self.controlsScript, arguments: ["mode": mode, "request": request],
                                            in: nil, in: .defaultClient) { result in
                    switch result {
                    case .success(let value as String): pending.finish(.success(value))
                    case .success, .failure: pending.finish(.failure(ChatWebExecutionError.pageUnavailable))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
    }

    private struct Snapshot: Decodable {
        let snapshotId: String
        let url: String
        let truncated: Bool
        let controls: [Control]
        struct Control: Decodable {
            let ref: String; let kind: String; let label: String; let enabled: Bool
            let checked: Bool?; let options: [String]?
        }
    }

    // MARK: Loading

    private func prepareNavigation() {
        state = .loading; committed = false; stoppedBy = nil; httpStatus = nil; lastDialog = nil
        terminated = false; idleSince = nil; requestedURL = nil
    }

    private func waitForPage(timeout: TimeInterval) async throws -> ChatWebLoad {
        let end = Date().addingTimeInterval(timeout)
        do {
            while Date() < end {
                if let stoppedBy { throw stoppedBy }
                if terminated { throw ChatWebExecutionError.interrupted }
                switch state {
                case .finished where !webView.isLoading:
                    loadedOnce = true
                    return try result(settled: true)
                case .failed(let error) where !webView.isLoading:
                    throw Self.navigationError(error)
                default:
                    // A page restored from the back-forward cache may not report
                    // didFinish; an idle committed view is a loaded page.
                    // A link to a part of the same page changes no document.
                    if !webView.isLoading && (committed || (requestedURL != nil && webView.url == requestedURL)) {
                        if let idleSince, Date().timeIntervalSince(idleSince) > 1 { loadedOnce = true; return try result(settled: true) }
                        if idleSince == nil { idleSince = Date() }
                    } else { idleSince = nil }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            if error is CancellationError { webView.stopLoading() }
            throw error
        }
        if committed, currentURL != nil { loadedOnce = true; return try result(settled: false) }
        webView.stopLoading()
        throw ChatWebExecutionError.navigationTimedOut
    }

    private func result(settled: Bool) throws -> ChatWebLoad {
        guard let url = currentURL else { throw ChatWebExecutionError.pageUnavailable }
        return ChatWebLoad(url: url, title: webView.title ?? "", httpStatus: httpStatus, settled: settled)
    }

    private func reloadAfterTermination() async throws {
        guard let url = webView.url ?? webView.backForwardList.currentItem?.url, url.scheme != "about" else {
            throw ChatWebExecutionError.interrupted
        }
        prepareNavigation()
        webView.load(URLRequest(url: url))
        _ = try await waitForPage(timeout: 45)
    }

    /// Waits up to about three seconds for the page text to stop growing.
    private func settle() async {
        var previous = -1
        for _ in 0..<6 {
            guard let length = try? await evaluate("String(document.readyState === 'complete' && document.body ? document.body.innerText.length : -1)", timeout: 2),
                  let value = Int(length) else { return }
            if value >= 0 && value == previous { return }
            previous = value
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Runs in the app's own script world, which page scripts cannot change.
    /// A page that never answers (for example a suspended web process) ends
    /// the wait at the deadline instead of holding the task.
    private func evaluate(_ script: String, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        let pending = PendingEvaluation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                pending.deadline = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    pending.finish(.failure(ChatWebExecutionError.readTimedOut))
                }
                webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                    switch result {
                    case .success(let value as String): pending.finish(.success(value))
                    case .success, .failure: pending.finish(.failure(ChatWebExecutionError.pageUnavailable))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
    }

    @MainActor private final class PendingEvaluation {
        var continuation: CheckedContinuation<String, Error>?
        var deadline: Task<Void, Never>?
        func finish(_ result: Result<String, Error>) {
            deadline?.cancel(); deadline = nil
            let waiting = continuation; continuation = nil
            waiting?.resume(with: result)
        }
    }

    private static func navigationError(_ error: Error) -> ChatWebExecutionError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut { return .navigationTimedOut }
        return .navigationFailed(nsError.domain == NSURLErrorDomain ? "url_\(nsError.code)" : "webkit_\(nsError.code)")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard mainFrame else {
            decisionHandler(["https", "http", "about", "data", "blob"].contains(scheme) ? .allow : .cancel); return
        }
        if scheme == "about" { decisionHandler(.allow); return }
        if navigationAction.shouldPerformDownload { stop(.navigationFailed("download")); decisionHandler(.cancel); return }
        let method = (navigationAction.request.httpMethod ?? "GET").uppercased()
        guard method == "GET" || (method == "POST" && (userControlled || (submissionAllowedUntil.map { Date() < $0 } ?? false))) else {
            stop(.navigationFailed("not_get")); decisionHandler(.cancel); return
        }
        switch ChatWebTaskPolicy.evaluate(url, fixtureOrigin: fixtureOrigin) {
        // Sign-in pages open: the task hands them to the user, who signs in there.
        case .allow, .signIn: decisionHandler(.allow)
        case .block(let reason): stop(.blocked(reason)); decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame else { decisionHandler(.allow); return }
        httpStatus = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        guard navigationResponse.canShowMIMEType else { stop(.navigationFailed("download")); decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationStarted = true
        if case .idle = state { return }
        state = .loading
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { committed = true }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state = .finished }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { terminated = true }

    private func failed(_ error: Error) {
        let nsError = error as NSError
        // A page that starts another navigation cancels the first one; keep
        // waiting for the newer one instead of reporting a failure.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled && webView.isLoading { return }
        state = .failed(error)
    }

    private func stop(_ reason: ChatWebExecutionError) {
        if stoppedBy == nil { stoppedBy = reason }
    }

    // MARK: WKUIDelegate

    /// A pop-up opens in the task tab itself, under the same rules.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET" {
            switch ChatWebTaskPolicy.evaluate(url, fixtureOrigin: fixtureOrigin) {
            case .allow, .signIn: webView.load(navigationAction.request)
            case .block: break
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        lastDialog = String(message.prefix(200)); completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        lastDialog = String(message.prefix(200)); completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        lastDialog = String(prompt.prefix(200)); completionHandler(nil)
    }

    #if os(iOS)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
    #endif

    // MARK: Scripts

    /// Visible links, buttons, text fields, toggles and choices with refs that
    /// live only in this script world; passwords, one-time codes, card numbers
    /// and sign-in names are never listed. One action per snapshot.
    static let controlsScript = #"""
    // mode: 'snapshot' | 'perform'; request: {snapshotId, ref, kind: 'tap'|'type'|'select', text, pressEnter, option}
    if (!globalThis.__woowTask || globalThis.__woowTask.document !== document) {
      globalThis.__woowTask = {document, ids: new WeakMap(), serial: 0, records: new Map(), snapshotId: null, url: null};
    }
    const state = globalThis.__woowTask;
    const clip = s => String(s || '').replace(/\s+/g, ' ').trim().slice(0, 160);
    const visible = e => {
      if (!e.isConnected || e.closest('[hidden],[inert],[aria-hidden="true"]') || !e.getClientRects().length) return false;
      for (let p = e; p; p = p.parentElement) {
        const s = getComputedStyle(p);
        if (s.display === 'none' || s.visibility === 'hidden' || s.visibility === 'collapse' || s.opacity === '0') return false;
      }
      return true;
    };
    const labelText = e => Array.from(e.labels || []).map(l => {
      const copy = l.cloneNode(true); copy.querySelectorAll('input,select,textarea,button').forEach(n => n.remove()); return copy.textContent;
    }).join(' ');
    const label = e => clip(e.getAttribute('aria-label') || labelText(e) || e.getAttribute('placeholder') ||
      (e.tagName === 'INPUT' ? (e.value && ['submit', 'button'].includes((e.type || '').toLowerCase()) ? e.value : e.getAttribute('name')) : e.innerText || e.textContent) ||
      e.getAttribute('title') || e.tagName);
    // Passwords, one-time codes, card numbers and sign-in names are the user's to type.
    const sensitive = e => /password|passwd|secret|token|api.?key|credential|one.?time|otp|cc-|credit.?card|card.?number|cvv|cvc|username|login/i.test(
      [e.type, e.name, e.id, e.autocomplete, e.getAttribute('aria-label'), e.getAttribute('placeholder'), labelText(e)].join(' '));
    const describe = e => {
      if (!visible(e) || sensitive(e)) return null;
      const tag = e.tagName, type = (e.type || '').toLowerCase(), role = (e.getAttribute('role') || '').toLowerCase();
      let kind = null;
      if (tag === 'A' && e.hasAttribute('href') && !e.hasAttribute('download')) kind = 'link';
      else if (tag === 'BUTTON' || (tag === 'INPUT' && ['submit', 'button', 'reset', 'image'].includes(type)) || role === 'button' || role === 'tab' || role === 'menuitem') kind = 'button';
      else if (tag === 'INPUT' && ['checkbox', 'radio'].includes(type)) kind = 'toggle';
      else if (tag === 'TEXTAREA' || (tag === 'INPUT' && ['', 'text', 'search', 'email', 'url', 'tel', 'number'].includes(type))) kind = 'text';
      else if (tag === 'SELECT' && !e.multiple && e.options.length <= 100) kind = 'select';
      if (!kind) return null;
      return {kind, label: label(e), enabled: !e.matches(':disabled') && !e.readOnly && e.getAttribute('aria-disabled') !== 'true',
        checked: kind === 'toggle' ? !!e.checked : undefined,
        options: kind === 'select' ? Array.from(e.options).slice(0, 100).map(o => clip(o.label || o.text)) : undefined};
    };
    if (mode === 'snapshot') {
      const controls = [], records = new Map(); let scanned = 0, truncated = false;
      for (const e of document.querySelectorAll('a[href],button,input,textarea,select,[role=button],[role=tab],[role=menuitem]')) {
        if (++scanned > 3000 || controls.length >= 200) { truncated = true; break; }
        const d = describe(e); if (!d) continue;
        if (!state.ids.has(e)) state.ids.set(e, 'e' + (++state.serial));
        const ref = state.ids.get(e); controls.push({ref, ...d}); records.set(ref, e);
      }
      state.records = records; state.snapshotId = 's' + Date.now().toString(36); state.url = location.href;
      return JSON.stringify({snapshotId: state.snapshotId, url: state.url, controls, truncated});
    }
    if (mode !== 'perform') return 'invalid_request';
    if (state.snapshotId !== request.snapshotId || state.url !== location.href) return 'stale_snapshot';
    const e = state.records.get(request.ref); if (!e) return 'unknown_ref';
    const d = describe(e); if (!d || !d.enabled) return 'unavailable_control';
    e.scrollIntoView({block: 'center', inline: 'nearest', behavior: 'instant'});
    const r = e.getBoundingClientRect(), x = Math.max(0, Math.min(innerWidth - 1, r.x + r.width / 2)), y = Math.max(0, Math.min(innerHeight - 1, r.y + r.height / 2));
    const hit = document.elementFromPoint(x, y);
    if (request.kind === 'tap' && (!hit || (hit !== e && !e.contains(hit) && !hit.contains(e)))) return 'covered';
    state.snapshotId = null; // one action per snapshot, even if the site throws
    if (request.kind === 'tap' && ['link', 'button', 'toggle'].includes(d.kind)) {
      if (e.tagName === 'A' && e.target && e.target !== '_self') e.target = '_self';
      e.click();
    } else if (request.kind === 'type' && d.kind === 'text' && typeof request.text === 'string' && request.text.length <= 4096) {
      e.focus();
      const prototype = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(e, request.text);
      e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true}));
      if (request.pressEnter) {
        for (const type of ['keydown', 'keypress', 'keyup']) e.dispatchEvent(new KeyboardEvent(type, {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true}));
        if (e.form && e.tagName !== 'TEXTAREA') { if (typeof e.form.requestSubmit === 'function') e.form.requestSubmit(); else e.form.submit(); }
      }
    } else if (request.kind === 'select' && d.kind === 'select' && typeof request.option === 'string') {
      const wanted = clip(request.option);
      const index = Array.from(e.options).findIndex(o => !o.disabled && (clip(o.label || o.text) === wanted || o.value === request.option));
      if (index < 0) return 'unknown_option';
      e.selectedIndex = index; e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true}));
    } else return 'invalid_request';
    return 'dispatched';
    """#

    private struct Capture: Decodable {
        let title: String
        let text: String
        let truncated: Bool
        let links: [Link]
        let password: Bool
        let captcha: Bool
        let omitted: Int
        struct Link: Decodable { let t: String; let u: String }
    }

    /// The rendered text of the whole page (open shadow roots included; form
    /// field values never), links with the main content's first, and signs of
    /// a sign-in form or a CAPTCHA.
    static let captureScript = #"""
    (() => {
      const limit = 300000;
      const clean = s => (s || '').replace(/[ \t ]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
      const visible = e => e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
      if (!document.body) return JSON.stringify({title: document.title || '', text: '', truncated: false, links: [], password: false, captcha: false, omitted: 0});
      let text = clean(document.body.innerText);
      const roots = [];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
      let seen = 0;
      while (walker.nextNode() && seen < 20000) { seen++; if (walker.currentNode.shadowRoot) roots.push(walker.currentNode.shadowRoot); }
      for (const root of roots.slice(0, 200)) {
        for (const child of root.children) { if (child.innerText) text += '\n' + clean(child.innerText); }
      }
      const truncated = text.length > limit;
      if (truncated) text = text.slice(0, limit);
      let omitted = 0;
      for (const frame of document.querySelectorAll('iframe,frame,object,embed')) { if (visible(frame)) omitted++; }
      const chrome = 'nav,header,footer,aside,[role=navigation],[role=banner],[role=contentinfo]';
      const main = [], rest = [], hrefs = new Set();
      for (const a of document.querySelectorAll('a[href]')) {
        if (main.length + rest.length >= 400) break;
        const u = a.href;
        if (!/^https?:/i.test(u) || hrefs.has(u) || !visible(a)) continue;
        hrefs.add(u);
        const t = clean(a.innerText || a.getAttribute('aria-label') || a.title || '').slice(0, 120);
        (a.closest(chrome) ? rest : main).push({t, u});
      }
      const password = Array.from(document.querySelectorAll('input[type=password]')).some(visible);
      const captcha = Array.from(document.querySelectorAll('iframe[src]')).some(f => /recaptcha|hcaptcha|turnstile|captcha/i.test(f.src)) ||
        Array.from(document.querySelectorAll('[id*=captcha i],[class*=captcha i],.g-recaptcha,.h-captcha,.cf-turnstile')).some(visible);
      return JSON.stringify({title: (document.title || '').slice(0, 200), text, truncated, links: main.concat(rest), password, captcha, omitted});
    })()
    """#

    /// Scrolls the page, or its largest scrolling area when the page itself
    /// does not move; "true" when something moved.
    static let scrollScript = #"""
    (() => {
      const step = SIGN * Math.max(200, Math.round(innerHeight * 0.85));
      const before = scrollY;
      scrollBy(0, step);
      if (scrollY !== before) return 'true';
      let best = null, size = 0;
      for (const e of document.querySelectorAll('body *')) {
        const s = getComputedStyle(e);
        if (!/(auto|scroll)/.test(s.overflowY) || e.scrollHeight <= e.clientHeight + 40) continue;
        const area = e.clientWidth * e.clientHeight;
        if (area > size) { size = area; best = e; }
      }
      if (!best) return 'false';
      const top = best.scrollTop;
      best.scrollBy(0, step);
      return String(best.scrollTop !== top);
    })()
    """#
}
