import Foundation
import WebKit
import AssistantBrowser
import AssistantPersistence
#if os(iOS)
import UIKit
#if canImport(XCTest)
@testable import WoowAssistant
#endif
#else
import AppKit
#endif

private final class SiteModeKeys: LearningKeyStore {
    var keys: [String: Data] = [:]
    var unavailable = false
    func read(id: String) throws -> Data? {
        if unavailable { throw LearningFileError.unavailable }; return keys[id]
    }
    func insert(_ key: Data, id: String) throws {
        if unavailable { throw LearningFileError.unavailable }; keys[id] = key
    }
    func remove(id: String) throws { keys.removeValue(forKey: id) }
    func removeAll(except id: String) throws { keys = keys.filter { $0.key == id } }
}

@MainActor enum BrowserSiteModesAppChecks {
    struct Failure: Error { let check: String }
    static func wait(_ name: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() {
            guard Date() < deadline else { throw Failure(check: "deadline: " + name) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Observes actual WebKit navigation actions/preferences while forwarding
    /// the production delegate. External requests are cancelled after policy
    /// evaluation; pages are locally loaded HTML with reserved HTTPS origins.
    @MainActor final class Probe: NSObject, WKNavigationDelegate {
        let browser: BrowserSession
        var effectiveMode: WKWebpagePreferences.ContentMode?
        var localHTMLURL: URL?
        var allowReloadURL: URL?
        var allowsNetworkFixture: (URL) -> Bool = { _ in false }
        var omitNextPolicyObservation = false
        var finishes = 0
        var failures = 0
        var externallyCancelledURLs: [URL] = []
        var events: [String] = []
        var lastNavigation: WKNavigation?
        var lastStarted: WKNavigation?
        var deferResponseURL: URL?
        var deferredResponse: (() -> Void)?
        var deferredPolicies: [WKNavigationResponsePolicy] = []
        var holdNextDownloadAction = false
        var deferredDownloadAction: (() -> Void)?
        var deliveredActionPolicies: [WKNavigationActionPolicy] = []
        var holdNextDownload = false
        var deferredDownload: (() -> Void)?
        var actions: [(host: String?, main: Bool, method: String?, incomingMode: WKWebpagePreferences.ContentMode,
                       mode: WKWebpagePreferences.ContentMode, policy: WKNavigationActionPolicy, type: WKNavigationType)] = []
        init(_ browser: BrowserSession) { self.browser = browser }
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if holdNextDownloadAction && action.shouldPerformDownload {
                holdNextDownloadAction = false
                deferredDownloadAction = { [browser, weak self] in
                    browser.webView(view, decidePolicyFor: action, preferences: preferences) { policy, result in
                        self?.deliveredActionPolicies.append(policy); decisionHandler(policy, result)
                    }
                }
                return
            }
            let incomingMode = preferences.preferredContentMode
            events.append("policy:\(action.request.httpMethod ?? "nil"):body=\(action.request.httpBody?.count ?? -1):stream=\(action.request.httpBodyStream != nil)")
            if omitNextPolicyObservation, localHTMLURL == action.request.url {
                omitNextPolicyObservation = false; localHTMLURL = nil
                // Deliberately missing method evidence: real WebKit still starts,
                // commits and finishes a new document. Production must defer.
                decisionHandler(.allow, preferences); return
            }
            browser.webView(view, decidePolicyFor: action, preferences: preferences) { policy, result in
                self.actions.append((action.request.url?.host, action.targetFrame?.isMainFrame == true,
                                     action.request.httpMethod, incomingMode, result.preferredContentMode, policy, action.navigationType))
                // One explicitly scheduled local HTML load only. Everything
                // else is observed then cancelled before network/download I/O.
                let local = self.localHTMLURL == action.request.url && action.navigationType == .other
                    && action.targetFrame?.isMainFrame == true
                let reload = self.allowReloadURL == action.request.url && action.navigationType == .reload
                    && action.targetFrame?.isMainFrame == true && action.request.httpMethod == "GET"
                if local { self.localHTMLURL = nil }
                if reload { self.allowReloadURL = nil }
                let networkFixture = action.request.url.map(self.allowsNetworkFixture) == true
                if !(local || reload || networkFixture), let url = action.request.url {
                    self.externallyCancelledURLs.append(url)
                }
                decisionHandler(local || reload || networkFixture ? policy : .cancel, result)
            }
        }
        func webView(_ view: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.response.url == deferResponseURL {
                deferResponseURL = nil
                deferredResponse = { [browser, weak self] in
                    browser.webView(view, decidePolicyFor: response) { policy in
                        self?.deferredPolicies.append(policy); decisionHandler(policy)
                    }
                }
                return
            }
            browser.webView(view, decidePolicyFor: response, decisionHandler: decisionHandler)
        }
        func webView(_ view: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            if holdNextDownload {
                holdNextDownload = false
                deferredDownload = { [browser] in browser.webView(view, navigationResponse: navigationResponse, didBecome: download) }
                return
            }
            browser.webView(view, navigationResponse: navigationResponse, didBecome: download)
        }
        func webView(_ view: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            if holdNextDownload {
                holdNextDownload = false
                deferredDownload = { [browser] in browser.webView(view, navigationAction: navigationAction, didBecome: download) }
                return
            }
            browser.webView(view, navigationAction: navigationAction, didBecome: download)
        }
        func webView(_ view: WKWebView, didStartProvisionalNavigation nav: WKNavigation!) {
            events.append("start"); lastStarted = nav
            browser.webView(view, didStartProvisionalNavigation: nav)
        }
        func webView(_ view: WKWebView, didCommit nav: WKNavigation!) {
            events.append("commit")
            effectiveMode = nav?.effectiveContentMode
            browser.webView(view, didCommit: nav)
        }
        func webView(_ view: WKWebView, didFinish nav: WKNavigation!) {
            events.append("finish")
            finishes += 1; lastNavigation = nav
            browser.webView(view, didFinish: nav)
        }
        func webView(_ view: WKWebView, didReceiveServerRedirectForProvisionalNavigation nav: WKNavigation!) {
            browser.webView(view, didReceiveServerRedirectForProvisionalNavigation: nav)
        }
        func webView(_ view: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
            failures += 1; browser.webView(view, didFail: nav, withError: error)
        }
        func webView(_ view: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
            failures += 1; browser.webView(view, didFailProvisionalNavigation: nav, withError: error)
        }
    }

    @MainActor final class Host {
        #if os(iOS)
        let window: UIWindow
        #else
        let window: NSWindow
        #endif
        init() throws {
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(check: "host scene")
            }
            window = UIWindow(windowScene: scene); window.rootViewController = UIViewController(); window.makeKeyAndVisible()
            #else
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.orderFront(nil)
            #endif
        }
        func attach(_ browser: BrowserSession) {
            #if os(iOS)
            let parent = window.rootViewController!.view!
            parent.subviews.forEach { $0.removeFromSuperview() }
            browser.webView.frame = parent.bounds; parent.addSubview(browser.webView)
            #else
            window.contentView = browser.webView
            #endif
        }
        func close() {
            #if os(iOS)
            window.isHidden = true
            #else
            window.orderOut(nil)
            #endif
        }
    }

    static func run() async throws -> [String: Any] {
        var count = try BrowserUserSiteModesChecks.run()
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw Failure(check: name) }; count += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-site-modes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("library.vault"), keys = SiteModeKeys()
        func vault() -> EncryptedLearningFile { EncryptedLearningFile(url: file, keys: keys) }
        let store = WKWebsiteDataStore.nonPersistent()
        let workspace = BrowserWorkspace(dataStore: store, vault: vault(), downloadDirectory: root.appendingPathComponent("Downloads"))
        try check(workspace.available, "isolated actual workspace available")
        let host = try Host(); defer { host.close(); workspace.cancelAllWork() }
        let browser = workspace.selected, probe = Probe(workspace.selected)
        host.attach(browser); browser.webView.navigationDelegate = probe
        let html = """
        <!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>
        <title>Site mode fixture</title><p>LOCAL SITE MODE</p>
        <input aria-label='Retained note' value='unchanged'>
        <button id='action' onclick='this.textContent="EXECUTED"'>Local action</button>
        <a id='query' href='https://research.example.invalid/page?q=restricted'>Query</a>
        <a id='cross' href='https://other.example.invalid/'>Cross origin</a>
        <a id='private' href='http://127.0.0.1/'>Private</a>
        <a id='download' href='https://research.example.invalid/file.txt' download>Download</a>
        <form id='post' method='POST' action='https://research.example.invalid/post'><button>Submit</button></form>
        """
        func load(_ url: URL, manually: Bool = true, method: String = "GET", observePolicy: Bool = true) async throws {
            let before = probe.finishes
            probe.localHTMLURL = url
            probe.omitNextPolicyObservation = !observePolicy
            var request = URLRequest(url: url); request.httpMethod = method
            if method == "POST" { request.httpBody = Data("fixture=synthetic".utf8) }
            if manually { browser.manualNavigation(to: url) { browser.webView.loadSimulatedRequest(request, responseHTML: html) } }
            else { browser.webView.loadSimulatedRequest(request, responseHTML: html) }
            try await wait("actual page", { browser.loadedURL == url && browser.current?.url == url && !browser.webView.isLoading && probe.finishes > before })
        }
        let base = URL(string: "https://research.example.invalid/start")!
        try await load(base)
        try check(probe.actions.last?.mode == .mobile, "real navigation callback manual default mobile")
        let mobileEffective = probe.effectiveMode?.rawValue ?? -1
        #if os(iOS)
        try check(probe.effectiveMode == .mobile, "iOS rendered mobile mode")
        #endif
        let cookie = HTTPCookie(properties: [.domain: "research.example.invalid", .path: "/", .name: "site_mode_fixture", .value: "synthetic"])!
        await store.httpCookieStore.setCookie(cookie)
        let originalView = browser.webView
        let snapshot = try await browser.snapshotControls()
        let control = snapshot.controls.first { $0.label == "Local action" }!
        let proposal = try browser.proposeInteraction(.init(documentID: snapshot.documentID, snapshotID: snapshot.snapshotID,
                                                          kind: .click, controlID: control.id))
        let beforeChoice = probe.actions.count
        let finishedBeforeChoice = probe.finishes
        try check(workspace.setManualSiteMode(.desktop), "actual UI entry saves desktop")
        try check(browser.interactionProposal == nil && browser.controlSnapshot == nil, "pending approval cancelled")
        browser.approveInteraction(id: proposal.id)
        do {
            try await wait("GET mode reload action", { probe.actions.count == beforeChoice + 1 && !browser.webView.isLoading })
        } catch {
            throw Failure(check: "GET reload: events=\(probe.events); notice=\(workspace.siteModeNotice ?? "nil"); status=\(browser.status); error=\(browser.error ?? "nil"); finishes=\(probe.finishes)")
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.count == beforeChoice + 1 && probe.finishes == finishedBeforeChoice,
                  "workspace issues exactly one real reload action (probe cancels before network)")
        try check(probe.actions.last?.type == .reload && probe.actions.last?.method == "GET" && probe.actions.last?.mode == .desktop,
                  "actual reload request is GET with new preference")
        try check(browser.webView === originalView, "reload keeps same WebView")
        try check(browser.interactionProposal == nil && browser.interactionError != nil, "old proposal remains rejected")
        try check(workspace.siteModeNotice?.contains("正在重新整理") == true, "GET immediate apply notice")
        // Synthetic responses cannot serve a subsequent network reload. This
        // fixture intercepts that action; runHTTPFixture proves actual GET
        // completion against the existing gated HTTP server, including cookies.
        try await load(base)
        let cookies = await store.httpCookieStore.allCookies()
        try check(cookies.contains { $0.name == cookie.name && $0.value == cookie.value }, "same profile retains synthetic cookie")
        try check((browser.webView.customUserAgent ?? "").isEmpty, "no UA spoofing")
        try check(browser.manualSiteMode("child.research.example.invalid") == .desktop, "live resolver inherits")
        try check(workspace.library.tabs.count == 1 && workspace.downloads.items.isEmpty, "tabs and downloads retained")
        let ciphertext = try Data(contentsOf: file)
        try check(!String(decoding: ciphertext, as: UTF8.self).contains("research.example.invalid"), "host encrypted on disk")
        let reopened = BrowserWorkspace(dataStore: store, vault: vault(), downloadDirectory: root.appendingPathComponent("Downloads"))
        try check(reopened.available && reopened.library == workspace.library, "actual encrypted workspace restart")
        try check(reopened.selected.manualSiteMode("research.example.invalid") == .desktop, "restored session wired to persisted choice")
        let originalLibrary = workspace.library
        keys.unavailable = true
        try check(!workspace.setManualSiteMode(.mobile) && workspace.library == originalLibrary, "failed write preserves visible choice")
        try check(try Data(contentsOf: file) == ciphertext, "failed write preserves ciphertext")
        keys.unavailable = false
        try await load(URL(string: "https://child.research.example.invalid/inherited")!)
        try check(probe.actions.last?.mode == .desktop, "real navigation applies inherited desktop")
        #if os(iOS)
        try check(probe.effectiveMode == .desktop, "iOS rendered desktop mode")
        #endif
        let desktopEffective = probe.effectiveMode?.rawValue ?? -1
        let beforeFrame = probe.actions.count
        _ = try await browser.webView.evaluateJavaScript("const frame=document.createElement('iframe'); frame.src='https://child.research.example.invalid/frame'; document.body.appendChild(frame); true")
        try await wait("subframe policy", { probe.actions.count > beforeFrame })
        try check(probe.actions.last?.main == false && probe.actions.last?.mode == probe.actions.last?.incomingMode,
                  "subframe preferences left unchanged")
        try await load(base)
        browser.refreshControls()
        try await wait("automation ownership", { browser.automationOwnsDocument && !browser.isInteracting && browser.controlSnapshot != nil })
        try await load(URL(string: "https://research.example.invalid/agent")!, manually: false)
        try check(probe.actions.last?.mode == .recommended, "automation uses existing independent recommended policy")
        let agentActions = probe.actions.count
        try check(workspace.setManualSiteMode(.mobile) && browser.automationOwnsDocument, "preference cannot release automated document")
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.count == agentActions && workspace.siteModeNotice?.contains("下次手動導覽") == true,
                  "automation document never automatically reloads")
        for (id, method) in [("query", "GET"), ("cross", "GET"), ("private", "GET"), ("post", "POST"), ("download", "GET")] {
            let previous = probe.actions.count
            _ = try await browser.webView.evaluateJavaScript(id == "post" ? "document.getElementById('post').requestSubmit(); true" : "document.getElementById('\(id)').click(); true")
            try await wait("restricted action " + id, { probe.actions.count > previous })
            try check(probe.actions.last?.policy == .cancel && probe.actions.last?.method == method, "new delegate retains gate " + id)
        }
        try await load(base)
        try check(!browser.automationOwnsDocument && probe.actions.last?.mode == .mobile, "explicit manual commit restores manual mobile")
        let beforeDownload = probe.actions.count
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('download').click(); true")
        try await wait("manual download policy", { probe.actions.count > beforeDownload })
        try check(probe.actions.last?.policy == .download, "manual download gate preserved in preferences delegate")
        let previous = probe.actions.count
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('post').requestSubmit(); true")
        try await wait("actual manual POST action", { probe.actions.count > previous })
        try check(probe.actions.last?.method == "POST" && probe.actions.last?.policy == .allow, "manual POST policy preserved (fixture intercepts request)")
        // This is an actual WebKit POST action, cancelled by the test probe
        // before network. Choosing a mode must not replay that action.
        let afterPost = probe.actions.count
        try await wait("intercepted POST settled", { !browser.webView.isLoading })
        try check(workspace.setManualSiteMode(.desktop), "choice after intercepted POST")
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.count == afterPost, "no automatic POST or navigation replay")
        try check(workspace.setManualSiteMode(.mobile), "mobile reset")
        try check(workspace.library.userSiteModes.mode(for: "child.research.example.invalid") == .mobile, "persisted inherited reset")
        // A real completed POST navigation at the SAME URL as the preceding GET.
        // WebKit's public simulated-response API supplies controlled HTML bytes;
        // request method and all navigation lifecycle callbacks are actual WebKit.
        try await load(base, method: "POST")
        try check(probe.actions.last?.method == "POST" && probe.actions.last?.policy == .allow, "POST document actually commits and finishes")
        let postActions = probe.actions.count, postFinishes = probe.finishes, postNavigation = probe.lastNavigation
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('input').value='keep POST document'; true")
        try check(workspace.setManualSiteMode(.desktop), "save choice on completed POST document")
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(probe.actions.count == postActions && probe.finishes == postFinishes && probe.lastNavigation === postNavigation,
                  "completed POST never replayed or replaced with GET")
        let postNote = try await browser.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        try check(postNote == "keep POST document" && workspace.siteModeNotice?.contains("下次手動導覽") == true,
                  "POST keeps current document and clear deferred notice")
        try await load(base, observePolicy: false)
        let unknownActions = probe.actions.count, unknownFinishes = probe.finishes
        try check(workspace.setManualSiteMode(.mobile), "save choice on unknown-method document")
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.count == unknownActions && probe.finishes == unknownFinishes
                  && workspace.siteModeNotice?.contains("下次手動導覽") == true, "unknown evidence never automatically reloads")
        workspace.newTab()
        try check(workspace.library.tabs.count == 2 && workspace.selected.webView.configuration.websiteDataStore === store,
                  "new tab shares profile")
        try check(workspace.selected.manualSiteMode("research.example.invalid") == .mobile, "new tab resolves current choices")
        struct LegacyLibrary: Encodable {
            let version = 1
            let tabs: [BrowserTab]
            let selectedID: UUID
            let bookmarks: [BrowserSavedPage]
            let history: [BrowserSavedPage]
        }
        let legacyFile = root.appendingPathComponent("legacy.vault")
        let legacyVault = EncryptedLearningFile(url: legacyFile, keys: keys)
        _ = try legacyVault.load(BrowserLibraryState.self)
        let state = workspace.library
        try legacyVault.save(LegacyLibrary(tabs: state.tabs, selectedID: state.selectedID,
                                           bookmarks: state.bookmarks, history: state.history))
        let migrated = BrowserWorkspace(dataStore: store,
            vault: EncryptedLearningFile(url: legacyFile, keys: keys), downloadDirectory: root.appendingPathComponent("LegacyDownloads"))
        try check(migrated.available && migrated.library.tabs == state.tabs && migrated.library.history == state.history
                  && migrated.library.bookmarks == state.bookmarks && migrated.library.selectedID == state.selectedID,
                  "legacy encrypted library migrates without metadata loss")
        try check(migrated.library.userSiteModes.desktopHosts.isEmpty, "legacy encrypted library starts mobile")
        // Corrupt ciphertext: fail closed and leave original bytes untouched.
        try Data("corrupt fixture".utf8).write(to: file)
        let corrupt = BrowserWorkspace(dataStore: store, vault: vault(), downloadDirectory: root.appendingPathComponent("OtherDownloads"))
        try check(!corrupt.available && !corrupt.setManualSiteMode(.desktop), "corrupt encrypted vault unavailable")
        try check(try Data(contentsOf: file) == Data("corrupt fixture".utf8), "corrupt vault not overwritten")
        return ["assertions": count, "actual_webkit": true, "mobile_effective_raw": mobileEffective,
                "desktop_effective_raw": desktopEffective, "post_network_sent": false, "completed_simulated_post": true,
                "explicit_get_reload_actions": 1, "post_replay_count": 0,
                "external_network_or_personal_keychain": false]
    }

    #if DEBUG
    static func runHTTPFixture() async throws -> [String: Any] {
        guard let fixture = BrowserLoginFixture.enabled else { throw Failure(check: "existing HTTP fixture flags required") }
        let statusURL = try await fixture.start()
        defer { fixture.stop() }
        let browser = BrowserSession(dataStore: .nonPersistent())
        let host = try Host(); defer { browser.cancel(); host.close() }
        let probe = Probe(browser); probe.allowsNetworkFixture = fixture.allows
        host.attach(browser); browser.webView.navigationDelegate = probe
        var mode = BrowserManualSiteMode.mobile
        browser.manualSiteMode = { _ in mode }
        var count = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw Failure(check: name) }; count += 1
        }
        func body() async throws -> String { try await browser.webView.evaluateJavaScript("document.body.innerText") as? String ?? "" }
        func open(_ url: URL) async throws {
            let before = probe.finishes
            browser.address = url.absoluteString; browser.openAddress()
            try await wait("HTTP page", { probe.finishes == before + 1 && browser.loadedURL == url && !browser.webView.isLoading })
        }
        try await open(statusURL)
        let beforeLogin = probe.finishes
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('username').value='\(BrowserLoginFixture.username)'; document.getElementById('password').value='\(BrowserLoginFixture.password)'; document.querySelector('form').requestSubmit(); true")
        let protectedURL = statusURL.deletingLastPathComponent().appendingPathComponent("protected")
        try await wait("HTTP login and redirect", { probe.finishes == beforeLogin + 1 && browser.loadedURL == protectedURL && !browser.webView.isLoading })
        let authenticated = try await body()
        try check(authenticated.contains("LOGIN_PROTECTED_AUTHENTICATED") && authenticated.contains("LOGIN_SERVER_LOGINS_1"),
                  "synthetic server received one actual login POST and authenticated redirect GET")
        mode = .desktop
        let redirectActions = probe.actions.count
        try check(!browser.manualSiteModeDidChange(applyToCurrentDocument: true), "POST/redirect chain is deferred")
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.count == redirectActions, "POST/redirect has no replay")
        mode = .mobile
        try await open(protectedURL)
        let before = try await body()
        try check(before.contains("LOGIN_PROTECTED_CHECKS_2"), "fresh explicit GET document has server counter two")
        let getActions = probe.actions.count, getFinishes = probe.finishes, oldNavigation = probe.lastNavigation
        let originalView = browser.webView
        mode = .desktop
        try check(browser.manualSiteModeDidChange(applyToCurrentDocument: true), "known HTTP GET applies immediately")
        try await wait("actual HTTP reload completed", { probe.finishes == getFinishes + 1 && !browser.webView.isLoading })
        try await Task.sleep(nanoseconds: 200_000_000)
        let reloaded = try await body()
        try check(probe.actions.count == getActions + 1 && probe.finishes == getFinishes + 1,
                  "one actual GET reload and one completed document")
        try check(probe.actions.last?.type == .reload && probe.actions.last?.method == "GET" && probe.actions.last?.mode == .desktop,
                  "actual HTTP reload uses GET and desktop preference")
        try check(reloaded.contains("LOGIN_PROTECTED_CHECKS_3") && reloaded.contains("LOGIN_PROTECTED_AUTHENTICATED")
                  && reloaded.contains("LOGIN_SERVER_LOGINS_1"), "server saw exactly one more GET with retained HttpOnly cookie and no repeated login POST")
        try check(browser.webView === originalView && probe.lastNavigation !== oldNavigation, "same WebView with a new real HTTP document")
        #if os(iOS)
        try check(probe.effectiveMode == .desktop, "native HTTP reload effective desktop mode")
        #endif
        // Submit invalid synthetic fields: existing fixture replies 401 to the
        // POST itself, without a redirect. No personal account or credentials.
        let loginURL = statusURL.deletingLastPathComponent().appendingPathComponent("login")
        let beforePost = probe.finishes
        _ = try await browser.webView.evaluateJavaScript("const f=document.createElement('form'); f.method='POST'; f.action='\(loginURL.absoluteString)'; for (const name of ['username','password']) { const i=document.createElement('input'); i.name=name; i.value='synthetic-invalid'; f.appendChild(i); } document.body.appendChild(f); f.requestSubmit(); true")
        try await wait("completed HTTP POST document", { probe.finishes == beforePost + 1 && browser.loadedURL == loginURL && !browser.webView.isLoading })
        let rejected = try await body()
        try check(probe.actions.last?.method == "POST" && rejected.contains("LOGIN_CREDENTIALS_REJECTED"), "actual HTTP POST response committed without redirect")
        let postActions = probe.actions.count, postFinishes = probe.finishes, postNavigation = probe.lastNavigation
        mode = .mobile
        try check(!browser.manualSiteModeDidChange(applyToCurrentDocument: true), "completed HTTP POST stays deferred")
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(probe.actions.count == postActions && probe.finishes == postFinishes && probe.lastNavigation === postNavigation,
                  "no POST resubmission or replacement GET")
        let postsBeforeStop = probe.actions.filter { $0.method == "POST" }.count
        fixture.setHoldStatus(true)
        browser.manualNavigation(to: statusURL) { browser.webView.load(URLRequest(url: statusURL)) }
        try await wait("held GET after POST document", { fixture.heldStatusCount > 0 && browser.isPageLoading })
        try check(browser.stopManualPageLoading(), "stop while POST document is visible")
        fixture.setHoldStatus(false)
        try await wait("stopped GET after POST is idle", { !browser.webView.isLoading && !browser.isPageLoading })
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(probe.actions.filter { $0.method == "POST" }.count == postsBeforeStop && browser.webView === originalView,
                  "stop does not replay the visible POST document")

        // The server holds an actual HTTP response while both sessions remain
        // isolated from the user's profile and the rest of the network.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-stop-load-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(),
            vault: EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: SiteModeKeys()),
            downloadDirectory: root.appendingPathComponent("downloads"))
        defer { workspace.cancelAllWork(); fixture.setHoldStatus(false) }
        let selected = workspace.selected, selectedProbe = Probe(workspace.selected)
        selectedProbe.allowsNetworkFixture = fixture.allows
        host.attach(selected); selected.webView.navigationDelegate = selectedProbe
        workspace.activateSelected()
        try await wait("workspace initial page", { selectedProbe.finishes > 0 && selected.loadedURL == statusURL && !selected.isPageLoading })
        let oldID = workspace.library.selectedID
        let statusBeforeIdle = selected.status
        try check(!selected.stopManualPageLoading() && selected.status == statusBeforeIdle, "idle stop is a no-op")
        fixture.setHoldStatus(true)
        let completedBeforeStop = selectedProbe.finishes
        selected.reloadPage()
        try check(selected.isPageLoading, "manual reload immediately publishes loading")
        try await wait("held actual HTTP response", { fixture.heldStatusCount > 0 && selected.webView.isLoading && selected.isPageLoading })
        workspace.newTab()
        let other = workspace.selected
        try check(other !== selected && !other.isPageLoading && !other.stopManualPageLoading(), "new tab has independent idle state")
        try check(!selected.stopManualPageLoading() && selected.webView.isLoading, "hidden tab cannot be stopped")
        workspace.selectTab(oldID)
        try check(workspace.selected === selected && selected.isPageLoading, "returning to tab retains its loading state")
        try check(selected.stopManualPageLoading() && selected.manualLoadStopped && !selected.isPageLoading, "stop cancels selected manual load")
        fixture.setHoldStatus(false)
        try await wait("stopped WebKit becomes idle", { !selected.webView.isLoading && !selected.isPageLoading })
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(selectedProbe.finishes == completedBeforeStop && selected.manualLoadStopped && selected.error == nil,
                  "released late response does not finish or replace stopped status")
        try check(!selected.stopManualPageLoading(), "repeated stop is a no-op")
        selected.reloadPage()
        try await wait("manual reload after stop", { selectedProbe.finishes > completedBeforeStop && !selected.isPageLoading })
        try check(!selected.manualLoadStopped && selected.loadedURL == statusURL, "fresh navigation works after stop")

        // Hold a real WebKit response-policy callback, not just server bytes.
        // Release it after stop and again while a newer navigation is in flight.
        let attachmentURL = statusURL.deletingLastPathComponent().appendingPathComponent("attachment")
        let failedBefore = selectedProbe.failures
        selected.manualNavigation(to: attachmentURL) { selected.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("current rejected attachment fails", { selectedProbe.failures > failedBefore && !selected.isPageLoading })
        try check(selected.error != nil && !selected.manualLoadStopped, "current rejection still reports failure")
        selected.reloadPage()
        try await wait("restore after current rejection", { selected.loadedURL == statusURL && !selected.isPageLoading })
        for newerNavigation in [false, true] {
            selectedProbe.deferResponseURL = attachmentURL
            selected.manualNavigation(to: attachmentURL) { selected.webView.load(URLRequest(url: attachmentURL)) }
            try await wait("real attachment policy held", { selectedProbe.deferredResponse != nil && selected.isPageLoading })
            let stoppedNavigation = selectedProbe.lastStarted!
            try check(selected.stopManualPageLoading() && selected.manualLoadStopped, "stop while response decision held")
            if newerNavigation {
                fixture.setHoldStatus(true)
                selected.reloadPage()
                // reloadPage targets the old visible document in this scenario.
                try await wait("new navigation held", { fixture.heldStatusCount > 0 && selected.isPageLoading })
            }
            // Re-deliver old lifecycle events with the real stopped navigation.
            selected.webView(selected.webView, didStartProvisionalNavigation: stoppedNavigation)
            selected.webView(selected.webView, didCommit: stoppedNavigation)
            selected.webView(selected.webView, didFinish: stoppedNavigation)
            selected.webView(selected.webView, didFail: stoppedNavigation, withError: URLError(.cancelled))
            if newerNavigation {
                try check(selected.isPageLoading && selected.error == nil, "late stopped lifecycle callbacks leave new load intact")
            } else {
                try check(selected.manualLoadStopped && selected.error == nil, "late stopped lifecycle callbacks preserve stop")
            }
            let release = selectedProbe.deferredResponse!
            selectedProbe.deferredResponse = nil
            release()
            if newerNavigation {
                try check(selected.isPageLoading && selected.error == nil, "late attachment response does not invalidate new navigation")
                let before = selectedProbe.finishes
                fixture.setHoldStatus(false)
                try await wait("new navigation completes after late policy", { selectedProbe.finishes > before && selected.loadedURL == statusURL && !selected.isPageLoading })
                try check(selected.error == nil && !selected.manualLoadStopped, "new page remains usable")
            } else {
                try check(selected.manualLoadStopped && selected.error == nil, "late attachment response preserves stopped state")
                selected.reloadPage()
                try await wait("restore after stopped policy", { selected.loadedURL == statusURL && !selected.isPageLoading })
            }
        }

        fixture.setHoldStatus(true)
        workspace.newTab()
        let firstLoad = workspace.selected, firstID = workspace.library.selectedID
        let firstProbe = Probe(firstLoad); firstProbe.allowsNetworkFixture = fixture.allows
        host.attach(firstLoad); firstLoad.webView.navigationDelegate = firstProbe
        firstLoad.address = statusURL.absoluteString; firstLoad.openAddress()
        try await wait("held first navigation", { fixture.heldStatusCount > 0 && firstLoad.isPageLoading })
        let firstActions = firstProbe.actions.count
        workspace.selectTab(oldID); workspace.selectTab(firstID)
        try check(firstLoad.isPageLoading && firstProbe.actions.count == firstActions,
                  "returning during first load does not start it again")
        try check(firstLoad.stopManualPageLoading(), "first navigation can be stopped")
        workspace.selectTab(oldID); workspace.selectTab(firstID)
        fixture.setHoldStatus(false)
        try await wait("stopped first navigation becomes idle", { !firstLoad.webView.isLoading && !firstLoad.isPageLoading })
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(firstLoad.manualLoadStopped && firstLoad.loadedURL == nil && firstProbe.finishes == 0 && firstProbe.actions.count == firstActions,
                  "tab switches do not restart a stopped first navigation")
        // This baseline keeps the original view: verify what the broad
        // quarantine candidate would remove, using actual WebKit history and a
        // new user-requested synthetic form POST after a stop.
        workspace.selectTab(oldID)
        let retainedView = selected.webView
        selected.address = protectedURL.absoluteString; selected.openAddress()
        try await wait("post-stop new page", { selected.loadedURL == protectedURL && !selected.isPageLoading })
        try check(selected.webView === retainedView && selected.webView.canGoBack, "old view and back history retained")
        selected.goBack()
        try await wait("post-stop back", { selected.loadedURL == statusURL && !selected.isPageLoading })
        try check(selected.webView.canGoForward, "forward history retained")
        selected.goForward()
        try await wait("post-stop forward", { selected.loadedURL == protectedURL && !selected.isPageLoading })
        selected.goBack()
        try await wait("return to form", { selected.loadedURL == statusURL && !selected.isPageLoading })
        let postCount = selectedProbe.actions.filter { $0.method == "POST" }.count
        _ = try await selected.webView.evaluateJavaScript("document.getElementById('username').value='\(BrowserLoginFixture.username)'; document.getElementById('password').value='\(BrowserLoginFixture.password)'; document.querySelector('form').requestSubmit(); true")
        try await wait("new post-stop form submission", { selected.loadedURL == protectedURL && !selected.isPageLoading })
        try check(selected.webView === retainedView && selectedProbe.actions.filter { $0.method == "POST" }.count == postCount + 1,
                  "new user-requested form POST works exactly once in old view")
        return ["assertions": count, "actual_webkit": true, "actual_loopback_http": true,
                "completed_get_reloads": 1, "additional_server_gets": 1, "post_replays": 0,
                "post_stop_original_view_back_forward_and_explicit_form_post": true,
                "retained_cookie_authenticated_by_server": true, "external_network_or_personal_keychain": false]
    }
    // The proxy holds genuine WebKit policy objects; this controlled order is
    // not a claim that WebKit naturally delivers this order on iOS.
    static func runRedirectStopDiagnostic() async throws -> [String: Any] {
        guard let fixture = BrowserDownloadedPDFFixture.enabled else { throw Failure(check: "PDF fixture flags required") }
        let pageURL = try await fixture.start(); defer { fixture.stop() }
        let attachmentURL = pageURL.deletingLastPathComponent().appendingPathComponent("file.pdf")
        let redirectURL = pageURL.deletingLastPathComponent().appendingPathComponent("redirect-to-file")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-stop-redirect-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(),
            vault: EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: SiteModeKeys()),
            downloadDirectory: root.appendingPathComponent("downloads"))
        let host = try Host(); defer { host.close(); workspace.cancelAllWork() }
        let browser = workspace.selected, probe = Probe(workspace.selected)
        probe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(browser); browser.webView.navigationDelegate = probe
        probe.deferResponseURL = attachmentURL
        browser.manualNavigation(to: attachmentURL) { browser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("old real PDF policy held", { probe.deferredResponse != nil && browser.isPageLoading })
        let oldResponse = probe.deferredResponse!; probe.deferredResponse = nil
        guard browser.stopManualPageLoading() else { throw Failure(check: "stop old PDF") }
        probe.deferResponseURL = attachmentURL
        browser.manualNavigation(to: redirectURL) { browser.webView.load(URLRequest(url: redirectURL)) }
        try await wait("new redirected PDF policy held", { probe.deferredResponse != nil && browser.isPageLoading })
        let newResponse = probe.deferredResponse!; probe.deferredResponse = nil
        oldResponse()
        guard probe.deferredPolicies.count == 1 else { throw Failure(check: "old policy delivered") }
        let oldPolicy = probe.deferredPolicies[0]
        guard oldPolicy == .cancel, browser.downloadRecovery != nil else { throw Failure(check: "old redirected response must be quarantined") }
        let staleOffer = browser.downloadRecoveryOffers[0]
        newResponse()
        guard probe.deferredPolicies.count == 2, probe.deferredPolicies[1] == .cancel,
              browser.downloadRecoveryOffers.count == 2,
              browser.downloadRecoveryOffers[0].id == staleOffer.id else {
            throw Failure(check: "overlapping redirected responses retained as separate untrusted offers")
        }
        browser.dismissDownloadRecovery(id: staleOffer.id)
        guard let offer = browser.downloadRecoveryOffers.first else { throw Failure(check: "new redirected offer lost") }
        browser.confirmDownloadRecovery(id: offer.id)
        browser.confirmDownloadRecovery(id: offer.id)
        try await wait("new redirected download completes", { workspace.downloads.items.contains { $0.status == .completed } })
        guard let item = workspace.downloads.items.first(where: { $0.status == .completed }),
              let file = try? workspace.downloads.fileURL(id: item.id),
              let contents = try? Data(contentsOf: file), contents == BrowserDownloadedPDFFixture.payload else {
            throw Failure(check: "downloaded fixture bytes")
        }
        return ["different_initial_urls": true, "same_response_url_after_redirect": true,
                "old_response_policy_cancel": true, "new_isolated_get_completed": true,
                "actual_webkit": true, "actual_loopback_http": true,
                "callback_order_injected_by_proxy": true, "native_ios_execution": false]
    }

    // Two real WebKit action objects are held by the proxy and delivered old-first.
    // Their provenance is deliberately never inferred from that test ordering.
    static func runDistinctActionOverlap() async throws {
        guard let fixture = BrowserDownloadedPDFFixture.enabled else { throw Failure(check: "fixture required") }
        let pageURL = try await fixture.start(); defer { fixture.stop() }
        let oldURL = pageURL.deletingLastPathComponent().appendingPathComponent("file.pdf")
        let newURL = pageURL.deletingLastPathComponent().appendingPathComponent("other.pdf")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-distinct-action-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(),
            vault: EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: SiteModeKeys()),
            downloadDirectory: root.appendingPathComponent("downloads"))
        let host = try Host(); defer { host.close(); workspace.cancelAllWork() }
        let browser = workspace.selected, probe = Probe(workspace.selected)
        probe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(browser); browser.webView.navigationDelegate = probe
        browser.manualNavigation(to: pageURL) { browser.webView.load(URLRequest(url: pageURL)) }
        try await wait("distinct action page", { probe.finishes > 0 && !browser.isPageLoading })
        probe.holdNextDownloadAction = true
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('a[download]').click(); true")
        try await wait("old action held", { probe.deferredDownloadAction != nil })
        let oldAction = probe.deferredDownloadAction!; probe.deferredDownloadAction = nil
        probe.deferResponseURL = oldURL
        browser.manualNavigation(to: oldURL) { browser.webView.load(URLRequest(url: oldURL)) }
        try await wait("response held before stop", { probe.deferredResponse != nil && browser.isPageLoading })
        guard browser.stopManualPageLoading() else { throw Failure(check: "stop before distinct action") }
        let stoppedResponse = probe.deferredResponse!; probe.deferredResponse = nil
        stoppedResponse()
        probe.holdNextDownloadAction = true
        _ = try await browser.webView.evaluateJavaScript("const a=document.createElement('a');a.href='\(newURL.absoluteString)';a.download='fresh.pdf';document.body.appendChild(a);a.click();true")
        try await wait("new distinct action held", { probe.deferredDownloadAction != nil })
        let newAction = probe.deferredDownloadAction!; probe.deferredDownloadAction = nil
        oldAction(); newAction()
        guard probe.deliveredActionPolicies == [.cancel, .cancel], browser.downloadRecoveryOffers.count == 2,
              browser.downloadRecoveryOffers.map(\.url) == [oldURL, newURL], workspace.downloads.items.isEmpty else {
            throw Failure(check: "distinct old/new offers are both retained without authorization")
        }
        let oldOffer = browser.downloadRecoveryOffers[0], newOffer = browser.downloadRecoveryOffers[1]
        let before = fixture.transferCount
        browser.confirmDownloadRecovery(id: oldOffer.id)
        browser.confirmDownloadRecovery(id: oldOffer.id)
        guard browser.downloadRecoveryOffers.map(\.id) == [newOffer.id] else { throw Failure(check: "new offer lost after confirming old") }
        try await wait("old explicit GET completes", { workspace.downloads.items.filter { $0.status == .completed }.count == 1 })
        guard browser.downloadRecoveryOffers.map(\.id) == [newOffer.id], fixture.transferCount == before + 1 else {
            throw Failure(check: "new offer changed or unexpected GET")
        }
        browser.confirmDownloadRecovery(id: newOffer.id)
        browser.confirmDownloadRecovery(id: newOffer.id)
        try await wait("distinct new explicit GET completes", { workspace.downloads.items.filter { $0.status == .completed }.count == 2 })
        guard fixture.transferCount == before + 2, browser.downloadRecoveryOffers.isEmpty else {
            throw Failure(check: "duplicate confirmation or remaining offers")
        }
        // Bound callback storage and retain a visible warning without network I/O.
        let issuers = (0..<17).map { _ in NSObject() }
        for issuer in issuers { browser.testOfferDownloadRecovery(oldURL, issuer: issuer) }
        guard browser.downloadRecoveryOffers.count == 16, browser.downloadRecoveryOverflow,
              browser.downloadRecovery != nil else { throw Failure(check: "overflow must be visible") }
        let offers = browser.downloadRecoveryOffers
        browser.dismissDownloadRecovery(id: offers[0].id)
        guard browser.downloadRecoveryOverflow, browser.downloadRecoveryOffers.count == 15 else {
            throw Failure(check: "overflow warning lost after one dismissal")
        }
        let tabID = workspace.library.selectedID
        workspace.newTab()
        guard browser.downloadRecoveryOffers.isEmpty, !browser.downloadRecoveryOverflow,
              browser.downloadRecovery == nil else { throw Failure(check: "tab switch retained multiple offers") }
        workspace.selectTab(tabID)
        browser.confirmDownloadRecovery(id: offers[1].id)
        guard fixture.transferCount == before + 2 else { throw Failure(check: "revoked offer started a GET") }
        print("DISTINCT_ACTION_OVERLAP both_untrusted_offers_retained=true explicit_gets=2")
    }

    // Same URL needs a new explicit GET once the old view has been stopped.
    // The proxy retains real WebKit response objects and controls when the app
    // sees them. It does not establish that iOS naturally delivers this order.
    static func runSameURLStopRegression() async throws -> [String: Any] {
        guard let fixture = BrowserDownloadedPDFFixture.enabled else { throw Failure(check: "PDF fixture flags required") }
        let pageURL = try await fixture.start(); defer { fixture.stop() }
        let attachmentURL = pageURL.deletingLastPathComponent().appendingPathComponent("file.pdf")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-stop-same-url-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(),
            vault: EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: SiteModeKeys()),
            downloadDirectory: root.appendingPathComponent("downloads"))
        let host = try Host(); defer { host.close(); workspace.cancelAllWork() }
        let browser = workspace.selected, probe = Probe(workspace.selected)
        probe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(browser); browser.webView.navigationDelegate = probe
        func start() {
            probe.deferResponseURL = attachmentURL
            browser.manualNavigation(to: attachmentURL) { browser.webView.load(URLRequest(url: attachmentURL)) }
        }
        start()
        try await wait("first real PDF policy held", { probe.deferredResponse != nil && browser.isPageLoading })
        let oldResponse = probe.deferredResponse!; probe.deferredResponse = nil
        guard browser.stopManualPageLoading() else { throw Failure(check: "stop first PDF") }
        start()
        try await wait("second real PDF policy held", { probe.deferredResponse != nil && browser.isPageLoading })
        let newResponse = probe.deferredResponse!; probe.deferredResponse = nil
        oldResponse()
        guard probe.deferredPolicies.count == 1 else { throw Failure(check: "old policy was not delivered") }
        let oldPolicy = probe.deferredPolicies[0]
        guard oldPolicy == .cancel, browser.downloadRecovery != nil else { throw Failure(check: "old response was not quarantined") }
        browser.dismissDownloadRecoveryOffers()
        newResponse()
        guard probe.deferredPolicies.count == 2, probe.deferredPolicies[1] == .cancel,
              let offer = browser.downloadRecovery else {
            throw Failure(check: "new user-requested same-URL response requires explicit GET")
        }
        browser.confirmDownloadRecovery(id: offer.id)
        browser.confirmDownloadRecovery(id: offer.id)
        try await wait("legitimate same-URL download completes", {
            workspace.downloads.items.contains { $0.status == .completed }
        })
        guard let item = workspace.downloads.items.first(where: { $0.status == .completed }),
              let file = try? workspace.downloads.fileURL(id: item.id),
              let contents = try? Data(contentsOf: file), contents == BrowserDownloadedPDFFixture.payload else {
            throw Failure(check: "legitimate download bytes")
        }
        // Test the isolation premise separately: the stopped response belongs
        // to a different, quarantined WebView/session from the new request.
        workspace.newTab()
        let oldBrowser = workspace.selected, oldProbe = Probe(workspace.selected)
        oldProbe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(oldBrowser); oldBrowser.webView.navigationDelegate = oldProbe
        oldProbe.deferResponseURL = attachmentURL
        oldBrowser.manualNavigation(to: attachmentURL) { oldBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("isolated old PDF policy held", { oldProbe.deferredResponse != nil && oldBrowser.isPageLoading })
        let isolatedOldResponse = oldProbe.deferredResponse!; oldProbe.deferredResponse = nil
        guard oldBrowser.stopManualPageLoading() else { throw Failure(check: "stop isolated PDF") }
        workspace.newTab()
        let newBrowser = workspace.selected, newProbe = Probe(workspace.selected)
        guard oldBrowser.webView !== newBrowser.webView else { throw Failure(check: "isolated view identity") }
        newProbe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(newBrowser); newBrowser.webView.navigationDelegate = newProbe
        newProbe.deferResponseURL = attachmentURL
        newBrowser.manualNavigation(to: attachmentURL) { newBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("isolated new PDF policy held", { newProbe.deferredResponse != nil && newBrowser.isPageLoading })
        let isolatedNewResponse = newProbe.deferredResponse!; newProbe.deferredResponse = nil
        isolatedOldResponse()
        isolatedNewResponse()
        guard oldProbe.deferredPolicies == [.cancel], newProbe.deferredPolicies == [.download], oldBrowser.manualLoadStopped else {
            throw Failure(check: "isolated view policies or stopped state")
        }
        try await wait("isolated legitimate download completes", {
            workspace.downloads.items.filter { $0.status == .completed }.count == 2
        })
        workspace.newTab()
        let actionBrowser = workspace.selected, actionProbe = Probe(workspace.selected)
        actionProbe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(actionBrowser); actionBrowser.webView.navigationDelegate = actionProbe
        actionBrowser.manualNavigation(to: pageURL) { actionBrowser.webView.load(URLRequest(url: pageURL)) }
        try await wait("download link page", { actionProbe.finishes > 0 && !actionBrowser.isPageLoading })
        func clickDownload() async throws {
            _ = try await actionBrowser.webView.evaluateJavaScript("document.querySelector('a[download]').click(); true")
        }
        try await clickDownload()
        try await wait("ordinary action download before stop", { workspace.downloads.items.filter { $0.status == .completed }.count == 3 })
        actionProbe.holdNextDownload = true
        try await clickDownload()
        try await wait("old real action didBecome held", { actionProbe.deferredDownload != nil })
        let oldDownload = actionProbe.deferredDownload!; actionProbe.deferredDownload = nil
        actionProbe.deferResponseURL = attachmentURL
        actionBrowser.manualNavigation(to: attachmentURL) { actionBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("held policy before stopping action test", { actionProbe.deferredResponse != nil && actionBrowser.isPageLoading })
        guard actionBrowser.stopManualPageLoading() else { throw Failure(check: "stop action test") }
        let oldActionResponse = actionProbe.deferredResponse!; actionProbe.deferredResponse = nil
        oldActionResponse()
        try await Task.sleep(nanoseconds: 300_000_000)
        guard workspace.downloads.items.count == 3, actionBrowser.downloadRecovery == nil else {
            throw Failure(check: "late action didBecome or stopped response was accepted")
        }
        try await clickDownload()
        try await wait("post-stop action confirmation", { actionBrowser.downloadRecovery != nil })
        let actionOffer = actionBrowser.downloadRecovery!
        let transfersBeforeConfirmation = fixture.transferCount
        let managerErrorBeforeLateAction = workspace.downloads.errorMessage
        oldDownload()
        try await Task.sleep(nanoseconds: 200_000_000)
        guard actionBrowser.downloadRecovery?.id == actionOffer.id, workspace.downloads.items.count == 3,
              workspace.downloads.errorMessage == managerErrorBeforeLateAction else {
            throw Failure(check: "late action didBecome affected new confirmation")
        }
        actionBrowser.confirmDownloadRecovery(id: actionOffer.id)
        actionBrowser.confirmDownloadRecovery(id: actionOffer.id)
        try await wait("post-stop action isolated GET", { workspace.downloads.items.filter { $0.status == .completed }.count == 4 })
        try await Task.sleep(nanoseconds: 200_000_000)
        guard workspace.downloads.items.count == 4, fixture.transferCount == transfersBeforeConfirmation + 1 else {
            throw Failure(check: "duplicate confirmation created a download request")
        }
        try await clickDownload()
        try await wait("cancellable action confirmation", { actionBrowser.downloadRecovery != nil })
        let cancelledOffer = actionBrowser.downloadRecovery!
        let transfersBeforeDismissal = fixture.transferCount
        actionBrowser.dismissDownloadRecoveryOffers()
        actionBrowser.confirmDownloadRecovery(id: cancelledOffer.id)
        try await Task.sleep(nanoseconds: 200_000_000)
        guard workspace.downloads.items.count == 4, fixture.transferCount == transfersBeforeDismissal else {
            throw Failure(check: "dismissed offer issued a request")
        }
        try await clickDownload()
        try await wait("tab-switch confirmation", { actionBrowser.downloadRecovery != nil })
        let tabOffer = actionBrowser.downloadRecovery!, actionTabID = workspace.library.selectedID
        workspace.newTab()
        guard actionBrowser.downloadRecovery == nil else { throw Failure(check: "tab switch retained confirmation") }
        actionBrowser.confirmDownloadRecovery(id: tabOffer.id)
        workspace.selectTab(actionTabID)
        try await wait("action page selected again", { workspace.selected === actionBrowser && actionBrowser.loadedURL == pageURL && !actionBrowser.isPageLoading })
        guard workspace.downloads.items.count == 4 else { throw Failure(check: "tab-switched offer was accepted") }
        try await clickDownload()
        try await wait("close-page action confirmation", { actionBrowser.downloadRecovery != nil })
        let closingOffer = actionBrowser.downloadRecovery!
        var heldHandoff: (() -> Void)?
        var rejectedAfterClose = false
        actionBrowser.deferIsolatedDownloadHandoff = { heldHandoff = $0 }
        actionBrowser.onIsolatedDownloadRejected = { rejectedAfterClose = true }
        actionBrowser.confirmDownloadRecovery(id: closingOffer.id)
        try await wait("actual WebKit isolated handoff held", { heldHandoff != nil })
        guard workspace.closeCurrentPage() else { throw Failure(check: "close page") }
        guard let handoff = heldHandoff else { throw Failure(check: "missing real handoff") }
        handoff()
        guard rejectedAfterClose, workspace.downloads.items.count == 4 else {
            throw Failure(check: "closed page did not synchronously reject held WebKit handoff")
        }
        actionBrowser.deferIsolatedDownloadHandoff = nil
        actionBrowser.onIsolatedDownloadRejected = nil
        workspace.newTab()
        let responseBrowser = workspace.selected, responseProbe = Probe(workspace.selected)
        responseProbe.allowsNetworkFixture = fixture.allowsNavigation
        host.attach(responseBrowser); responseBrowser.webView.navigationDelegate = responseProbe
        responseProbe.holdNextDownload = true
        responseBrowser.manualNavigation(to: attachmentURL) { responseBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("old real response didBecome held", { responseProbe.deferredDownload != nil })
        let lateResponseDownload = responseProbe.deferredDownload!; responseProbe.deferredDownload = nil
        responseProbe.deferResponseURL = attachmentURL
        responseBrowser.manualNavigation(to: attachmentURL) { responseBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("held response before second stop", { responseProbe.deferredResponse != nil && responseBrowser.isPageLoading })
        let stoppedResponse = responseProbe.deferredResponse!; responseProbe.deferredResponse = nil
        guard responseBrowser.stopManualPageLoading() else { throw Failure(check: "stop response didBecome test") }
        responseProbe.deferResponseURL = attachmentURL
        responseBrowser.manualNavigation(to: attachmentURL) { responseBrowser.webView.load(URLRequest(url: attachmentURL)) }
        try await wait("fresh response after second stop", { responseProbe.deferredResponse != nil })
        stoppedResponse()
        let stoppedOffer = responseBrowser.downloadRecovery
        responseBrowser.dismissDownloadRecoveryOffers()
        let freshResponse = responseProbe.deferredResponse!; responseProbe.deferredResponse = nil
        freshResponse()
        guard stoppedOffer != nil, let freshOffer = responseBrowser.downloadRecovery else { throw Failure(check: "both ambiguous responses offered") }
        let managerErrorBeforeLateResponse = workspace.downloads.errorMessage
        lateResponseDownload()
        try await Task.sleep(nanoseconds: 200_000_000)
        guard responseBrowser.downloadRecovery?.id == freshOffer.id, workspace.downloads.items.count == 4,
              workspace.downloads.errorMessage == managerErrorBeforeLateResponse else {
            throw Failure(check: "late response didBecome affected new confirmation")
        }
        responseBrowser.dismissDownloadRecoveryOffers()
        print("REGRESSION positive_new_download=completed old_response_policy=\(oldPolicy == .cancel ? "cancel" : "not_cancel") isolated_views=pass")
        guard oldPolicy == .cancel else { throw Failure(check: "stopped PDF response authorized by later same-URL intent") }
        return ["old_response_cancelled": true, "new_download_completed": true,
                "actual_webkit": true, "actual_loopback_http": true]
    }
    #endif
}

#if BROWSER_SITE_MODE_APP_STANDALONE
@main struct BrowserSiteModeCheckMain {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let result: [String: Any]
                #if DEBUG
                if BrowserDownloadedPDFFixture.enabled != nil && ProcessInfo.processInfo.arguments.contains("-UITestBrowserStopRedirect") {
                    result = try await BrowserSiteModesAppChecks.runRedirectStopDiagnostic()
                }
                else if BrowserDownloadedPDFFixture.enabled != nil && ProcessInfo.processInfo.arguments.contains("-UITestBrowserDistinctActions") {
                    try await BrowserSiteModesAppChecks.runDistinctActionOverlap()
                    result = ["distinct_actions": true, "actual_webkit": true, "native_ios_execution": false]
                }
                else if BrowserDownloadedPDFFixture.enabled != nil { result = try await BrowserSiteModesAppChecks.runSameURLStopRegression() }
                else if BrowserLoginFixture.enabled != nil { result = try await BrowserSiteModesAppChecks.runHTTPFixture() }
                else { result = try await BrowserSiteModesAppChecks.run() }
                #else
                result = try await BrowserSiteModesAppChecks.run()
                #endif
                print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
                exit(0)
            } catch { print("FAIL \(error)"); exit(1) }
        }
        app.run()
    }
}
#endif
