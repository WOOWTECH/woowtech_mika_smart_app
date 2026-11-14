import SwiftUI
import WebKit
import AssistantBrowser
import UIKit

@MainActor
struct BrowserView: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.openURL) private var openURL
    @ObservedObject var browser: BrowserSession
    @ObservedObject var chat: ChatSession
    @ObservedObject var workspace: BrowserWorkspace
    @State private var showResearch = false
    @State private var showInteractions = false
    @State private var showSearchSettings = false
    @State private var showMore = false
    @State private var startQuery = ""
    /// Play's page bar: the address shows the site until tapped, then the full URL.
    @State private var editingAddress = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var addressFocused: Bool
    private var palette: BrowserPalette { BrowserPalette(colorScheme) }
    private var isStartPage: Bool { browser.loadedURL == nil && browser.address.isEmpty || showInvalidStartInput }
    @State private var showInvalidStartInput = false
    private var pageCovered: Bool {
        isStartPage || showResearch || showInteractions
            || showSearchSettings || showMore || workspace.presentsSignIns || browser.pageDialog != nil
    }
    private var pageHostVisible: Bool {
        scenePhase == .active && !pageCovered && !workspace.isClearingWebsiteData
    }
    /// Offer the existing research form only for the page WebKit currently shows
    /// and that this session has already read as a permitted public page.
    private var pageAskHost: String? {
        guard scenePhase == .active, !pageCovered, !addressFocused, workspace.available,
              !workspace.isClearingWebsiteData, !browser.isRunning, !browser.isInteracting,
              !browser.automationOwnsDocument, let page = browser.current,
              browser.loadedURL == page.url, browser.webView.url == page.url,
              browser.address == page.url.absoluteString,
              !browser.webView.isLoading else { return nil }
        return page.url.host
    }
    var body: some View {
        VStack(spacing: 4) {
            Group {
                if isStartPage { startBar }
                else if editingAddress { addressEditor }
                else { pageBar }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, isStartPage ? 12 : 4)
            .overlay(alignment: .topLeading) { loadObservation }
            if !isStartPage { progressLine }
            if isStartPage {
                HStack {
                    Button(localizer.text(.browserChromeSearchEngine(name: workspace.library.searchSettings.selected.name))) {
                        addressFocused = false; browser.webView.endEditing(true); showSearchSettings = true
                    }.font(.caption).lineLimit(1).accessibilityIdentifier("browser.searchEngine.open")
                        .disabled(!workspace.available || workspace.isClearingWebsiteData)
                    Spacer()
                }.padding(.horizontal, 20)
            }
            if workspace.isClearingWebsiteData {
                ProgressView(localizer.text(.browserClearing))
                    .font(.caption).accessibilityIdentifier("browser.sites.clearing")
            }
            // Like the Play build there is no status line; only problems show.
            if let error = browser.error {
                Text(localizer.stored(error)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("browser.error")
            }
            if let notice = workspace.siteModeNoticeText {
                Text(localizer.text(notice)).font(.caption).accessibilityIdentifier("browser.siteMode.notice")
            }
            if let error = workspace.errorText {
                Text(localizer.text(error)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("browser.workspace.error")
            }
            HStack(spacing: 12) {
                Button(localizer.text(isStartPage ? .browserChromeResearch : .browserChromeResearchSite)) { addressFocused = false; showResearch = true }
                    .disabled(browser.current == nil || browser.isInteracting || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.research")
                Button(localizer.text(.browserChromeInteract)) { addressFocused = false; showInteractions = true }
                    .disabled(browser.current == nil || browser.isRunning || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.interactions")
                // After research or an action the page stays limited to that site
                // until the next manual load; this reloads it for manual browsing.
                if browser.automationOwnsDocument && !browser.isRunning && !browser.isInteracting {
                    Button(localizer.text(.browserChromeReturnManual)) { addressFocused = false; browser.returnToManualBrowsing() }
                        .accessibilityIdentifier("browser.returnToManual")
                        .disabled(workspace.isClearingWebsiteData || browser.loadedURL == nil)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 20)
            ZStack {
                BrowserWebView(webView: browser.webView, coveredByResearch: pageCovered,
                               onDetach: { [browser] in browser.setPageHostVisible(false) })
                    .id(ObjectIdentifier(browser))
                    .allowsHitTesting(!isStartPage && !browser.isRunning && !browser.isInteracting
                                      && !workspace.isClearingWebsiteData)
                    .accessibilityHidden(pageCovered)
                if isStartPage {
                    BrowserStartPageView(workspace: workspace, query: startQuery,
                        onSubmit: submitStartQuery,
                        onOpen: { url in
                            showInvalidStartInput = false; startQuery = ""; workspace.open(url)
                        })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let host = pageAskHost { pageAskBar(host: host) }
            if !isStartPage { pageToolbar }
        }
        .background(palette.background)
        .sheet(isPresented: $showResearch) {
            BrowserResearchView(browser: browser, chat: chat)
        }
        .sheet(isPresented: $showInteractions, onDismiss: { browser.cancelInteraction() }) {
            BrowserInteractionView(browser: browser, chat: chat)
        }
        .sheet(isPresented: $workspace.presentsSignIns) { WebsiteSignInsView(workspace: workspace) }
        .sheet(isPresented: $showSearchSettings) { BrowserSearchSettingsView(workspace: workspace) }
        .sheet(isPresented: $showMore) { moreSheet }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Text(localizer.text(workspace.library.userSiteModes.mode(for: browser.loadedURL?.host) == .desktop
                         ? .browserChromeCurrentDesktop : .browserChromeCurrentMobile))
                    Button(localizer.text(.browserChromeMobileWebsite)) { workspace.setManualSiteMode(.mobile) }
                        .accessibilityIdentifier("browser.siteMode.mobile")
                    Button(localizer.text(.browserChromeDesktopWebsite)) { workspace.setManualSiteMode(.desktop) }
                        .accessibilityIdentifier("browser.siteMode.desktop")
                    Text(localizer.text(.browserChromeSiteModeHelp))
                } label: {
                    Image(systemName: workspace.library.userSiteModes.mode(for: browser.loadedURL?.host) == .desktop
                          ? "desktopcomputer" : "iphone")
                }
                .accessibilityLabel(localizer.text(.browserChromeSiteMode))
                .accessibilityValue(localizer.text(workspace.library.userSiteModes.mode(for: browser.loadedURL?.host) == .desktop
                    ? .browserChromeDesktop : .browserChromeMobile))
                .accessibilityIdentifier("browser.siteMode")
                .disabled(!workspace.available || workspace.isClearingWebsiteData || browser.manualSiteModeHost == nil)
            }
        }
        .sheet(item: $browser.pageDialog, onDismiss: { browser.resolveDialog(nil) }) { dialog in
            BrowserDialogView(dialog: dialog, browser: browser)
        }
        .onAppear { workspace.activateSelected(); browser.setPageHostVisible(pageHostVisible) }
        .onDisappear { browser.setPageHostVisible(false) }
        .onChange(of: pageHostVisible) { _, visible in browser.setPageHostVisible(visible) }
        .onChange(of: addressFocused) { _, focused in
            if !focused && editingAddress { endAddressEditing() }
        }
        .onChange(of: ObjectIdentifier(browser)) { _, _ in
            showResearch = false; showInteractions = false
            showMore = false; showInvalidStartInput = false; startQuery = ""; editingAddress = false
            browser.setPageHostVisible(pageHostVisible)
        }
        .onChange(of: browser.interactionProposal?.id) { _, value in
            if value != nil && !showResearch { addressFocused = false; showInteractions = true }
        }
    }
    /// UI tests wait on the page's load state through this element; it is in
    /// DEBUG test launches only and draws nothing. People see no status text.
    @ViewBuilder private var loadObservation: some View {
        #if DEBUG
        if Self.exposesLoadObservation {
            Text(localizer.stored(browser.status))
                .font(.system(size: 1)).foregroundStyle(.clear)
                .frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("browser.status")
                .accessibilityValue(browser.manualLoadDiagnostics ?? "")
        }
        #endif
    }
    #if DEBUG
    private static let exposesLoadObservation: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestMode") || arguments.contains("-LiveModelUITest")
            || arguments.contains("-LiveBrowserUITest")
    }()
    #endif

    private var startBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(palette.tertiary)
                TextField(localizer.text(.browserChromeAddressPlaceholder), text: $startQuery)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.default).submitLabel(.go).focused($addressFocused)
                    .onSubmit { submitStartQuery() }
                    .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.address")
                if !startQuery.isEmpty {
                    Button { startQuery = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 30, height: 30) }
                        .accessibilityLabel(localizer.text(.browserChromeClearInput))
                        .accessibilityIdentifier("browser.start.clearInput")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(palette.edge, lineWidth: 0.5))
            Button { submitStartQuery() } label: { Image(systemName: "arrow.right").frame(width: 36, height: 40) }
                .accessibilityLabel(localizer.text(.browserChromeOpen))
                .accessibilityIdentifier("browser.open")
                .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
        }
    }

    /// Play's BrowserPageBar: close, the address pill, then stop while loading or reload.
    private var pageBar: some View {
        HStack(spacing: 4) {
            Button { closePage() } label: { Image(systemName: "xmark").frame(width: 36, height: 40) }
                .accessibilityLabel(localizer.text(.browserChromeClosePage))
                .accessibilityIdentifier("browser.closePage")
                .disabled(!workspace.available || workspace.isClearingWebsiteData)
            addressPill
            if browser.isRunning {
                Button { browser.cancel() } label: { Image(systemName: "stop.fill").frame(width: 36, height: 40) }
                    .accessibilityLabel(localizer.text(.browserChromeStop))
                    .accessibilityIdentifier("browser.cancel")
            } else if browser.isLoading {
                Button { browser.stopLoading() } label: { Image(systemName: "stop.fill").frame(width: 36, height: 40) }
                    .accessibilityLabel(localizer.text(.browserChromeStop))
                    .accessibilityIdentifier("browser.stop")
                    .disabled(browser.isInteracting || workspace.isClearingWebsiteData)
            } else {
                Button { browser.reloadPage() } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 40) }
                    .accessibilityLabel(localizer.text(.browserChromeReload))
                    .accessibilityIdentifier("browser.reload")
                    .disabled(browser.loadedURL == nil || browser.isInteracting || workspace.isClearingWebsiteData)
            }
        }
    }

    /// The page WebKit shows, or is loading, for the address pill.
    private var pageAddress: URL? {
        if let shown = browser.webView.url, ["https", "http"].contains(shown.scheme?.lowercased() ?? "") { return shown }
        return browser.loadedURL ?? URL(string: browser.address)
    }

    /// Like Play's AddressPill: the site name, or the words on a search results
    /// page, with a 電腦版 tag when this site uses the desktop version. Tap it to
    /// edit the full URL; its accessibility value is the full URL.
    private var addressPill: some View {
        let url = pageAddress
        let search = url.flatMap { workspace.library.searchSettings.match($0) }
        let shown = search?.query ?? url.map(Self.siteName) ?? browser.address
        let desktop = workspace.library.userSiteModes.mode(for: url?.host) == .desktop
        let desktopTag = localizer.text(.browserChromeDesktop)
        return Button { beginAddressEditing(url) } label: {
            HStack(spacing: 6) {
                if search != nil {
                    Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(palette.tertiary)
                } else if url?.scheme?.lowercased() == "https" {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(palette.tertiary)
                }
                Text(verbatim: shown).lineLimit(1).truncationMode(.tail).foregroundStyle(palette.primary)
                if desktop {
                    Text(desktopTag).font(.caption2.weight(.semibold)).foregroundStyle(Color.orange).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(palette.edge, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(desktop ? shown + " " + desktopTag : shown)
        .accessibilityValue(url?.absoluteString ?? "")
        .accessibilityHint(localizer.text(.browserChromeEditAddress))
        .accessibilityIdentifier("browser.addressPill")
        .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
    }

    /// Play's AddressEditor: the full URL, all selected, with Go; 取消 folds it back.
    private var addressEditor: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: pageAddress?.scheme?.lowercased() == "https" ? "lock.fill" : "globe")
                    .font(.caption).foregroundStyle(palette.tertiary)
                TextField(localizer.text(.browserChromeAddressPlaceholder), text: $browser.address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.default).submitLabel(.go).focused($addressFocused)
                    .onSubmit { submitPageAddress() }
                    .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.address")
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(.tint, lineWidth: 1.5))
            Button(localizer.text(.commonCancel)) { endAddressEditing() }
                .foregroundStyle(.tint)
                .padding(.horizontal, 4)
                .frame(minHeight: 40)
                .accessibilityIdentifier("browser.address.cancel")
        }
        .onAppear { DispatchQueue.main.async { addressFocused = true } }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // Select the whole URL so typing replaces it, as on Play.
            guard editingAddress, let field = note.object as? UITextField, field.text == browser.address else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            if browser.isLoading {
                Rectangle().fill(.tint)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0.05, browser.loadProgress))))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private static func siteName(_ url: URL) -> String {
        guard var host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.lowercased().hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private func pageAskBar(host: String) -> some View {
        Button {
            addressFocused = false
            showResearch = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text(localizer.text(.browserPageAskResearch))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Text(host).font(.caption).lineLimit(1)
                    .foregroundStyle(palette.secondary)
                Image(systemName: "arrow.up.right").font(.caption)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(palette.edge, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizer.text(.browserPageAskResearch))
        .accessibilityValue(host)
        .accessibilityIdentifier("browser.pageAsk.open")
        .padding(.horizontal, 12)
    }
    private var pageToolbar: some View {
        HStack {
            toolbarButton("chevron.backward", label: localizer.text(.browserChromeBack), id: "browser.back",
                          disabled: !browser.canGoBack) { browser.goBack() }
            Spacer()
            toolbarButton("chevron.forward", label: localizer.text(.browserChromeForward), id: "browser.forward",
                          disabled: !browser.canGoForward) { browser.goForward() }
            Spacer()
            toolbarButton("house", label: localizer.text(.browserChromeHome), id: "browser.home", disabled: !workspace.available,
                          allowDuringWork: true) {
                closePage()
            }
            Spacer()
            if let url = safeShareURL {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 44) }
                    .accessibilityLabel(localizer.text(.browserChromeShare))
                    .accessibilityIdentifier("browser.share")
                    .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityLabel(localizer.text(.browserChromeShareUnavailable))
                    .accessibilityIdentifier("browser.share.unavailable")
                    .foregroundStyle(palette.tertiary)
            }
            Spacer()
            toolbarButton("ellipsis", label: localizer.text(.browserChromeMore), id: "browser.more", disabled: false) {
                addressFocused = false; showMore = true
            }
        }
        .font(.system(size: 18))
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(palette.background)
        .overlay(alignment: .top) { Divider() }
    }

    private func toolbarButton(_ icon: String, label: String, id: String,
                               disabled: Bool, allowDuringWork: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 36, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(id)
            .disabled(disabled || (!allowDuringWork && (browser.isRunning || browser.isInteracting))
                      || workspace.isClearingWebsiteData)
    }

    private var safeShareURL: URL? { browser.loadedURL.flatMap(BrowserManualNavigationPolicy.libraryURL) }
    private var moreSheet: some View {
        NavigationStack {
            List {
                if let url = safeShareURL {
                    Section {
                        Text(url.host ?? localizer.text(.browserChromeWebsite)).font(.headline)
                        Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Section {
                    Button(localizer.text(.browserChromeReload)) { showMore = false; browser.reloadPage() }
                        .disabled(browser.loadedURL == nil || browser.isRunning || browser.isInteracting)
                        .accessibilityIdentifier("browser.more.reload")
                    if let url = safeShareURL {
                        Button(localizer.text(.browserChromeCopyLink)) { UIPasteboard.general.url = url; showMore = false }
                            .accessibilityIdentifier("browser.more.copy")
                        Button(localizer.text(.browserChromeOpenOutside)) {
                            guard scenePhase == .active, workspace.available,
                                  !workspace.isClearingWebsiteData else { return }
                            browser.handoffVisiblePage { destination in
                                showMore = false
                                openURL(destination)
                            }
                        }
                        .disabled(scenePhase != .active || !workspace.available
                                  || workspace.isClearingWebsiteData || browser.externalOpenURL == nil)
                        .accessibilityValue(browser.externalOpenURL?.absoluteString ?? "")
                        .accessibilityIdentifier("browser.more.openOutside")
                        if let saved = workspace.library.bookmarks.first(where: { $0.url == url }) {
                            Button(localizer.text(.browserChromeRemoveBookmark), role: .destructive) {
                                workspace.removeBookmark(saved.id); showMore = false
                            }.accessibilityIdentifier("browser.more.removeFavorite")
                        } else {
                            Button(localizer.text(.browserChromeAddBookmark)) { workspace.addBookmark(); showMore = false }
                                .disabled(!workspace.available)
                                .accessibilityIdentifier("browser.more.addFavorite")
                        }
                    }
                    if browser.manualSiteModeHost != nil {
                        let desktop = workspace.library.userSiteModes.mode(for: browser.loadedURL?.host) == .desktop
                        Button(localizer.text(desktop ? .browserChromeSwitchMobile : .browserChromeSwitchDesktop)) {
                            workspace.setManualSiteMode(desktop ? .mobile : .desktop)
                            showMore = false
                        }.accessibilityIdentifier("browser.more.siteMode")
                    }
                }
            }
            .navigationTitle(localizer.text(.browserChromeMore))
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.browserChromeDone)) { showMore = false }.accessibilityIdentifier("browser.more.close")
            } }
        }
        .presentationDetents([.medium, .large])
    }

    private func closePage() {
        editingAddress = false; addressFocused = false; browser.webView.endEditing(true)
        if workspace.closeCurrentPage() { startQuery = ""; showInvalidStartInput = false }
    }
    private func submitStartQuery() {
        let input = startQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        addressFocused = false
        browser.address = input
        browser.openAddress()
        showInvalidStartInput = browser.error != nil
        if !showInvalidStartInput { startQuery = "" }
    }
    private func beginAddressEditing(_ url: URL?) {
        if let url { browser.address = url.absoluteString }
        editingAddress = true
    }
    private func endAddressEditing() {
        editingAddress = false; addressFocused = false
        if let url = browser.loadedURL { browser.address = url.absoluteString }
    }
    private func submitPageAddress() {
        editingAddress = false; addressFocused = false
        browser.openAddress()
        // A refused address keeps the current page, like Play's toast.
        if browser.error != nil, let url = browser.loadedURL { browser.address = url.absoluteString }
    }
}

