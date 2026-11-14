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
    private var pageFindHostVisible: Bool {
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
            HStack(spacing: 8) {
                if !isStartPage {
                    Button { closePage() } label: { Image(systemName: "xmark").frame(width: 36, height: 40) }
                        .accessibilityLabel(localizer.text(.browserChromeClosePage))
                        .accessibilityIdentifier("browser.closePage")
                        .disabled(!workspace.available || workspace.isClearingWebsiteData)
                }
                HStack(spacing: 8) {
                    Image(systemName: isStartPage ? "magnifyingglass" :
                          (browser.loadedURL?.scheme == "https" ? "lock.fill" : "globe"))
                        .font(.caption).foregroundStyle(palette.tertiary)
                    if isStartPage {
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
                    } else {
                        TextField(localizer.text(.browserChromeAddressPlaceholder), text: $browser.address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.default).submitLabel(.go).focused($addressFocused)
                            .onSubmit { open() }
                            .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
                            .accessibilityIdentifier("browser.address")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: isStartPage ? 52 : 40)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().stroke(palette.edge, lineWidth: 0.5))
                if !isStartPage {
                    if browser.isRunning {
                        Button { browser.cancel() } label: { Image(systemName: "stop.fill").frame(width: 36, height: 40) }
                            .accessibilityLabel(localizer.text(.browserChromeStop))
                            .accessibilityIdentifier("browser.cancel")
                    } else {
                        Button { browser.reloadPage() } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 40) }
                            .accessibilityLabel(localizer.text(.browserChromeReload))
                            .accessibilityIdentifier("browser.reload")
                            .disabled(browser.loadedURL == nil || browser.isInteracting || workspace.isClearingWebsiteData)
                    }
                }
                Button { isStartPage ? submitStartQuery() : open() } label: { Image(systemName: "arrow.right").frame(width: 36, height: 40) }
                    .accessibilityLabel(localizer.text(.browserChromeOpen))
                    .accessibilityIdentifier("browser.open")
                    .disabled(browser.isRunning || browser.isInteracting || workspace.isClearingWebsiteData)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, isStartPage ? 12 : 4)
            if !isStartPage {
                Group {
                    if browser.webView.isLoading { ProgressView().progressViewStyle(.linear) }
                    else { Color.clear }
                }
                .frame(height: 2)
            }
            HStack {
                Button(localizer.text(.browserChromeSearchEngine(name: workspace.library.searchSettings.selected.name))) {
                    addressFocused = false; browser.webView.endEditing(true); showSearchSettings = true
                }.font(.caption).lineLimit(1).accessibilityIdentifier("browser.searchEngine.open")
                    .disabled(!workspace.available || workspace.isClearingWebsiteData)
                Spacer()
            }.padding(.horizontal, 20)
            if let match = browser.manualSearchMatch {
                Text(localizer.text(.browserChromeSearchMatch(query: match.query, engine: match.engineName)))
                    .font(.caption).lineLimit(2).accessibilityIdentifier("browser.search.query")
            }
            if workspace.isClearingWebsiteData {
                ProgressView(localizer.text(.browserClearing))
                    .font(.caption).accessibilityIdentifier("browser.sites.clearing")
            }
            if let diagnostics = browser.manualLoadDiagnostics {
                Text(localizer.stored(browser.status)).font(.caption).accessibilityIdentifier("browser.status")
                    .accessibilityValue(diagnostics)
            } else {
                Text(localizer.stored(browser.status)).font(.caption).accessibilityIdentifier("browser.status")
            }
            if let error = browser.error {
                Text(localizer.stored(error)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("browser.error")
            }
            if let notice = workspace.siteModeNoticeText {
                Text(localizer.text(notice)).font(.caption).accessibilityIdentifier("browser.siteMode.notice")
            }
            if let error = workspace.errorText {
                Text(localizer.text(error)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("browser.workspace.error")
            }
            if browser.automationOwnsDocument && !browser.isRunning && !browser.isInteracting {
                HStack {
                    Text(localizer.text(.browserChromeAutomationNotice)).font(.caption)
                    Button(localizer.text(.browserChromeReturnManual)) { addressFocused = false; browser.returnToManualBrowsing() }
                        .accessibilityIdentifier("browser.returnToManual")
                        .disabled(workspace.isClearingWebsiteData || browser.loadedURL == nil)
                }.padding(.horizontal)
            }
            HStack(spacing: 12) {
                Button(localizer.text(isStartPage ? .browserChromeResearch : .browserChromeResearchSite)) { addressFocused = false; showResearch = true }
                    .disabled(browser.current == nil || browser.isInteracting || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.research")
                Button(localizer.text(.browserChromeInteract)) { addressFocused = false; showInteractions = true }
                    .disabled(browser.current == nil || browser.isRunning || workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("browser.interactions")
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 20)
            ZStack {
                BrowserWebView(webView: browser.webView, coveredByResearch: pageCovered,
                               onDetach: { [browser] in browser.setPageFindHostVisible(false) })
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
            Text(localizer.text(.browserChromeExplanation))
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
                .accessibilityIdentifier("browser.explanation")
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
        .onAppear { workspace.activateSelected(); browser.setPageFindHostVisible(pageFindHostVisible) }
        .onDisappear { browser.setPageFindHostVisible(false) }
        .onChange(of: pageFindHostVisible) { _, visible in browser.setPageFindHostVisible(visible) }
        .onChange(of: ObjectIdentifier(browser)) { _, _ in
            showResearch = false; showInteractions = false
            showMore = false; showInvalidStartInput = false; startQuery = ""
            browser.setPageFindHostVisible(pageFindHostVisible)
        }
        .onChange(of: browser.interactionProposal?.id) { _, value in
            if value != nil && !showResearch { addressFocused = false; showInteractions = true }
        }
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
        addressFocused = false; browser.webView.endEditing(true)
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
    private func open() { addressFocused = false; browser.openAddress() }
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
