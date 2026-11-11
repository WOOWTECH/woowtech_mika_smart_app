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

private final class BrowserSearchKeys: LearningKeyStore {
    var values: [String: Data] = [:]
    var unavailable = false
    func read(id: String) throws -> Data? {
        if unavailable { throw LearningFileError.unavailable }; return values[id]
    }
    func insert(_ key: Data, id: String) throws {
        if unavailable { throw LearningFileError.unavailable }; values[id] = key
    }
    func remove(id: String) throws { values.removeValue(forKey: id) }
    func removeAll(except id: String) throws { values = values.filter { $0.key == id } }
}

@MainActor enum BrowserSearchAppChecks {
    struct Failure: Error { let check: String }
    @MainActor private final class URLChangeEvidence {
        private var observation: NSKeyValueObservation?
        private(set) var urls: [URL] = []
        init(_ view: WKWebView) {
            observation = view.observe(\.url, options: [.new]) { [weak self] _, change in
                let observed = change.newValue ?? nil
                Task { @MainActor [weak self] in
                    if let observed { self?.urls.append(observed) }
                }
            }
        }
    }
    static func runSPAHash() async throws -> [String: Any] {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw Failure(check: name) }; count += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-spa-hash-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = BrowserSearchKeys()
        let vault = EncryptedLearningFile(url: root.appendingPathComponent("library.vault"), keys: keys)
        let workspace = BrowserWorkspace(dataStore: .nonPersistent(), vault: vault,
            downloadDirectory: root.appendingPathComponent("Downloads"))
        let host = try BrowserSiteModesAppChecks.Host()
        defer { workspace.cancelAllWork(); host.close() }
        let browser = workspace.selected
        host.attach(browser)
        let base = URL(string: "https://research.example.invalid/spa")!
        let routed = URL(string: "https://research.example.invalid/spa#/docs/42")!
        let sensitive = URL(string: "https://research.example.invalid/spa#/authToken/fixture")!
        let afterFailure = URL(string: "https://research.example.invalid/spa#/docs/43")!
        let afterClose = URL(string: "https://research.example.invalid/spa#/docs/44")!
        let html = "<!doctype html><title>SPA fixture</title><a id='route-link' href='#/docs/42'>Open section</a><a id='sensitive-link' href='#/authToken/fixture'>Private section</a><a id='rejected-link' href='https://127.0.0.1/fail'>Rejected navigation</a><a id='after-failure' href='#/docs/43'>After failed navigation</a><a id='after-close' href='#/docs/44'>After closed tab</a><script>window.spaMarker='same-document'</script>"
        let selectedID = workspace.library.selectedID
        browser.manualNavigation(to: base) {
            browser.webView.loadSimulatedRequest(URLRequest(url: base), responseHTML: html)
        }
        try await BrowserSiteModesAppChecks.wait("actual SPA document load") {
            browser.loadedURL == base && !browser.webView.isLoading && workspace.library.tabs.first?.url == base
        }
        try check(browser.externalOpenURL == base, "initial selected page is eligible for external handoff")
        let link = try await browser.webView.evaluateJavaScript("document.getElementById('route-link').getAttribute('href')") as? String
        try check(link == "#/docs/42", "real loaded document contains the in-page route link")
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('route-link').click(); true")
        try await BrowserSiteModesAppChecks.wait("actual anchor changes WebKit URL") { browser.webView.url == routed }
        let marker = try await browser.webView.evaluateJavaScript("window.spaMarker") as? String
        try check(marker == "same-document", "hash route kept the loaded document")
        // WebKit's same-document route may not issue another didFinish. Give
        // App observation a bounded chance to publish before checking handoff.
        let deadline = Date().addingTimeInterval(5)
        while browser.loadedURL != routed && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try check(browser.loadedURL == routed, "selected session publishes actual hash route (loaded=\(browser.loadedURL?.absoluteString ?? "nil"))")
        try check(browser.current == nil && browser.status == "頁面已載入；此頁面僅供手動瀏覽",
            "hash route remains outside the readonly research evidence boundary")
        try check(browser.address == routed.absoluteString, "address follows actual hash route")
        try check(workspace.selected === browser && workspace.library.selectedID == selectedID,
            "the active tab remains selected after same-document navigation")
        var handedOff: [URL] = []
        try check(browser.externalOpenURL == routed && browser.handoffVisiblePage { handedOff.append($0) }
            && handedOff == [routed], "external handoff passes exact current SPA route")
        try check(workspace.library.tabs.first?.url == base && workspace.library.history.first?.url == base,
            "encrypted tab/history retain their fragment-insensitive storage contract")
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('sensitive-link').click(); true")
        try await BrowserSiteModesAppChecks.wait("actual sensitive hash link") {
            browser.webView.url == sensitive && browser.loadedURL == sensitive
        }
        let sensitiveHandoff = browser.handoffVisiblePage { handedOff.append($0) }
        try check(browser.externalOpenURL == nil && !sensitiveHandoff
            && handedOff == [routed], "known-sensitive hash route never leaves the App")
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('route-link').click(); true")
        try await BrowserSiteModesAppChecks.wait("safe SPA route restored") {
            browser.loadedURL == routed && browser.externalOpenURL == routed
        }
        workspace.newTab(); host.attach(workspace.selected)
        try check(browser.externalOpenURL == nil && workspace.selected !== browser,
            "unselected tab cannot hand off its retained route")
        workspace.selectTab(selectedID); host.attach(workspace.selected)
        try check(workspace.selected === browser && browser.externalOpenURL == routed,
            "reselected tab preserves its live SPA route without storing the fragment")
        let urlEvidence = URLChangeEvidence(browser.webView)
        let failedTarget = URL(string: "https://127.0.0.1/fail")!
        let failureProbe = BrowserSiteModesAppChecks.Probe(browser)
        browser.webView.navigationDelegate = failureProbe
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('rejected-link').click(); true")
        try await BrowserSiteModesAppChecks.wait("real WebKit rejected-link policy") {
            failureProbe.externallyCancelledURLs.contains(failedTarget)
                && failureProbe.actions.contains { $0.host == "127.0.0.1" && $0.main && $0.policy == .cancel }
                && browser.error != nil
        }
        browser.webView.navigationDelegate = browser
        try check(browser.webView.url == routed && browser.loadedURL == routed && browser.externalOpenURL == nil,
            "rejected navigation retains the old document but revokes its handoff")
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('after-failure').click(); true")
        try await BrowserSiteModesAppChecks.wait("late URL KVO after failed navigation") {
            browser.webView.url == afterFailure && urlEvidence.urls.contains(afterFailure)
        }
        await Task.yield() // Let the product's independently queued MainActor KVO handler run.
        try check(browser.loadedURL == routed && browser.externalOpenURL == nil,
            "late hash change cannot revive a failed navigation")

