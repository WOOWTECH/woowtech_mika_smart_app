import AssistantBrowser
import AssistantPersistence
import Combine
import Foundation
import WebKit

struct BrowserPageDialog: Identifiable {
    enum Kind { case alert, confirm, prompt }
    let id = UUID()
    let kind: Kind
    let host: String
    let message: String
    let initial: String
}

@MainActor
final class BrowserWorkspace: ObservableObject {
    @Published private(set) var library = BrowserLibraryState()
    @Published private(set) var selected: BrowserSession
    @Published private(set) var errorText: AppText?
    var error: String? { errorText.map { AppLocalizer(language: .traditionalChinese).text($0) } }
    @Published private(set) var siteModeNoticeText: AppText?
    var siteModeNotice: String? { siteModeNoticeText.map { AppLocalizer(language: .traditionalChinese).text($0) } }
    @Published private(set) var available = false
    @Published private(set) var websiteRecords: [WKWebsiteDataRecord] = []
    @Published private(set) var isLoadingWebsiteRecords = false
    @Published private(set) var isClearingWebsiteData = false
    private var sessions: [UUID: BrowserSession] = [:]
    private var websiteRecordRevision = UUID()
    private var activateAfterWebsiteClear = false
    private var browserActivationAllowed = false
    private var vault: EncryptedLearningFile?
    let websiteDataStore: WKWebsiteDataStore
    let downloads: BrowserDownloadManager
    #if DEBUG
    private var uploadFixtureStarted = false
    private var loginFixtureStarted = false
    private var downloadPDFFixtureStarted = false
    #endif

