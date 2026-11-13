import AssistantBrowser
import SwiftUI
import WebKit

@MainActor
struct BrowserLibraryView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var workspace: BrowserWorkspace
    var initialSection = 0
    var sitesOnly = false
    var pdfDestination: ((BrowserDownloadedPDFSelection) -> AnyView)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @State private var renameID: UUID?
    @State private var showRename = false
    @State private var renameTitle = ""
    @State private var confirmHistory = false
    @State private var deleteSite: WKWebsiteDataRecord?
    @State private var confirmSite = false
    @State private var showDownloads = false
    @State private var siteRecordsRequested = false
    @State private var deferredSiteRefresh = false
    #if DEBUG
    @State private var fixtureProtectedRequests = -1
    #endif
    var body: some View {
        NavigationStack {
            VStack {
                if !sitesOnly {
                    Picker(localizer.text(.browserLibrary), selection: $section) {
                        Text(localizer.text(.browserTabs)).tag(0); Text(localizer.text(.browserBookmarks)).tag(1); Text(localizer.text(.browserHistory)).tag(2); Text(localizer.text(.browserSites)).tag(3)
                    }.pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("browser.library.sections")
                }
                if let error = workspace.errorText { Text(localizer.text(error)).foregroundStyle(.red).accessibilityIdentifier("browser.library.error") }
                if workspace.isClearingWebsiteData {
                    ProgressView(localizer.text(.browserClearing))
                        .accessibilityIdentifier("browser.library.clearing")
                }
                #if DEBUG
                if workspace.delayedClearUIFixtureEnabled {
                    Text(workspace.delayedClearUIFixtureTimedOut ? "timed out" :
                         workspace.delayedClearUIFixtureWaiting ? "waiting" :
                         workspace.isClearingWebsiteData ? "clearing" : "complete")
                        .accessibilityIdentifier("browser.fixture.clearState")
                    Text("\(fixtureProtectedRequests)")
                        .accessibilityIdentifier("browser.fixture.protectedCount")
                    if workspace.delayedClearUIFixtureWaiting {
                        Button("Release synthetic clear") { workspace.releaseDelayedClearUIFixture() }
                            .accessibilityIdentifier("browser.fixture.releaseClear")
                    }
                }
                #endif
                List {
                    if sitesOnly { websites }
                    else if section == 0 { tabs }
                    else if section == 1 { bookmarks }
                    else if section == 2 { history }
                    else { websites }
                }
            }
            .background {
                if sitesOnly || section == 3 {
                    WebsiteDataForegroundPage(dataStore: workspace.websiteDataStore)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(localizer.text(sitesOnly ? .browserSites : .browserLibrary))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localizer.text(.commonClose)) { dismiss() }.accessibilityIdentifier("browser.library.close") } }
            .toolbar {
                if !sitesOnly {
                    ToolbarItem(placement: .navigationBarLeading) { Button(localizer.text(.browserDownloads)) { showDownloads = true }.accessibilityIdentifier("browser.downloads.open") }
                }
            }
            .sheet(isPresented: $showDownloads) { BrowserDownloadsView(manager: workspace.downloads, pdfDestination: pdfDestination) }
            .alert(localizer.text(.browserRenameBookmark), isPresented: $showRename) {
                TextField(localizer.text(.commonName), text: $renameTitle).accessibilityIdentifier("browser.bookmark.name")
                Button(localizer.text(.commonSave)) { if let id = renameID { workspace.renameBookmark(id, title: renameTitle) }; renameID = nil }
                Button(localizer.text(.commonCancel), role: .cancel) { renameID = nil }
            }
            .confirmationDialog(localizer.text(.browserClearHistoryQuestion), isPresented: $confirmHistory, titleVisibility: .visible) {
                Button(localizer.text(.browserClearHistory), role: .destructive) { workspace.clearHistory() }.accessibilityIdentifier("browser.history.confirmClear")
            }
            .confirmationDialog(localizer.text(.browserClearSiteQuestion), isPresented: $confirmSite, titleVisibility: .visible, presenting: deleteSite) { record in
                Button(localizer.text(.browserClearSite), role: .destructive) { workspace.removeWebsiteData([record]); deleteSite = nil }
                    .accessibilityIdentifier("browser.sites.confirmClear")
                Button(localizer.text(.commonCancel), role: .cancel) { deleteSite = nil }
                    .accessibilityIdentifier("browser.sites.cancelClear")
            } message: { record in
                Text(localizer.text(.browserClearSiteTarget(name: record.displayName)))
                    .accessibilityIdentifier("browser.sites.confirmTarget")
            }
            .onChange(of: section) { _, selected in if selected == 3 { requestSiteRecords() } }
            .onChange(of: workspace.isClearingWebsiteData) { _, clearing in
                if !clearing && deferredSiteRefresh && (sitesOnly || section == 3) { requestSiteRecords() }
            }
            .onAppear {
                if sitesOnly { requestSiteRecords() }
                else { section = initialSection }
            }
        }
        #if DEBUG
        .task {
            guard workspace.delayedClearUIFixtureEnabled, let fixture = BrowserLoginFixture.enabled else { return }
            while !Task.isCancelled {
                fixtureProtectedRequests = await fixture.protectedRequestCount()
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            }
        }
        #endif
    }
    private func requestSiteRecords() {
        siteRecordsRequested = true
        guard !workspace.isClearingWebsiteData else { deferredSiteRefresh = true; return }
        deferredSiteRefresh = false
        workspace.refreshWebsiteRecords()
    }
    private var tabs: some View {
        Group {
            Button(localizer.text(.browserNewTab)) { workspace.newTab(); dismiss() }.disabled(!workspace.available)
                .accessibilityIdentifier("browser.tabs.new")
            ForEach(workspace.library.tabs) { tab in
                HStack {
                    Button {
                        workspace.selectTab(tab.id); dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(tab.title).lineLimit(2)
                            Text(tab.url?.host ?? localizer.text(.browserNoPage)).font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("browser.tabs.select.\(tab.id)")
                        .accessibilityValue(workspace.library.selectedID == tab.id ? localizer.text(.commonSelected) : localizer.text(.commonUnselected))
                    Button { workspace.closeTab(tab.id) } label: { Image(systemName: "xmark.circle") }
                        .accessibilityLabel(localizer.text(.commonCloseName(name: tab.title))).accessibilityIdentifier("browser.tabs.close.\(tab.id)")
                }.buttonStyle(.borderless)
            }
        }
    }
    private var bookmarks: some View {
        Group {
            Button(localizer.text(.browserBookmarkCurrent)) { workspace.addBookmark() }
                .disabled(!workspace.available || workspace.selected.loadedURL.flatMap(BrowserManualNavigationPolicy.libraryURL) == nil)
                .accessibilityIdentifier("browser.bookmarks.add")
            if workspace.library.bookmarks.isEmpty { Text(localizer.text(.browserNoBookmarks)).accessibilityIdentifier("browser.bookmarks.empty") }
            ForEach(workspace.library.bookmarks) { page in
                VStack(alignment: .leading, spacing: 8) {
                    pageButton(page, prefix: "bookmark")
                    HStack {
                        Button(localizer.text(.browserRename)) { renameTitle = page.title; renameID = page.id; showRename = true }.accessibilityIdentifier("browser.bookmark.rename.\(page.id)")
                        Button(localizer.text(.commonDelete), role: .destructive) { workspace.removeBookmark(page.id) }.accessibilityIdentifier("browser.bookmark.delete.\(page.id)")
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
    private var history: some View {
        Group {
            Button(localizer.text(.browserClearAllHistory), role: .destructive) { confirmHistory = true }
                .disabled(workspace.library.history.isEmpty).accessibilityIdentifier("browser.history.clear")
            if workspace.library.history.isEmpty { Text(localizer.text(.browserNoHistory)).accessibilityIdentifier("browser.history.empty") }
            ForEach(workspace.library.history) { page in
                HStack {
                    pageButton(page, prefix: "history")
                    Button(localizer.text(.commonDelete), role: .destructive) { workspace.removeHistory(page.id) }
                        .accessibilityIdentifier("browser.history.delete.\(page.id)")
                }.buttonStyle(.borderless)
            }
        }
    }
    private var websites: some View {
        Group {
            Text(localizer.text(.browserSitesHelp))
                .font(.caption)
                .accessibilityIdentifier("browser.sites.help")
            if !workspace.isClearingWebsiteData && (!siteRecordsRequested || deferredSiteRefresh || workspace.isLoadingWebsiteRecords) {
                ProgressView().accessibilityLabel(localizer.text(.browserSites))
                    .accessibilityIdentifier("browser.sites.loading")
            } else if !workspace.isClearingWebsiteData {
                if workspace.websiteRecords.isEmpty { Text(localizer.text(.browserNoSites)).accessibilityIdentifier("browser.sites.empty") }
                ForEach(workspace.websiteRecords, id: \.displayName) { record in
                    HStack {
                        Text(record.displayName)
                        Spacer()
                        Button(localizer.text(.commonClear), role: .destructive) { deleteSite = record; confirmSite = true }
                            .accessibilityIdentifier("browser.sites.clear.\(record.displayName)")
                    }
                }
            }
        }
    }
    private func pageButton(_ page: BrowserSavedPage, prefix: String) -> some View {
        Button { workspace.open(page.url); dismiss() } label: {
            VStack(alignment: .leading) {
                if prefix == "history", let match = workspace.library.searchSettings.match(page.url) {
                    Text(localizer.text(.browserHistorySearch(query: match.query))).lineLimit(2)
                    Text(match.engineName).font(.caption)
                } else { Text(page.title).lineLimit(2) }
                Text(page.url.absoluteString).font(.caption).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("browser.\(prefix).open.\(page.id)")
    }
}

/// A blank page from the browser's own data store, kept in the window while
/// the website-data list is shown. WebKit lists and deletes website data in
/// its network process, and only a visible page gives that process a
/// foreground activity. From Memory, or over the browser start page, there is
/// no visible page. On iOS 18.5 CI (PR #33, SE and Pro Max) fetchDataRecords
/// then woke the suspended network process with a background assertion only;
/// it did not even log processDidResume while the tests waited (20 and 30 s),
/// so the list spun forever. Each resume in those logs that followed a
/// foreground activity ran within 0.1 s. This page loads no URL, sends no
/// request and stores no website data.
private struct WebsiteDataForegroundPage: UIViewRepresentable {
    let dataStore: WKWebsiteDataStore

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.accessibilityElementsHidden = true
        view.loadHTMLString("<!doctype html><title></title>", baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
    }
}