@MainActor
private struct BrowserDialogView: View {
    @Environment(\.appLocalizer) private var localizer
    let dialog: BrowserPageDialog
    @ObservedObject var browser: BrowserSession
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                Text(dialog.host).font(.caption)
                Text(verbatim: dialog.message).accessibilityIdentifier("browser.dialog.message")
                if dialog.kind == .prompt { TextField(localizer.text(.browserDialogInput), text: $text).accessibilityIdentifier("browser.dialog.input") }
                Button(localizer.text(.browserDialogOk)) { browser.resolveDialog(dialog.kind == .prompt ? text : "") }
                    .accessibilityIdentifier("browser.dialog.accept")
                if dialog.kind != .alert {
                    Button(localizer.text(.commonCancel), role: .cancel) { browser.resolveDialog(nil) }.accessibilityIdentifier("browser.dialog.cancel")
                }
            }.navigationTitle(localizer.text(.browserDialogTitle))
                .onAppear { text = dialog.initial }
        }
    }
}

@MainActor
private struct BrowserInteractionView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var browser: BrowserSession
    @ObservedObject var chat: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BrowserDOMControl?
    @State private var text = ""
    @State private var localError: String?
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(localizer.stored(browser.interactionStatus)).accessibilityIdentifier("browser.interaction.status")
                    if let error = localError ?? browser.interactionError {
                        Text(localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("browser.interaction.error")
                    }
                }
                if let proposal = browser.interactionProposal {
                    Section(localizer.text(.browserInteractionApproveTitle)) {
                        Text(localizer.text(.browserInteractionApproveNote))
                        Text(proposal.pageURL.absoluteString).font(.caption).textSelection(.enabled)
                        Text(actionLabel(proposal.request.kind))
                            .accessibilityIdentifier("browser.interaction.previewKind")
                            .accessibilityValue(proposal.request.kind.rawValue)
                        if let control = proposal.control { Text(control.label) }
                        if let value = proposal.request.text {
                            Text(value).textSelection(.enabled).accessibilityIdentifier("browser.interaction.previewText")
                        }
                        if let index = proposal.request.optionIndex,
                           let option = proposal.control?.options.first(where: { $0.index == index }) { Text(option.label) }
                        if let direction = proposal.request.direction { Text(localizer.text(direction == .down ? .browserInteractionScrollDownScreen : .browserInteractionScrollUpScreen)) }
                        if let target = proposal.control?.navigationURL {
                            Text(localizer.text(.browserInteractionNavigationMethod(method: proposal.control?.navigationMethod ?? "GET"))).font(.caption)
                            Text(target.absoluteString).font(.caption).accessibilityIdentifier("browser.interaction.previewDestination")
                        }
                        Button(localizer.text(.browserInteractionApproveOnce)) { editing = false; browser.approveInteraction(id: proposal.id) }
                            .disabled(browser.isInteracting).accessibilityIdentifier("browser.interaction.approve")
                        Button(localizer.text(.browserInteractionReject), role: .cancel) { browser.rejectInteraction() }
                            .accessibilityIdentifier("browser.interaction.reject")
                        Button(localizer.text(.browserInteractionReloadCancel)) { browser.reloadPage() }
                            .accessibilityIdentifier("browser.interaction.reload")
                    }
                } else if let control = selected {
                    Section(control.label) {
                        if control.kind == .text {
                            TextField(localizer.text(.browserInteractionTypeField), text: $text, axis: .vertical)
                                .focused($editing).accessibilityIdentifier("browser.interaction.text")
                            Text(localizer.text(.browserInteractionTypeNote))
                            Button(localizer.text(.browserInteractionProposeType)) { editing = false; propose(.type, controlID: control.id, text: text) }
                                .accessibilityIdentifier("browser.interaction.proposeType")
                        } else if control.kind == .select {
                            ForEach(control.options, id: \.index) { option in
                                Button(option.label) { propose(.select, controlID: control.id, optionIndex: option.index) }
                                    .disabled(option.disabled).accessibilityIdentifier("browser.interaction.option.\(option.index)")
                            }
                        }
                        Button(localizer.text(.browserInteractionBackToControls)) { editing = false; selected = nil }.accessibilityIdentifier("browser.interaction.back")
                    }
                } else {
                    Section(localizer.text(.browserInteractionNextAction)) {
                        TextField(localizer.text(.browserInteractionGoal), text: $browser.interactionGoal, axis: .vertical)
                            .focused($editing).accessibilityIdentifier("browser.interaction.goal")
                        Button(localizer.text(.browserInteractionAskModel)) { editing = false; browser.requestModelInteraction(using: chat) }
                            .disabled(browser.isInteracting || !chat.hasStoredKey || browser.interactionGoal.isEmpty)
                            .accessibilityIdentifier("browser.interaction.plan")
                        Text(localizer.text(.browserInteractionAskModelNote))
                    }
                    Section(localizer.text(.browserInteractionManual)) {
                        Button(localizer.text(.browserInteractionRefresh)) { browser.refreshControls() }
                            .disabled(browser.isInteracting).accessibilityIdentifier("browser.interaction.refresh")
                        if let snapshot = browser.controlSnapshot {
                            Button(localizer.text(.browserInteractionScrollDown)) { propose(.scroll, direction: .down) }.accessibilityIdentifier("browser.interaction.scrollDown")
                            Button(localizer.text(.browserInteractionScrollUp)) { propose(.scroll, direction: .up) }.accessibilityIdentifier("browser.interaction.scrollUp")
                            ForEach(snapshot.controls) { control in
                                Button(control.label) {
                                    localError = nil
                                    if control.kind == .text || control.kind == .select { selected = control; text = "" }
                                    else { propose(.click, controlID: control.id) }
                                }
                                .disabled(!control.enabled || browser.isInteracting)
                                .accessibilityIdentifier("browser.control.\(control.id)")
                            }
                            if snapshot.truncated { Text(localizer.text(.browserInteractionTruncated)) }
                        }
                    }
                }
                if browser.isInteracting {
                    Button(localizer.text(.browserInteractionStop)) { browser.cancelInteraction() }.accessibilityIdentifier("browser.interaction.stop")
                }
            }
            .navigationTitle(localizer.text(.browserInteractionTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonClose)) { browser.cancelInteraction(); dismiss() }.accessibilityIdentifier("browser.interaction.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button(localizer.text(.keyboardDone)) { editing = false }.accessibilityIdentifier("browser.interaction.done")
                }
            }
            .task { if browser.controlSnapshot == nil && browser.interactionProposal == nil { browser.refreshControls() } }
            .onChange(of: browser.controlSnapshot?.snapshotID) { _, snapshotID in
                if snapshotID == nil {
                    // Background/settings cancellation or navigation can
                    // invalidate the selected editor without dismissing the
                    // sheet. Return to refresh instead of leaving dead fields.
                    selected = nil; editing = false; localError = nil
                }
            }
        }
    }
    private func propose(_ kind: BrowserInteractionKind, controlID: String? = nil, text: String? = nil,
                         optionIndex: Int? = nil, direction: BrowserScrollDirection? = nil) {
        guard let snapshot = browser.controlSnapshot else { return }
        do {
            _ = try browser.proposeInteraction(BrowserInteractionRequest(documentID: snapshot.documentID,
                snapshotID: snapshot.snapshotID, kind: kind, controlID: controlID, text: text, optionIndex: optionIndex, direction: direction))
            selected = nil; localError = nil
        } catch { localError = (error as? BrowserInteractionError)?.message ?? BrowserInteractionError.invalidRequest.message }
    }
    private func actionLabel(_ kind: BrowserInteractionKind) -> String {
        switch kind {
        case .click: return localizer.text(.browserInteractionKindClick)
        case .type: return localizer.text(.browserInteractionKindType)
        case .select: return localizer.text(.browserInteractionKindSelect)
        case .scroll: return localizer.text(.browserInteractionKindScroll)
        }
    }
}