        browser.manualNavigation(to: base) {
            browser.webView.loadSimulatedRequest(URLRequest(url: base), responseHTML: html)
        }
        try await BrowserSiteModesAppChecks.wait("fresh manual document after failure") {
            browser.loadedURL == base && browser.externalOpenURL == base && !browser.webView.isLoading
        }
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('route-link').click(); true")
        try await BrowserSiteModesAppChecks.wait("fresh route before close") {
            browser.loadedURL == routed && browser.externalOpenURL == routed
        }
        workspace.closeTab(selectedID)
        let replacement = workspace.selected
        let libraryAfterClose = workspace.library
        try check(replacement !== browser && replacement.loadedURL == nil && browser.externalOpenURL == nil,
            "closing the active tab revokes the old session and selects a blank replacement")
        // Retain the old WebView in the hosted window while the removed session
        // receives one more actual same-document WebKit URL notification.
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('after-close').click(); true")
        try await BrowserSiteModesAppChecks.wait("late URL KVO after closing tab") {
            browser.webView.url == afterClose && urlEvidence.urls.contains(afterClose)
        }
        await Task.yield()
        let closedHandoff = browser.handoffVisiblePage { _ in }
        try check(browser.loadedURL == routed && browser.externalOpenURL == nil && !closedHandoff,
            "late hash change cannot restore the closed session's URL or external action")
        try check(workspace.selected === replacement && workspace.library == libraryAfterClose
            && workspace.selected.loadedURL == nil,
            "late closed-tab KVO cannot alter the selected tab or encrypted library")
        host.attach(replacement)
        return ["assertions": count, "actual_webkit": true, "actual_in_page_anchor": true,
                "failed_navigation_policy_rejected": failureProbe.externallyCancelledURLs.contains(failedTarget),
                "failed_navigation_callbacks": failureProbe.failures,
                "late_failure_url_kvo": urlEvidence.urls.contains(afterFailure),
                "late_closed_tab_url_kvo": urlEvidence.urls.contains(afterClose),
                "external_network_or_personal_keychain": false, "native_ui_execution": false]
    }
    static func run() async throws -> [String: Any] {
        var count = try BrowserSearchChecks.run()
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw Failure(check: name) }; count += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-browser-search-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("library.vault"), keys = BrowserSearchKeys()
        func vault() -> EncryptedLearningFile { EncryptedLearningFile(url: file, keys: keys) }
        let languageSuite = "woow-language-search-" + UUID().uuidString
        let languageDefaults = UserDefaults(suiteName: languageSuite)!
        defer { languageDefaults.removePersistentDomain(forName: languageSuite) }
        let language = AppLanguageStore(defaults: languageDefaults, preferredLanguages: { ["zh-TW"] })
        let store = WKWebsiteDataStore.nonPersistent()
        let workspace = BrowserWorkspace(dataStore: store, vault: vault(), downloadDirectory: root.appendingPathComponent("Downloads"))
        let browser = workspace.selected, probe = BrowserSiteModesAppChecks.Probe(workspace.selected)
        let host = try BrowserSiteModesAppChecks.Host()
        defer { workspace.cancelAllWork(); host.close() }
        host.attach(browser); browser.webView.navigationDelegate = probe
        try check(workspace.available && workspace.library.searchSettings.selectedID == "bing", "actual workspace defaults Bing")
        browser.address = " \n "; browser.openAddress()
        try check(browser.error == nil && probe.actions.isEmpty, "empty input is a no-op")

        // Exercise openAddress and the real policy delegate; the probe cancels
        // the outgoing request before network I/O. No search service is contacted.
        browser.address = "first query & #/+% 中文"
        browser.openAddress()
        try await BrowserSiteModesAppChecks.wait("actual Bing navigation action", { probe.actions.count == 1 && !browser.webView.isLoading })
        try check(probe.actions[0].host == "www.bing.com" && probe.actions[0].method == "GET" && probe.actions[0].policy == .allow,
                  "actual App resolves words through default engine")
        try check(workspace.selectSearchEngine("google"), "select built-in persists")
        browser.address = "second query"
        browser.openAddress()
        try await BrowserSiteModesAppChecks.wait("actual Google navigation action", { probe.actions.count == 2 && !browser.webView.isLoading })
        try check(probe.actions[1].host == "www.google.com" && probe.actions[1].method == "GET", "selected engine wired to same session")
        let beforeInvalid = probe.actions.count
        for invalid in ["https://127.0.0.1/", "https://example.com:/", "http://example.com/", "javascript:alert(1)", "https://user:pass@example.com/",
                        "https:127.0.0.1", "http:localhost", "https:/private.invalid/path", "HTTPS:example.invalid",
                        "https:/user:synthetic@example.invalid/", "https:example.invalid/?token=synthetic"] {
            browser.address = invalid; browser.openAddress()
            try check(browser.error != nil, "rejected input reports an error without a search")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(probe.actions.count == beforeInvalid, "blocked URL not reinterpreted as remote search")

        try check(workspace.addSearchEngine(name: "Fixture Search", template: "https://research.example.invalid/search?q=%s&lang=en"), "add custom through actual workspace")
        let engine = workspace.library.searchSettings.selected
        let query = "fixture cats & dogs/+% 中文"
        let url = try engine.searchURL(query: query)
        let html = "<!doctype html><title>Search fixture</title><p>LOCAL SEARCH FIXTURE</p><input aria-label='Search note' value='retained'>"
        func load(_ target: URL) async throws {
            let finishes = probe.finishes
            probe.localHTMLURL = target
            var request = URLRequest(url: target); request.httpMethod = "GET"
            browser.manualNavigation(to: target) { browser.webView.loadSimulatedRequest(request, responseHTML: html) }
            try await BrowserSiteModesAppChecks.wait("completed local search document", { probe.finishes == finishes + 1 && browser.loadedURL == target && !browser.webView.isLoading })
        }
        try await load(url)
        try check(browser.manualSearchMatch?.query == query && browser.manualSearchMatch?.engineName == "Fixture Search", "query restored in actual App")
        try check(browser.address == url.absoluteString, "address retains destination URL")
        try check(browser.current == nil && !browser.automationOwnsDocument, "query page remains manual and outside readonly research")
        try check(workspace.library.history.count == 1 && workspace.library.history[0].url == url, "history persists actual result URL")
        workspace.addBookmark()
        try check(workspace.library.bookmarks.first?.url == url, "saved search reopens its original URL")
        let cookie = HTTPCookie(properties: [.domain: "research.example.invalid", .path: "/", .name: "search_fixture", .value: "synthetic"])!
        await store.httpCookieStore.setCookie(cookie)
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('input').value='keep document'; true")
        let originalView = browser.webView, originalNavigation = probe.lastNavigation
        let actions = probe.actions.count, finishes = probe.finishes
        let beforeLanguage = workspace.library
        let draftBeforeLanguage = browser.address
        try check(language.setFromUser(.english) && language.setFromUser(.simplifiedChinese), "change display language with a live manual document")
        try check(workspace.library == beforeLanguage && workspace.selected === browser && browser.address == draftBeforeLanguage,
                  "language preserves encrypted metadata, session and address draft")
        try check(workspace.selectSearchEngine("bing"), "change engine on completed document")
        try await Task.sleep(nanoseconds: 100_000_000)
        let note = try await browser.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        let cookies = await store.httpCookieStore.allCookies()
        try check(probe.actions.count == actions && probe.finishes == finishes && probe.lastNavigation === originalNavigation,
                  "engine change never navigates/reloads/repeats document")
        try check(browser.webView === originalView && note == "keep document" && cookies.contains { $0.name == cookie.name && $0.value == cookie.value },
                  "same view, fields and cookie survive selection")
        try check(browser.manualSearchMatch?.query == query, "query recognition uses all engines, not only selected")
        try check(workspace.selectSearchEngine(engine.id), "restore custom selection")
        let ciphertext = try Data(contentsOf: file)
        try check(!String(decoding: ciphertext, as: UTF8.self).contains("Fixture Search")
                  && !String(decoding: ciphertext, as: UTF8.self).contains("research.example.invalid"), "engine template and search history encrypted")
        let reopened = BrowserWorkspace(dataStore: store, vault: vault(), downloadDirectory: root.appendingPathComponent("Downloads"))
        defer { reopened.cancelAllWork() }
        try check(reopened.available && reopened.library == workspace.library, "encrypted restart preserves library and selected custom engine")
        try check(reopened.selected.manualSearchSettings().selected == engine && reopened.selected.address == url.absoluteString,
                  "restored session keeps original URL and new resolver")
        let beforeFailure = workspace.library
        keys.unavailable = true
        try check(!workspace.selectSearchEngine("google") && workspace.library == beforeFailure, "failed encrypted write does not publish")
        try check(try Data(contentsOf: file) == ciphertext, "failed write preserves ciphertext")
        keys.unavailable = false
        try check(!workspace.addSearchEngine(name: "Unsafe", template: "https://127.0.0.1/?q=%s") && workspace.library == beforeFailure,
                  "invalid template leaves workspace intact")
        workspace.newTab()
        try check(workspace.selected.manualSearchSettings().selected == engine, "new tabs use saved engine")
        try check(workspace.library.tabs.count == 2 && workspace.downloads.items.isEmpty, "tabs/download state preserved")
        try check(workspace.removeSearchEngine(engine.id), "delete selected custom")
        try check(workspace.library.searchSettings.selectedID == "bing" && workspace.library.history.first?.url == url
                  && workspace.library.bookmarks.first?.url == url, "delete falls back without rewriting saved result URLs")
        workspace.clearHistory()
        try check(workspace.library.history.isEmpty && workspace.library.bookmarks.count == 1
                  && workspace.library.searchSettings.selectedID == "bing", "history clear and engine state stay separate")
        // Load the actual pre-field encrypted schema, then save the additive field.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(beforeFailure)) as! [String: Any]
        legacy.removeValue(forKey: "searchSettings")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyFile = EncryptedLearningFile(url: root.appendingPathComponent("legacy.vault"), keys: keys)
        _ = try legacyFile.load(LegacyJSON.self)
        try legacyFile.save(JSONDecoder().decode(LegacyJSON.self, from: legacyData))
        let migrated = BrowserWorkspace(dataStore: .nonPersistent(), vault: legacyFile, downloadDirectory: root.appendingPathComponent("LegacyDownloads"))
        defer { migrated.cancelAllWork() }
        try check(migrated.available && migrated.library.searchSettings.selectedID == "bing", "actual encrypted legacy defaults Bing")
        try check(migrated.library.tabs == beforeFailure.tabs && migrated.library.bookmarks == beforeFailure.bookmarks
                  && migrated.library.history == beforeFailure.history && migrated.library.userSiteModes == beforeFailure.userSiteModes,
                  "encrypted migration preserves existing browser records")
        try check(migrated.selectSearchEngine("duckduckgo"), "migrated encrypted store can save new field")
        var damaged = try Data(contentsOf: file); damaged[damaged.count - 1] ^= 1; try damaged.write(to: file)
        let corrupt = BrowserWorkspace(dataStore: .nonPersistent(), vault: vault(), downloadDirectory: root.appendingPathComponent("CorruptDownloads"))
        try check(!corrupt.available && !corrupt.selectSearchEngine("google") && (try Data(contentsOf: file)) == damaged,
                  "corrupt vault unavailable and not overwritten")
        return ["assertions": count, "actual_webkit": true, "external_network_or_personal_keychain": false,
                "actual_default_and_selected_search_actions": 2, "engine_change_navigations": 0,
                "encrypted_restart_and_legacy_migration": true, "native_ui_execution": false]
    }

    private struct LegacyJSON: Codable {
        var version: Int
        var tabs: [BrowserTab]
        var selectedID: UUID
        var bookmarks: [BrowserSavedPage]
        var history: [BrowserSavedPage]
        var userSiteModes: BrowserUserSiteModes
    }
}

#if BROWSER_SEARCH_APP_STANDALONE
@main struct BrowserSearchCheckMain {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let spaHash = try await BrowserSearchAppChecks.runSPAHash()
                var result = try await BrowserSearchAppChecks.run()
                result["spa_hash"] = spaHash
                result["existing_site_mode_regression_assertions"] = try await BrowserSiteModesAppChecks.run()["assertions"]
                print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
                exit(0)
            } catch { print("FAIL \(error)"); exit(1) }
        }
        app.run()
    }
}
#endif
