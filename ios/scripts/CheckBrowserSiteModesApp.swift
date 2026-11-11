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
        var responses: [(URL?, WKNavigationResponsePolicy)] = []
        var externallyCancelledURLs: [URL] = []
        var events: [String] = []
        var lastNavigation: WKNavigation?
        var actions: [(host: String?, main: Bool, method: String?, incomingMode: WKWebpagePreferences.ContentMode,
                       mode: WKWebpagePreferences.ContentMode, policy: WKNavigationActionPolicy, type: WKNavigationType)] = []
        init(_ browser: BrowserSession) { self.browser = browser }
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
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
            browser.webView(view, decidePolicyFor: response) { policy in
                self.responses.append((response.response.url, policy))
                decisionHandler(policy)
            }
        }
        func webView(_ view: WKWebView, didStartProvisionalNavigation nav: WKNavigation!) {
            events.append("start")
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
    static func runLANFixture() async throws -> [String: Any] {
        guard BrowserLoginFixture.enabled == nil else { throw Failure(check: "no automatic fixture bypass") }
        func fixture() throws -> BrowserLoginFixture {
            guard let value = BrowserLoginFixture(arguments: ["-UITestMode", "-UITestBrowserLogin", "-UITestNamespace", UUID().uuidString]) else {
                throw Failure(check: "fixture setup")
            }
            return value
        }
        let server = try fixture(), other = try fixture()
        let url = try await server.start(), otherURL = try await other.start()
        defer { server.stop(); other.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-lan-webkit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: SiteModeKeys())
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(), vault: vault, downloadDirectory: root.appendingPathComponent("downloads"))
        let browser = workspace.selected, host = try Host(), probe = Probe(browser)
        defer { workspace.cancelAllWork(); host.close() }
        host.attach(browser); browser.webView.navigationDelegate = probe
        probe.allowsNetworkFixture = server.allows
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw Failure(check: label) }; count += 1
        }
        browser.address = url.absoluteString; browser.openAddress()
        guard let first = browser.pendingLANRequest else { throw Failure(check: "manual approval requested") }
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(server.connectionCount == 0 && !browser.lanBrowsingActive, "no connection before approval")
        browser.rejectPendingLAN(); browser.approvePendingLAN(first)
        try check(browser.pendingLANRequest == nil && server.connectionCount == 0, "rejected request cannot be approved")
        browser.address = url.absoluteString; browser.openAddress()
        guard let request = browser.pendingLANRequest else { throw Failure(check: "second approval requested") }
        browser.approvePendingLAN(first)
        try check(browser.pendingLANRequest == request && server.connectionCount == 0, "stale approval cannot cancel a newer request")
        browser.approvePendingLAN(request)
        try await wait("approved LAN page", { browser.loadedURL == url && !browser.webView.isLoading })
        try check(server.connectionCount > 0 && browser.lanBrowsingActive, "approved real WebKit loopback request")
        try check(browser.current == nil, "local page is not research context")
        try check(workspace.library.tabs.first?.url == nil && workspace.library.history.isEmpty, "local page not persisted")
        let actions = probe.actions.count
        _ = try await browser.webView.evaluateJavaScript("location.href = \(String(data: try JSONEncoder().encode(otherURL.absoluteString), encoding: .utf8)!); true")
        try await wait("cross-origin action", { probe.actions.count > actions })
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(probe.actions.last?.policy == .cancel && other.connectionCount == 0, "cross-origin action denied")
        let redirectURL = url.deletingLastPathComponent().appendingPathComponent("redirect")
        try check(server.setRedirectDestination(url), "same-origin redirect configured")
        let beforeSame = probe.finishes
        browser.manualNavigation(to: redirectURL) { browser.webView.load(URLRequest(url: redirectURL)) }
        try await wait("same-origin redirect", { probe.finishes > beforeSame && browser.loadedURL == url && !browser.webView.isLoading })
        try check(browser.lanBrowsingActive, "same-origin redirect remains authorized")
        try check(server.setRedirectDestination(otherURL), "cross-origin redirect configured")
        let beforeRedirect = probe.actions.count, beforeResponses = probe.responses.count
        browser.manualNavigation(to: redirectURL) { browser.webView.load(URLRequest(url: redirectURL)) }
        try await wait("cross-origin redirect denied", {
            probe.actions.dropFirst(beforeRedirect).contains { $0.policy == .cancel }
                || probe.responses.dropFirst(beforeResponses).contains { $0.0 == otherURL && $0.1 == .cancel }
        })
        let deniedAction = probe.actions.dropFirst(beforeRedirect).contains { $0.policy == .cancel }
        let deniedResponse = probe.responses.dropFirst(beforeResponses).contains { $0.0 == otherURL && $0.1 == .cancel }
        try check(deniedAction || deniedResponse, "cross-origin server redirect denied by navigation policy")
        let redirectedConnections = other.connectionCount
        browser.revokeLANAccess()
        try check(!browser.lanBrowsingActive && browser.loadedURL == nil, "explicit revoke retires the local page")
        browser.approvePendingLAN(request)
        try check(!browser.lanBrowsingActive, "explicit revoke invalidates prior approval")
        host.attach(browser); browser.webView.navigationDelegate = probe
        browser.address = url.absoluteString; browser.openAddress()
        guard let reapproved = browser.pendingLANRequest else { throw Failure(check: "fresh request after revoke") }
        browser.approvePendingLAN(reapproved)
        try await wait("local page after explicit reapproval", { browser.loadedURL == url && !browser.webView.isLoading })
        let originalID = workspace.library.selectedID
        workspace.newTab()
        let secondID = workspace.library.selectedID
        try check(!browser.lanBrowsingActive && browser.loadedURL == nil, "tab switch revokes and discards local page")
        browser.approvePendingLAN(request)
        try check(!browser.lanBrowsingActive, "stale approval cannot revive hidden tab")
        workspace.selectTab(originalID)
        try check(workspace.selected === browser && browser.loadedURL == nil && browser.pendingLANRequest == nil, "return does not reopen local page")
        browser.address = url.absoluteString; browser.openAddress()
        guard let pending = browser.pendingLANRequest else { throw Failure(check: "pending before tab close") }
        workspace.selectTab(secondID); browser.approvePendingLAN(pending)
        try check(browser.pendingLANRequest == nil && !browser.lanBrowsingActive, "switch revokes pending approval")
        workspace.selectTab(originalID)
        host.attach(browser); browser.webView.navigationDelegate = probe
        browser.address = url.absoluteString; browser.openAddress()
        guard let closeRequest = browser.pendingLANRequest else { throw Failure(check: "approval before tab close") }
        browser.approvePendingLAN(closeRequest)
        try await wait("local page before close", { browser.loadedURL == url && !browser.webView.isLoading })
        workspace.closeTab(originalID); browser.approvePendingLAN(closeRequest)
        try check(browser.pendingLANRequest == nil && !browser.lanBrowsingActive && browser.loadedURL == nil, "closing tab revokes active approval")
        return ["assertions": count, "actual_webkit": true, "actual_loopback_http": true,
                "cross_origin_redirect_target_connections": redirectedConnections,
                "external_network_or_personal_keychain": false, "native_ui_execution": false]
    }

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
        return ["assertions": count, "actual_webkit": true, "actual_loopback_http": true,
                "completed_get_reloads": 1, "additional_server_gets": 1, "post_replays": 0,
                "retained_cookie_authenticated_by_server": true, "external_network_or_personal_keychain": false]
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
                if ProcessInfo.processInfo.arguments.contains("-LANPolicyLoopback") { result = try await BrowserSiteModesAppChecks.runLANFixture() }
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
