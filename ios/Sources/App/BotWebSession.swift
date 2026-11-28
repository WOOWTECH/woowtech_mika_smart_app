#if WOOWTECHBOT
import AssistantBrowser
import AssistantPersistence
import Combine
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import WebKit

/// What the transition page says while a service opens: its bot list, a push target's conversation, a reload, or the page
/// the app was left on (reopened after the app was closed, owner 2026-11-28 as Android woow.26).
enum BotTransitionText { case list, chat, reload, resume }

@MainActor final class BotWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    let service: BotServiceRecord
    let webView: WKWebView
    let downloads: BrowserDownloadManager
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published var externalURL: URL?
    @Published var dialog: BotWebDialog?
    @Published private(set) var workspaceControlsReady = false
    @Published var presentationAction: BotWorkspaceAction?
    /// Owner 2026-11-27: no connecting screen and no bare bar with the address while a service opens; a transition page
    /// covers them (nil once the page shows). Opening or switching to a service lands on its bot list (`landOnList`): the
    /// phone website always starts on the selected bot's chat with its list closed, so the list is opened once with the
    /// site's own button. A push target and a reload keep the page the website shows.
    @Published private(set) var cover: BotTransitionText?
    /// Restarts the screen's polling of the page whenever a transition begins.
    @Published private(set) var transitionID = 0
    private(set) var landOnList = false
    private(set) var started = false
    /// Main-frame documents committed in this web view; a transition only reads pages committed after `transitionFrom`.
    private var pageCommits = 0
    private var transitionFrom = 0
    private var finishedAt: Date?
    /// The first touch on the page after the reveal stops the list from being reopened against the user.
    var touchedAt = Date.distantPast
    var sceneActive = true
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
    }

    func open(_ url: URL) {
        guard valid, service.policy.allows(url) else { return }
        started = true
        failed = false; loading = true; workspaceControlsReady = false; downloadUntil = .distantPast
        webView.load(URLRequest(url: url))
    }
    /// Opening the service, switching to it or reconnecting it: its root loads behind the transition page (a kept page
    /// too, which would otherwise show whatever it was left on) and the bot list opens.
    func openList() { begin(.list, list: true); open(service.policy.url) }
    /// A push target keeps the conversation the website opens for it.
    func openTarget(_ url: URL) { begin(.chat, list: false); open(url) }
    func retry() { begin(.reload, list: false); open(service.policy.url) }
    /// Reopening the app after it was closed while this service was shown: the website shows its last bot (no list).
    func openResume() { begin(.resume, list: false); open(service.policy.url) }
    private func begin(_ text: BotTransitionText, list: Bool) {
        landOnList = list; cover = text; transitionFrom = pageCommits; transitionID += 1
    }

    /// While the transition page is up the page is asked every 0.2 s what it shows (structure only). It goes when the bot
    /// list is open, or the page is a sign-in page or not a woowtechbot workspace, or after 20 s. For 2.5 s after that the
    /// list is opened again if the website closes it by itself (until the first touch). After a sign-in page, or a
    /// workspace still starting or connecting at 20 s, the list is still opened once, when the workspace appears.
    func runTransition(dark: Bool, localizer: AppLocalizer) async {
        let id = transitionID, started = Date()
        var openSeen = 0
        var emptySince: Date?
        var settleFrom: Date?
        var last: String?
        while valid, transitionID == id, cover != nil || landOnList {
            do { try await Task.sleep(for: cover != nil || settleFrom != nil ? .milliseconds(200) : .seconds(1)) } catch { return }
            guard valid, transitionID == id, sceneActive else { continue }
            let now = Date()
            if let settleFrom, touchedAt > settleFrom || now.timeIntervalSince(settleFrom) > 2.5 { landOnList = false; break }
            if failed || now.timeIntervalSince(started) > 600 { landOnList = false; cover = nil; break }
            if cover != nil, now.timeIntervalSince(started) > 20 {
                cover = nil; if last != "boot" && last != "connecting" { landOnList = false }
            }
            guard pageCommits > transitionFrom else { continue }
            await refreshWorkspaceAppearance(dark: dark, localizer: localizer)
            let shown = await workspaceList(open: landOnList)
            // A reload or another opening began meanwhile: its own poll decides from now on.
            guard transitionID == id else { return }
            if let shown { last = shown }
            if shown != "app" { emptySince = nil }
            switch shown {
            case "form": cover = nil
            case "none": if let finishedAt, now.timeIntervalSince(finishedAt) > 4 { landOnList = false; cover = nil }
            // The app without bots in its list and without its loading screen (an onboarding page, say) shows after 5 s.
            case "app":
                if let emptySince { if now.timeIntervalSince(emptySince) > 5 { landOnList = false; cover = nil } } else { emptySince = now }
            case "wide", "closed": landOnList = false; cover = nil
            case "opening": openSeen = 0
            case "open":
                if !landOnList { cover = nil }
                else { openSeen += 1; if openSeen >= 2, settleFrom == nil { cover = nil; settleFrom = now } }
            default: break
            }
        }
    }

    private static let listTemplate: String? = {
        guard let url = Bundle.main.url(forResource: "workspace-list", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    /// Runs the fixed list script (structure only; its one action is the site's own list button) on the service's own
    /// shown page; nil when the page changed or went away meanwhile.
    private func workspaceList(open: Bool) async -> String? {
        guard valid, let template = Self.listTemplate, let url = webView.url, service.policy.allows(url) else { return nil }
        let page = pageCommits
        // Parenthesised: the script starts with a block comment over several lines, which would end a bare `return`.
        let body = "return (" + template.replacingOccurrences(of: "__WOOW_OPEN__", with: open ? "true" : "false") + "\n);"
        let result = try? await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard valid, pageCommits == page, webView.url == url else { return nil }
        return result as? String
    }
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
        let page = pageCommits
        // This isolated script changes presentation only; the page cannot call
        // native methods or read any native data through it.
        // Inject (idempotent), then ask separately whether complete controls are installed:
        // the injection's own completion value is not delivered reliably through this API.
        _ = try? await webView.evaluateJavaScript(script, in: nil, in: .defaultClient)
        let probe = try? await webView.callAsyncJavaScript(Self.controlsInstalledProbe, arguments: [:], in: nil, contentWorld: .defaultClient)
        // An answer counts only for the page it was asked on.
        guard valid, !Task.isCancelled, !loading, webView.url == url, pageCommits == page else { return }
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
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageCommits += 1; finishedAt = nil
        // A sign-in page was shown; the next page is the workspace, whose list opens behind the transition page. On the
        // commit, not the start: a download or an empty answer never commits and leaves the shown page as it is.
        if cover == nil, landOnList { begin(.list, list: true); transitionFrom = pageCommits - 1 }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; finishedAt = Date()
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

/// Notes each touch on the page without taking it (it fails at once), like Android's initial-pass pointer input.
private final class BotTouchRecorder: UIGestureRecognizer {
    var touched: () -> Void = {}
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { touched(); state = .failed }
}

private struct BotWebSurface: UIViewRepresentable {
    let session: BotWebSession
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let recorder = BotTouchRecorder(target: nil, action: nil)
        recorder.cancelsTouchesInView = false; recorder.delaysTouchesBegan = false; recorder.delaysTouchesEnded = false
        container.addGestureRecognizer(recorder)
        return container
    }
    func updateUIView(_ container: UIView, context: Context) {
        let web = session.webView
        for case let recorder as BotTouchRecorder in container.gestureRecognizers ?? [] {
            recorder.touched = { [weak session] in session?.touchedAt = Date() }
        }
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
        ZStack {
            // The page colour fills the status-bar and home-indicator strips around the website (Android: the Scaffold's colour).
            palette.background.ignoresSafeArea()
            // Under the transition page the page is not there for VoiceOver either.
            BotWebSurface(session: web).id(web.service.profileID).accessibilityHidden(web.cover != nil)
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
            if web.cover == nil {
                VStack(spacing: 0) {
                    if !web.workspaceControlsReady { header }
                    if web.loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("bot.loading") }
                }
            }
        }
        .overlay {
            // It covers at once and fades out onto the bot list (Android: no enter transition, a 220 ms fade-out).
            ZStack {
                if let cover = web.cover {
                    BotServiceTransition(name: web.service.name, text: transitionText(cover), backLabel: t("返回", "Back"), back: close)
                        .transition(BotCoverTransition())
                }
            }.animation(.easeOut(duration: 0.22), value: web.cover == nil)
        }
        .tint(palette.accent)
        .modifier(BrowserDownloadPresentations(manager: web.downloads, chat: chat, showsList: $showsDownloads,
                                               localizer: localizer, attach: attach))
        .task(id: web.transitionID) { await web.runTransition(dark: colorScheme == .dark, localizer: localizer) }
        .onChange(of: scenePhase, initial: true) { _, phase in web.sceneActive = phase == .active }
        .task(id: "\(colorScheme)-\(scenePhase)-\(localizer.language)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await web.refreshWorkspaceAppearance(dark: colorScheme == .dark, localizer: localizer)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onAppear {
            // Every way in opens a page (`BotWorkspaceStore.openService`, a push target); this only guards a page never opened.
            if !web.started { web.openList() }
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

    /// A page that is not the woowtechbot workspace (sign-in, other sites) keeps a bar of its own in the app's style (Android):
    /// services, the name and address, more. iOS has no system back, so the way out of the service stays on the left.
    private var header: some View {
        HStack(spacing: 0) {
            BotRoundButton(symbol: "chevron.left", label: t("返回", "Back"), identifier: "bot.back", action: close)
            BotRoundButton(symbol: "arrow.left.arrow.right", label: t("服務", "Services"), identifier: "bot.switch") { showsServices = true }
            VStack(spacing: 0) {
                Text(web.service.name).scaledFont(size: 15, weight: .semibold).foregroundStyle(palette.ink)
                Text(web.service.origin).scaledFont(size: 12).foregroundStyle(palette.hintInk)
            }
            .lineLimit(1).frame(maxWidth: .infinity).padding(.horizontal, 8).accessibilityElement(children: .combine)
            BotRoundButton(symbol: "ellipsis", label: t("更多", "More"), identifier: "bot.menu") { showsManage = true }
        }
        .padding(.horizontal, 8).frame(minHeight: 64).background(palette.background)
    }
    private func transitionText(_ cover: BotTransitionText) -> String {
        switch cover {
        case .list: t("正在打開機器人列表…", "Opening the bot list…")
        case .chat: t("正在打開對話…", "Opening the conversation…")
        case .reload: t("正在重新載入…", "Reloading…")
        case .resume: t("正在回到剛才的畫面…", "Returning to where you were…")
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
        case .service(let id, let manage): workspace.openService(id, manage: manage)
        case .manage: showsManage = true
        case .downloads: showsDownloads = true
        case .pairing: showsPairing = true
        }
    }
}

/// Shown while a service opens, instead of the website's own connecting screen and a bare bar with the address (Android
/// `ServiceTransition`): the page colour, the robot tile, the service name and a quiet spinner. It takes the taps meant for
/// the page under it. iOS has no system back, so a round back button stays at the top left.
private struct BotServiceTransition: View {
    let name: String
    let text: String
    let backLabel: String
    let back: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        VStack(spacing: 0) {
            BotAvatar(avatar: BotConversationAvatar()).frame(width: 56, height: 56).accessibilityHidden(true)
            Text(name).scaledFont(size: 17, weight: .semibold).foregroundStyle(palette.ink).lineLimit(1).padding(.top, 16)
            Text(text).scaledFont(size: 14).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.center)
                .padding(.top, 6).accessibilityIdentifier("bot.transition")
            BotSpinner(color: palette.hintInk).frame(width: 20, height: 20).padding(.top, 20).accessibilityHidden(true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {}
        .overlay(alignment: .topLeading) {
            BotRoundButton(symbol: "chevron.left", label: backLabel, identifier: "bot.transition.back", action: back)
                .padding(.horizontal, 8).frame(height: 64)
        }
    }
}

/// Android's small indeterminate CircularProgressIndicator (no track): an arc that grows and shrinks while it turns.
/// In at once; out with a fade that no longer takes touches, so a tap on a bot right after the reveal reaches the page.
private struct BotCoverTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase == .didDisappear ? 0 : 1).allowsHitTesting(phase != .didDisappear)
    }
}

private struct BotSpinner: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let cycle = (time / 1.332).truncatingRemainder(dividingBy: 1)
            Circle().trim(from: 0, to: 0.06 + 0.66 * (0.5 - 0.5 * cos(cycle * 2 * .pi)))
                .stroke(color, style: StrokeStyle(lineWidth: 2))
                .rotationEffect(.degrees((time * 300).truncatingRemainder(dividingBy: 360) + cycle * 270))
                .padding(1)
        }
    }
}
#endif