    init(dataStore injectedDataStore: WKWebsiteDataStore? = nil,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        var dataStore = WKWebsiteDataStore.default()
        var scope = "personal"
        var reset = false
        var invalidTestScope = false
        #if DEBUG
        let args = arguments
        if args.contains("-UITestMode") || args.contains("-LiveModelUITest") || args.contains("-LiveBrowserUITest") {
            let flag = args.contains("-LiveModelUITest") ? "-LiveModelUITestNamespace" : "-UITestNamespace"
            if let index = args.firstIndex(of: flag), args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1]) {
                scope = "test-" + id.uuidString
                #if os(iOS)
                dataStore = WKWebsiteDataStore(forIdentifier: id)
                #else
                dataStore = .nonPersistent()
                #endif
                reset = args.contains("-UITestResetStorage") || args.contains("-LiveModelUITestCleanup")
            } else { invalidTestScope = true; dataStore = .nonPersistent() }
        }
        #endif
        if let injectedDataStore { dataStore = injectedDataStore }
        websiteDataStore = dataStore
        let downloadRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloadDirectory = downloadRoot.appendingPathComponent("BrowserDownloads/" + (invalidTestScope ? UUID().uuidString : scope), isDirectory: true)
        if reset { try? FileManager.default.removeItem(at: downloadDirectory) }
        downloads = BrowserDownloadManager(directory: downloadDirectory)
        selected = BrowserSession(dataStore: dataStore)
        do {
            guard !invalidTestScope else { throw BrowserLibraryError.invalidState }
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("BrowserLibrary/" + scope, isDirectory: true)
            let file = EncryptedLearningFile(url: root.appendingPathComponent("library.vault"),
                keys: LearningKeychainStore(service: "io.woowtech.assistant.browser.library." + scope))
            if reset {
                if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            }
            let loaded = try file.load(BrowserLibraryState.self) ?? BrowserLibraryState()
            try loaded.validate()
            library = loaded; vault = file; available = true
        } catch { self.errorText = .browserReadError }
        selected = makeSession(id: library.selectedID)
        if reset {
            isClearingWebsiteData = true
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
                guard let self else { return }
                self.isClearingWebsiteData = false
                // BrowserView may have appeared while its isolated profile was
                // being reset. Resume that visible navigation after WebKit
                // finishes clearing, just as a user-initiated clear does.
                self.finishDeferredBrowserActivation(success: true)
            }
        }
        // Restore metadata only. Visiting a saved page starts when Browser opens,
        // not during unrelated chat/settings startup or a background relaunch.
    }

    /// Exercise actual workspace persistence with an isolated file/key store.
    /// Does not open the personal profile, Keychain or download directory.
    init(dataStore: WKWebsiteDataStore, vault: EncryptedLearningFile, downloadDirectory: URL) {
        websiteDataStore = dataStore
        downloads = BrowserDownloadManager(directory: downloadDirectory)
        selected = BrowserSession(dataStore: dataStore)
        do {
            let loaded = try vault.load(BrowserLibraryState.self) ?? BrowserLibraryState()
            try loaded.validate()
            library = loaded; self.vault = vault; available = true
        } catch { self.errorText = .browserReadError }
        selected = makeSession(id: library.selectedID)
    }

    @discardableResult
    func setManualSiteMode(_ mode: BrowserManualSiteMode) -> Bool {
        guard !isClearingWebsiteData, let host = selected.manualSiteModeHost else { return false }
        siteModeNoticeText = nil
        let previous = library.userSiteModes
        guard update({ try $0.setManualSiteMode(mode, for: host) }) else { return false }
        var reloading = false
        for session in sessions.values {
            let pageHost = session.loadedURL?.host
            if session === selected || previous.mode(for: pageHost) != library.userSiteModes.mode(for: pageHost) {
                let changed = previous.mode(for: pageHost) != library.userSiteModes.mode(for: pageHost)
                let applied = session.manualSiteModeDidChange(applyToCurrentDocument: session === selected && changed)
                if session === selected { reloading = applied }
            }
        }
        siteModeNoticeText = reloading ? .browserModeReloading
            : .browserModeDeferred
        return true
    }

    @discardableResult
    func selectSearchEngine(_ id: String) -> Bool {
        guard !isClearingWebsiteData else { return false }
        return update { try $0.selectSearchEngine(id) }
    }

    @discardableResult
    func addSearchEngine(name: String, template: String) -> Bool {
        guard !isClearingWebsiteData else { return false }
        guard library.searchSettings.custom.count < BrowserSearchSettings.maximumCustomEngines else {
            errorText = .searchLimit; return false
        }
        do {
            let engine = try BrowserSearchEngine(name: name, template: template)
            return update { try $0.addSearchEngine(engine) }
        } catch {
            self.errorText = .searchInvalid
            return false
        }
    }

    @discardableResult
    func removeSearchEngine(_ id: String) -> Bool {
        guard !isClearingWebsiteData else { return false }
        return update { $0.removeSearchEngine(id) }
    }

    /// Browser appearance is a user navigation; defer it while clearing rather
    /// than restoring an obsolete session or loading in the background.
    func browserDidAppear(activate: Bool = true) {
        browserActivationAllowed = true
        // A foreground browser may still be covered by its library sheet.
        // Restore only after that sheet is dismissed.
        if !activate { activateAfterWebsiteClear = false; return }
        if isClearingWebsiteData { activateAfterWebsiteClear = true; return }
        activateAfterWebsiteClear = false
        activateSelected()
    }

    func browserDidDisappear() { browserActivationAllowed = false; activateAfterWebsiteClear = false }

    /// A sheet can cover BrowserView without a disappearance callback. Revoke
    /// a deferred page load synchronously before the sheet is presented.
    func browserLibraryWillPresent() { activateAfterWebsiteClear = false }

    /// A sheet can close without another BrowserView appearance callback.
    /// Only the still-visible foreground browser may restore its selected page.
    func browserLibraryDidDismiss(isVisible: Bool, isActive: Bool) {
        guard isVisible && isActive && browserActivationAllowed else { return }
        browserDidAppear()
    }

    private func finishDeferredBrowserActivation(success: Bool) {
        let shouldActivate = activateAfterWebsiteClear && success
        activateAfterWebsiteClear = false
        if shouldActivate { activateSelected() }
    }

    #if DEBUG
    // Hosted tests hold the real removal after page quiescence, and substitute
    // local HTML for the final navigation. Never enabled by production flags.
    var websiteRemovalTestGate: (@MainActor () async -> Void)?
    var restoredNavigationTestHook: (@MainActor (BrowserSession) -> Void)?

    // Opt-in only for the isolated synthetic login UI fixture. This bounded
    // gate lets native tests hold real WebKit deletion while presenting the
    // library and backgrounding the App; no production profile is involved.
    var delayedClearUIFixtureEnabled: Bool {
        BrowserLoginFixture.enabled != nil &&
        ProcessInfo.processInfo.arguments.filter { $0 == "-UITestBrowserDelayedClear" }.count == 1
    }
    @Published private(set) var delayedClearUIFixtureWaiting = false
    @Published private(set) var delayedClearUIFixtureTimedOut = false
    private var delayedClearUIFixtureContinuation: CheckedContinuation<Void, Never>?
    private var delayedClearUIFixtureTimeout: Task<Void, Never>?

    private func awaitDelayedClearUIFixture() async {
        guard delayedClearUIFixtureEnabled else { return }
        await withCheckedContinuation { continuation in
            delayedClearUIFixtureContinuation = continuation
            delayedClearUIFixtureTimedOut = false
            delayedClearUIFixtureWaiting = true
            delayedClearUIFixtureTimeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                self?.releaseDelayedClearUIFixture(timedOut: true)
            }
        }
    }

    func releaseDelayedClearUIFixture(timedOut: Bool = false) {
        guard let continuation = delayedClearUIFixtureContinuation else { return }
        delayedClearUIFixtureContinuation = nil
        delayedClearUIFixtureWaiting = false
        delayedClearUIFixtureTimedOut = timedOut
        delayedClearUIFixtureTimeout?.cancel(); delayedClearUIFixtureTimeout = nil
        continuation.resume()
    }
    #endif

    func activateSelected() {
        #if DEBUG
        if !downloadPDFFixtureStarted, let fixture = BrowserDownloadedPDFFixture.enabled {
            downloadPDFFixtureStarted = true
            Task { [weak self] in
                do {
                    let url = try await fixture.start()
                    guard let self else { return }
                    while self.isClearingWebsiteData { try await Task.sleep(nanoseconds: 50_000_000) }
                    self.open(url)
                } catch { self?.selected.reportDownloadPDFFixtureFailure() }
            }
            return
        }
        if !uploadFixtureStarted, let fixture = BrowserUploadFixture.enabled {
            uploadFixtureStarted = true
            Task { [weak self] in
                do {
                    let url = try await fixture.start()
                    guard let self else { return }
                    while self.isClearingWebsiteData { try await Task.sleep(nanoseconds: 50_000_000) }
                    self.open(url)
                } catch { self?.errorText = .browserUploadFixtureError }
            }
            return
        }
        if !loginFixtureStarted, let fixture = BrowserLoginFixture.enabled {
            loginFixtureStarted = true
            Task { [weak self] in
                do {
                    let url = try await fixture.start()
                    guard let self else { return }
                    while self.isClearingWebsiteData { try await Task.sleep(nanoseconds: 50_000_000) }
                    // Only the strictly isolated login UI fixture may seed a
                    // second fixed site for target-selection tests.
                    if ProcessInfo.processInfo.arguments.filter({ $0 == "-UITestBrowserLoginSecondSite" }).count == 1,
                       let cookie = HTTPCookie(properties: [.domain: "other-site.example.org", .path: "/",
                           .name: "woow_second_site_fixture", .value: "fixture-only", .secure: "TRUE",
                           .expires: Date().addingTimeInterval(3600)]) {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            self.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
                        }
                    }
                    self.open(url)
                } catch { self?.errorText = .browserLoginFixtureError }
            }
            return
        }
        #endif
        guard !isClearingWebsiteData, selected.loadedURL == nil, !selected.hasPendingManualNavigation,
              !selected.address.isEmpty, selected.manualLoadDiagnostics == nil else { return }
        #if DEBUG
        if let restoredNavigationTestHook { restoredNavigationTestHook(selected); return }
        #endif
        selected.openAddress()
    }
    @discardableResult private func update(_ change: (inout BrowserLibraryState) throws -> Void) -> Bool {
        guard available, let vault else { errorText = .browserSaveUnavailable; return false }
        do {
            var next = library; try change(&next); try next.validate(); try vault.save(next)
            library = next; errorText = nil; return true
        } catch { self.errorText = (error as? BrowserLibraryError) == .tabLimit ? .browserTabLimit : .browserSaveError; return false }
    }
    private func makeSession(id: UUID, configuration: WKWebViewConfiguration? = nil) -> BrowserSession {
        if let session = sessions[id] { return session }
        let session = BrowserSession(dataStore: websiteDataStore, configuration: configuration)
        session.manualSiteMode = { [weak self] host in self?.library.userSiteModes.mode(for: host) ?? .mobile }
        session.manualSearchSettings = { [weak self] in self?.library.searchSettings ?? .init() }
        session.downloads = downloads
        session.canPresentUI = { [weak self] in self?.library.selectedID == id && self?.isClearingWebsiteData == false }
        session.address = library.tabs.first(where: { $0.id == id })?.url?.absoluteString ?? ""
        session.onPageFinished = { [weak self] url, title in
            #if DEBUG
            // Fixture HTTP pages exercise WebKit state, not the public-HTTPS
            // bookmark library. Do not invent persistent public URLs for them.
            if BrowserUploadFixture.enabled?.allows(url) == true || BrowserLoginFixture.enabled?.allows(url) == true
                || BrowserDownloadedPDFFixture.enabled?.allowsNavigation(url) == true { return }
            #endif
            _ = self?.update { try $0.visit(tab: id, url: url, title: title) }
        }
        session.onCreateWindow = { [weak self] configuration, request in
            guard let self, self.library.selectedID == id, !self.isClearingWebsiteData else { return nil }
            var newID: UUID?
            guard self.update({ newID = try $0.addTab() }), let newID else { return nil }
            self.selected.cancelInteraction()
            let popup = self.makeSession(id: newID, configuration: configuration)
            popup.prepareManualPopup(request)
            self.selected = popup
            return popup.webView
        }
        session.onCloseWindow = { [weak self] in self?.closeTab(id) }
        sessions[id] = session
        return session
    }
    func newTab() {
        guard !isClearingWebsiteData else { return }
        var newID: UUID?
        guard update({ newID = try $0.addTab() }), let newID else { return }
        suspendSelected(); selected = makeSession(id: newID)
    }
    func selectTab(_ id: UUID) {
        guard id != library.selectedID, !isClearingWebsiteData else { return }
        guard update({ try $0.select(id) }) else { return }
        suspendSelected(); selected = makeSession(id: id); activateSelected()
    }
    func closeTab(_ id: UUID) {
        guard !isClearingWebsiteData, update({ try $0.close(id) }) else { return }
        sessions.removeValue(forKey: id)?.cancel()
        selected = makeSession(id: library.selectedID); activateSelected()
    }
    private func suspendSelected() {
        if selected.isRunning { selected.cancel() }
        selected.cancelInteraction(); selected.resolveDialog(nil)
    }
    func cancelAllWork(preservingFrozenReferences: Bool = false) {
        browserActivationAllowed = false
        activateAfterWebsiteClear = false
        for session in sessions.values {
            if session.isRunning && !(preservingFrozenReferences && session.hasActiveRunReferences) { session.cancel() }
            session.cancelInteraction(); session.resolveDialog(nil)
        }
    }
    func open(_ url: URL) {
        guard !isClearingWebsiteData else { return }
        suspendSelected(); selected.address = url.absoluteString; selected.openAddress()
    }
    @discardableResult
    func closeCurrentPage() -> Bool {
        guard !isClearingWebsiteData else { return false }
        let id = library.selectedID
        guard update({ try $0.clearPage(in: id) }) else { return false }
        let old = sessions.removeValue(forKey: id)
        old?.onPageFinished = nil
        old?.onCreateWindow = nil
        old?.onCloseWindow = nil
        old?.canPresentUI = { false }
        old?.cancel()
        selected = makeSession(id: id)
        return true
    }
    func addBookmark() {
        guard let url = selected.loadedURL else { return }
        _ = update { try $0.bookmark(url: url, title: selected.pageTitle) }
    }
    func renameBookmark(_ id: UUID, title: String) { _ = update { try $0.renameBookmark(id, title: title) } }
    func removeBookmark(_ id: UUID) { _ = update { $0.removeBookmark(id) } }
    func removeHistory(_ id: UUID) { _ = update { $0.removeHistory(id) } }
    func clearHistory() { _ = update { $0.clearHistory() } }
    func refreshWebsiteRecords() {
        guard !isClearingWebsiteData else { return }
        let revision = UUID()
        websiteRecordRevision = revision
        isLoadingWebsiteRecords = true
        websiteDataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
            guard let self, self.websiteRecordRevision == revision, !self.isClearingWebsiteData else { return }
            self.websiteRecords = records.sorted { $0.displayName < $1.displayName }
            self.isLoadingWebsiteRecords = false
        }
    }
    func removeWebsiteData(_ records: [WKWebsiteDataRecord]) {
        guard !isClearingWebsiteData, !records.isEmpty else { return }
        let selectedNames = Set(records.map(\.displayName))
        #if DEBUG
        // The production library deliberately excludes loopback URLs. Retain
        // only the strictly isolated login fixture URL in RAM for UI tests.
        let fixtureRestoreURL: URL? = {
            guard let url = selected.loadedURL,
                  BrowserLoginFixture.enabled?.allows(url) == true else { return nil }
            return url
        }()
        #endif
        websiteRecordRevision = UUID() // Earlier enumeration cannot republish stale records.
        isLoadingWebsiteRecords = false
        errorText = nil
        #if DEBUG
        let started = ProcessInfo.processInfo.systemUptime
        var removalEvents: [[String: String]] = []
        // Only the strictly gated synthetic login fixture persists diagnostics.
        // Hosted tests receive the same bounded, value-free phases in stdout.
        let diagnosticURL = BrowserLoginFixture.enabled == nil ? nil : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BrowserWebsiteRemovalDiagnostics.json")
        func trace(_ phase: String, _ counts: [String: Int] = [:]) {
            guard removalEvents.count < 64 else { return }
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            var event = counts.mapValues(String.init)
            event["phase"] = phase; event["elapsedMs"] = String(elapsed)
            removalEvents.append(event)
            browserWebsiteDiagnostic("BROWSER_WEBSITE_REMOVAL " + event.keys.sorted().map { "\($0)=\(event[$0]!)" }.joined(separator: " "))
            if let diagnosticURL,
               let data = try? JSONSerialization.data(withJSONObject: removalEvents, options: [.sortedKeys]),
               data.count <= 16_384 {
                do { try data.write(to: diagnosticURL, options: .atomic) }
                catch { browserWebsiteDiagnostic("BROWSER_WEBSITE_REMOVAL diagnosticWriteFailed=1") }
            }
        }
        trace("begin", ["records": records.count, "sessions": sessions.count,
                        "persistent": websiteDataStore.isPersistent ? 1 : 0])
        #endif
        isClearingWebsiteData = true
        for item in downloads.items where item.status.isActive { downloads.cancel(id: item.id) }
        let oldSessions = Array(sessions.values)
        for session in oldSessions { session.cancel() }
        Task { [weak self] in
            var ready = true
            for (index, session) in oldSessions.enumerated() {
                #if DEBUG
                trace("pageBegin", ["index": index])
                #endif
                let stopped = await session.discardPageForDataRemoval()
                if !stopped { ready = false }
                #if DEBUG
                trace("pageFinished", ["index": index, "stopped": stopped ? 1 : 0])
                #endif
            }
            guard let self else { return }
            #if DEBUG
            trace("pagesDiscarded", ["ready": ready ? 1 : 0])
            #endif
            guard ready else {
                self.errorText = .browserClearNotStopped
                self.isClearingWebsiteData = false
                self.sessions.removeAll()
                self.selected = self.makeSession(id: self.library.selectedID)
                self.finishDeferredBrowserActivation(success: false)
                #if DEBUG
                trace("sessionsReplaced", ["ready": 0])
                #endif
                return
            }
            #if DEBUG
            if let gate = self.websiteRemovalTestGate { await gate() }
            await self.awaitDelayedClearUIFixture()
            #endif
            // Re-enumerate after every page has stopped. The selected record
            // may have acquired new data types since the confirmation dialog.
            // Delete the actual refreshed types, avoiding work in unrelated
            // WebKit subsystems, then independently verify the selected records.
            // Keep stopped sessions alive until removal AND verification finish.
            let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            self.websiteDataStore.fetchDataRecords(ofTypes: allTypes) { [weak self] fresh in
                guard let self else { return }
                let selectedRecords = fresh.filter { selectedNames.contains($0.displayName) }
                let selectedTypes = Set(selectedRecords.flatMap { $0.dataTypes }).intersection(allTypes)
                #if DEBUG
                trace("recordsSelected", ["records": selectedRecords.count, "types": selectedTypes.count])
                #endif
                let verify: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.websiteDataStore.fetchDataRecords(ofTypes: allTypes) { [weak self] remaining in
                        guard let self else { return }
                        let selected = remaining.filter { selectedNames.contains($0.displayName) }
                        self.websiteRecords = remaining.sorted { $0.displayName < $1.displayName }
                        self.errorText = selected.isEmpty ? nil : .browserClearRemaining
                        #if DEBUG
                        let classifiedTypes: Set<String> = [WKWebsiteDataTypeCookies, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache]
                        trace("recordsRefreshed", ["allRecords": remaining.count, "selectedRecords": selected.count,
                                                  "selectedCookieRecords": selected.filter { $0.dataTypes.contains(WKWebsiteDataTypeCookies) }.count,
                                                  "selectedMemoryCacheRecords": selected.filter { $0.dataTypes.contains(WKWebsiteDataTypeMemoryCache) }.count,
                                                  "selectedDiskCacheRecords": selected.filter { $0.dataTypes.contains(WKWebsiteDataTypeDiskCache) }.count,
                                                  "selectedOtherDataTypes": Set(selected.flatMap { $0.dataTypes }).subtracting(classifiedTypes).count])
                        #endif
                        self.isClearingWebsiteData = false
                        self.sessions.removeAll()
                        self.selected = self.makeSession(id: self.library.selectedID)
                        #if DEBUG
                        if let fixtureRestoreURL { self.selected.address = fixtureRestoreURL.absoluteString }
                        #endif
                        self.finishDeferredBrowserActivation(success: selected.isEmpty)
                        #if DEBUG
                        trace("sessionsReplaced", ["ready": selected.isEmpty ? 1 : 0])
                        #endif
                    }
                }
                guard !selectedRecords.isEmpty, !selectedTypes.isEmpty else {
                    #if DEBUG
                    trace("removeNotNeeded")
                    #endif
                    verify()
                    return
                }
                #if DEBUG
                trace("removeRequested")
                #endif
                self.websiteDataStore.removeData(ofTypes: selectedTypes, for: selectedRecords) { [weak self] in
                    #if DEBUG
                    trace("removeCompleted")
                    if BrowserLoginFixture.enabled != nil, let self {
                        self.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                            trace("fixtureCookies", ["remaining": cookies.filter { $0.name == BrowserLoginFixture.cookieName }.count])
                        }
                    }
                    #endif
                    verify()
                }
            }
        }
    }
}