// A presented sheet owns its focus binding. Sharing a FocusState from the
// presenting browser leaves the multiline editor focused on iOS 26.
@MainActor
private struct BrowserResearchView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var browser: BrowserSession
    @ObservedObject var chat: ChatSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var goalFocused: Bool

    var body: some View {
        NavigationStack {
                Form {
                    Section(localizer.text(.browserResearchTitle)) {
                        Text(localizer.text(.browserResearchNote))
                        TextField(localizer.text(.browserResearchGoal), text: $browser.goal, axis: .vertical)
                            .focused($goalFocused)
                            .disabled(browser.isRunning).accessibilityIdentifier("browser.goal")
                        Button(localizer.text(.browserResearchStart)) { goalFocused = false; browser.beginResearch(using: chat) }
                            .disabled(browser.isRunning || browser.goal.isEmpty || !chat.hasStoredKey)
                            .accessibilityIdentifier("browser.start")
                        if browser.isRunning {
                            Button(localizer.text(.browserResearchStop)) { browser.cancel() }.accessibilityIdentifier("browser.task.cancel")
                        }
                        Text(localizer.stored(browser.status)).accessibilityIdentifier("browser.task.status")
                    }
                    if let answer = browser.answer {
                        Section(localizer.text(.browserResearchResult)) { Text(localizer.stored(answer)).textSelection(.enabled).accessibilityIdentifier("browser.answer") }
                    }
                    if let status = browser.learningStatus {
                        Section(localizer.text(.browserResearchLearning)) { Text(localizer.stored(status)).accessibilityIdentifier("browser.learning") }
                    }
                    Section(localizer.text(.browserResearchReads(count: browser.actions.count))) {
                        ForEach(Array(browser.actions.enumerated()), id: \.offset) { _, action in
                            VStack(alignment: .leading) {
                                Text(action.observation.title)
                                Text(action.observation.url.absoluteString).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
                .navigationTitle(localizer.text(.browserResearchTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(localizer.text(.commonDone)) { dismiss() }.accessibilityIdentifier("browser.research.close") }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(localizer.text(.keyboardDone)) { goalFocused = false }.accessibilityIdentifier("browser.goal.done")
                    }
                }
        }
    }
}

@MainActor
private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    let coveredByResearch: Bool
    let onDetach: () -> Void
    func makeUIView(context: Context) -> BrowserWebContainer {
        let container = BrowserWebContainer(webView: webView, onDetach: onDetach)
        container.setCoveredByResearch(coveredByResearch)
        return container
    }
    func updateUIView(_ uiView: BrowserWebContainer, context: Context) {
        uiView.setCoveredByResearch(coveredByResearch)
    }
    static func dismantleUIView(_ uiView: BrowserWebContainer, coordinator: Void) {
        uiView.detachWebView()
    }
}
