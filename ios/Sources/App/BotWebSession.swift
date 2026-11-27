#if WOOWTECHBOT
import AssistantBrowser
import AssistantPersistence
import Combine
import SwiftUI
import WebKit

@MainActor final class BotWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    let service: BotServiceRecord
    let webView: WKWebView
    let downloads: BrowserDownloadManager
    @Published private(set) var loading = true
    @Published private(set) var failed = false
    @Published var externalURL: URL?
    @Published var dialog: BotWebDialog?
    @Published private(set) var workspaceControlsReady = false
    @Published var presentationAction: BotWorkspaceAction?
    private var valid = true
    private var downloadUntil = Date.distantPast

    init(service: BotServiceRecord, dataStore: WKWebsiteDataStore) {
        self.service = service
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = false
        webView.allowsBackForwardNavigationGestures = true
        webView.accessibilityIdentifier = "bot.webview"
        webView.accessibilityValue = service.origin
        downloads = BrowserDownloadManager(root: PendingFileFolder.live("BotDownloads/" + service.profileID.uuidString).root,
                                            allowsURL: service.policy.allows)
        super.init()
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        webView.navigationDelegate = self; webView.uiDelegate = self
        open(service.policy.url)
    }

    func open(_ url: URL) {
        guard valid, service.policy.allows(url) else { return }
        failed = false; loading = true; workspaceControlsReady = false; downloadUntil = .distantPast
        webView.load(URLRequest(url: url))
    }
    func retry() { open(service.policy.url) }
    func invalidate() {
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        valid = false; workspaceControlsReady = false; presentationAction = nil
        webView.stopLoading(); downloads.cancelAll()
        for item in downloads.items where !item.phase.isActive { downloads.remove(item.id) }
        dialog?.finish(nil); dialog = nil; externalURL = nil
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
    }
    /// What shows until the page paints (Android sets the WebView to the same): #121212 on Midnight, #FCFCFC on Daylight.
    static let prePaintColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
                                           : UIColor(red: 252 / 255, green: 252 / 255, blue: 252 / 255, alpha: 1)
    }
    /// A function body for callAsyncJavaScript: true only when a sidebar slot of the app holds both controls.
    private static let controlsInstalledProbe =
        "return Array.from(document.querySelectorAll('[data-look=\"app\"] [data-sidebar-top-slot]')).some(function (slot) { var controls = slot.querySelector(':scope > .woow-workspace-controls'); return !!controls && ['services', 'notifications'].every(function (action) { return !!controls.querySelector('a[href=\"woowtech-ui://' + action + '\"]'); }); });"

    func refreshWorkspaceAppearance(dark: Bool, localizer: AppLocalizer) async {
        guard valid, !loading, !failed, let url = webView.url, service.policy.allows(url),
              let script = BotWorkspaceScript.source(dark: dark, localizer: localizer) else {
            if workspaceControlsReady { workspaceControlsReady = false }; return
        }
        webView.isOpaque = false
        let pre = Self.prePaintColor
        webView.backgroundColor = pre
        webView.scrollView.backgroundColor = pre
        // This isolated script changes presentation only; the page cannot call
        // native methods or read any native data through it.
        // Inject (idempotent), then ask separately whether complete controls are installed:
        // the injection's own completion value is not delivered reliably through this API.
        _ = try? await webView.evaluateJavaScript(script, in: nil, in: .defaultClient)
        let probe = try? await webView.callAsyncJavaScript(Self.controlsInstalledProbe, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard valid, !Task.isCancelled, !loading, webView.url == url else { return }
        let ready = (probe as? Bool) == true || (probe as? NSNumber)?.boolValue == true
        if workspaceControlsReady != ready { workspaceControlsReady = ready }
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            guard self?.valid == true, BotPushController.shared.optedIn else { return }
            BotPushController.shared.schedule()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard valid, let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "woowtech-ui" {
            presentationAction = BotWorkspaceAction.parse(url.absoluteString, service: service,
                source: action.sourceFrame.request.url, current: webView.url,
                mainFrame: action.sourceFrame.isMainFrame && action.targetFrame?.isMainFrame == true,
                linkActivated: action.navigationType == .linkActivated)
            decisionHandler(.cancel); return
        }
        let own = service.policy.allows(url)
        // Cross-origin subframes remain ordinary HTTPS web content with no
        // native authority; main-frame navigation is always exact-origin.
        if action.targetFrame?.isMainFrame == false {
            decisionHandler(own || (url.scheme == "https" && url.user == nil && url.password == nil) ? .allow : .cancel)
            return
        }
        guard own else {
            if action.navigationType == .linkActivated, url.scheme == "https", url.user == nil, url.password == nil,
               action.sourceFrame.request.url.map(service.policy.allows) == true {
                externalURL = url
            }
            decisionHandler(.cancel); return
        }
        if action.navigationType == .linkActivated { downloadUntil = Date().addingTimeInterval(15) }
        if action.targetFrame == nil {
            decisionHandler(.cancel); webView.load(action.request); return
        }
        if action.shouldPerformDownload {
            decisionHandler(Date() < downloadUntil ? .download : .cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard valid else { decisionHandler(.cancel); return }
        if response.isForMainFrame && !response.canShowMIMEType {
            decisionHandler(response.response.url.map(service.policy.allows) == true && Date() < downloadUntil ? .download : .cancel)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        receive(download, url: navigationAction.request.url)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        receive(download, url: navigationResponse.response.url)
    }
    private func receive(_ download: WKDownload, url: URL?) {
        guard valid, Date() < downloadUntil else { download.cancel(nil); return }
        downloadUntil = .distantPast; loading = false
        downloads.accept(download, from: url)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; failed = false; workspaceControlsReady = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        if BotPushController.shared.optedIn { BotPushController.shared.schedule() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard valid, (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; failed = true; workspaceControlsReady = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; failed = true; workspaceControlsReady = false }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        var c = URLComponents(); c.scheme = origin.protocol; c.host = origin.host
        c.port = origin.port == 0 ? nil : origin.port
        let allowed = valid && c.url.map(service.policy.allows) == true && frame.request.url.map(service.policy.allows) == true
        decisionHandler(allowed ? .prompt : .deny)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard valid, frame.request.url.map(service.policy.allows) == true else { completionHandler(); return }
        dialog?.finish(nil)
        dialog = .init(message: message, kind: .alert, finish: { _ in completionHandler() })
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard valid, frame.request.url.map(service.policy.allows) == true else { completionHandler(false); return }
        dialog?.finish(nil)
        dialog = .init(message: message, kind: .confirm, finish: { completionHandler($0 != nil) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard valid, frame.request.url.map(service.policy.allows) == true else { completionHandler(nil); return }
        dialog?.finish(nil)
        dialog = .init(message: prompt, kind: .input(defaultText ?? ""), finish: completionHandler)
    }
}

struct BotWebDialog: Identifiable {
    enum Kind { case alert, confirm, input(String) }
    let id = UUID()
    let message: String
    let kind: Kind
    let finish: (String?) -> Void
}

private struct BotWebSurface: UIViewRepresentable {
    let session: BotWebSession
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ container: UIView, context: Context) {
        let web = session.webView
        container.accessibilityIdentifier = "bot.surface.\(session.service.id)"
        container.backgroundColor = BotWebSession.prePaintColor
        web.isOpaque = false
        web.backgroundColor = BotWebSession.prePaintColor
        web.scrollView.backgroundColor = BotWebSession.prePaintColor
        guard container.subviews.first !== web else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        web.removeFromSuperview()
        web.frame = container.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(web)
    }
    static func dismantleUIView(_ container: UIView, coordinator: ()) {
        // Remove only children still owned by THIS presentation. A cached WKWebView
        // might already have been mounted in a newer presentation during dismissal.
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}

struct BotServiceScreen: View {
    @ObservedObject var web: BotWebSession
    @ObservedObject var chat: ChatSession
    @ObservedObject var notifications: TaskNotificationStore
    let localizer: AppLocalizer
    let close: () -> Void
    let attach: (URL) async -> Bool
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var showsDownloads = false
    @State private var showsPairing = false
    @State private var promptText = ""
    @State private var showsServices = false
    @State private var showsNotifications = false
    @State private var showsManage = false
    @State private var retiring: Retirement?
    @State private var busy = false
    @State private var serviceFollowUp: ServiceFollowUp?
    private enum ServiceFollowUp { case local, service(UUID, manage: Bool), manage, downloads, pairing }
    private struct Retirement: Identifiable { let remove: Bool; var id: Bool { remove } }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private var palette: MikaVisualPalette { MikaVisualPalette(colorScheme) }
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }

    var body: some View {
        NavigationStack {
            ZStack {
                // The page colour fills the status-bar and home-indicator strips around the website (Android: the Scaffold's colour).
                palette.background.ignoresSafeArea()
                BotWebSurface(session: web).id(web.service.profileID)
                if web.failed {
                    // Android: a status line with a text button to retry; the rest of the page stays the page colour.
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text(t("無法載入服務，請檢查網址與網路後重試。", "Unable to load the service. Check the address and network, then retry."))
                                .scaledFont(size: 13).foregroundStyle(palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                            Button(t("重試", "Retry"), action: web.retry).scaledFont(size: 14, weight: .medium)
                                .foregroundStyle(palette.accent).accessibilityIdentifier("bot.retry")
                        }.padding(12)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(palette.background)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if web.loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("bot.loading") }
            }
            // Android's fallback bar (shown until the website's own sidebar takes over): the name, the service switcher
            // and the manage sheet. iOS has no system back, so the way out of the service stays on the left.
            .navigationTitle(web.service.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Android: the name on one line, the address in small type under it.
                    VStack(spacing: 0) {
                        Text(web.service.name).font(.headline).lineLimit(1)
                        Text(web.service.origin).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: close) { Label(t("返回", "Back"), systemImage: "chevron.backward") }
                        .accessibilityIdentifier("bot.back")
                    Button(t("服務", "Services")) { showsServices = true }.accessibilityIdentifier("bot.switch")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("更多", "More")) { showsManage = true }.accessibilityIdentifier("bot.menu")
                }
            }
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbar(web.workspaceControlsReady ? .hidden : .visible, for: .navigationBar)
            .tint(palette.accent)
        }
        .modifier(BrowserDownloadPresentations(manager: web.downloads, chat: chat, showsList: $showsDownloads,
                                               localizer: localizer, attach: attach))
        .task(id: "\(colorScheme)-\(scenePhase)-\(localizer.language)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await web.refreshWorkspaceAppearance(dark: colorScheme == .dark, localizer: localizer)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onAppear {
            // A service's own "…" in the switcher opens this screen with its manage sheet.
            if workspace.manageOnOpen { workspace.manageOnOpen = false; showsManage = true }
        }
        .onChange(of: web.presentationAction) { _, action in
            guard let action else { return }; web.presentationAction = nil
            guard !showsServices, !showsNotifications, !showsPairing, !showsDownloads, !showsManage,
                  web.dialog == nil, web.externalURL == nil, retiring == nil else { return }
            switch action {
            case .services: showsServices = true
            case .notifications: showsNotifications = true
            }
        }
        .sheet(isPresented: $showsServices, onDismiss: finishServiceSwitch) {
            BotServicesSheet(workspace: workspace, localizer: localizer, selectedID: web.service.id,
                             onLocal: { queue(.local) },
                             onOpen: { id in if id == web.service.id { showsServices = false } else { queue(.service(id, manage: false)) } },
                             onManage: { id in if id == web.service.id { queue(.manage) } else { queue(.service(id, manage: true)) } },
                             onClose: { showsServices = false })
        }
        .sheet(isPresented: $showsNotifications) {
            BotNotificationsSheet(localizer: localizer) { showsNotifications = false }
        }
        .sheet(isPresented: $showsManage, onDismiss: finishServiceSwitch) {
            BotManageSheet(service: web.service, localizer: localizer,
                           scan: { queue(.pairing) }, reload: { showsManage = false; web.retry() },
                           downloads: { queue(.downloads) },
                           disconnect: { showsManage = false; try? workspace.setEnabled(web.service.id, false) },
                           logout: { showsManage = false; retiring = .init(remove: false) },
                           remove: { showsManage = false; retiring = .init(remove: true) },
                           close: { showsManage = false })
        }
        .sheet(isPresented: $showsPairing) {
            BotPairingView(service: web.service, localizer: localizer, connect: web.open)
        }
        .botDialog(isPresented: retiring != nil || web.externalURL != nil, dismiss: { retiring = nil; web.externalURL = nil }) {
            if let retiring {
                BotRetireDialog(remove: retiring.remove, localizer: localizer, confirm: { retire(retiring) }, cancel: { self.retiring = nil })
            } else if let url = web.externalURL {
                BotDialogSurface {
                    BotDialogTitle(text: t("在外部瀏覽器開啟連結？", "Open link in your browser?"))
                    BotDialogBody(text: url.host ?? "")
                    HStack(spacing: 10) {
                        BotDialogButton(title: t("取消", "Cancel"), kind: .dismiss, identifier: "bot.external.cancel") { web.externalURL = nil }
                        BotDialogButton(title: t("開啟", "Open"), kind: .confirm, identifier: "bot.external.open") { openURL(url); web.externalURL = nil }
                    }.padding(.top, 24)
                }
            }
        }
        .disabled(busy)
        .alert(web.service.name, isPresented: Binding(get: { web.dialog != nil }, set: { _ in }), presenting: web.dialog) { dialog in
            if case .input = dialog.kind { TextField(t("輸入內容", "Input"), text: $promptText) }
            Button(t("確認", "OK")) { dialog.finish(promptText); web.dialog = nil; promptText = "" }
            if case .alert = dialog.kind {} else {
                Button(t("取消", "Cancel"), role: .cancel) { dialog.finish(nil); web.dialog = nil; promptText = "" }
            }
        } message: { Text(String($0.message.prefix(4000))) }
        .onChange(of: web.dialog?.id) { _, _ in
            if case .input(let value) = web.dialog?.kind { promptText = value }
        }
    }

    private func retire(_ action: Retirement) {
        retiring = nil; busy = true
        Task {
            defer { busy = false }
            do { try await workspace.retire(web.service.id, remove: action.remove) }
            catch { workspace.notice = .changesUnsaved }
        }
    }
    private func queue(_ followUp: ServiceFollowUp) {
        serviceFollowUp = followUp
        if showsManage { showsManage = false }
        if showsServices { showsServices = false }
    }
    private func finishServiceSwitch() {
        guard let action = serviceFollowUp else { return }; serviceFollowUp = nil
        switch action {
        case .local: close()
        case .service(let id, let manage): workspace.manageOnOpen = manage; workspace.selectedService = id
        case .manage: showsManage = true
        case .downloads: showsDownloads = true
        case .pairing: showsPairing = true
        }
    }
}
#endif
