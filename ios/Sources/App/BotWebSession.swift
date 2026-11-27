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
        failed = false; loading = true; downloadUntil = .distantPast
        webView.load(URLRequest(url: url))
    }
    func retry() { open(service.policy.url) }
    func invalidate() {
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        valid = false; webView.stopLoading(); downloads.cancelAll()
        for item in downloads.items where !item.phase.isActive { downloads.remove(item.id) }
        dialog?.finish(nil); dialog = nil; externalURL = nil
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; failed = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        if BotPushController.shared.optedIn { BotPushController.shared.schedule() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard valid, (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; failed = true
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; failed = true }

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
    let localizer: AppLocalizer
    let close: () -> Void
    let attach: (URL) async -> Bool
    @State private var showsDownloads = false
    @State private var showsPairing = false
    @State private var promptText = ""
    @Environment(\.openURL) private var openURL
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }

    var body: some View {
        NavigationStack {
            ZStack {
                BotWebSurface(session: web).id(web.service.profileID)
                if web.failed {
                    ContentUnavailableView {
                        Label(t("暫時無法開啟服務", "Service unavailable"), systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(t("請確認網路或服務狀態。其他服務與本機助理仍可使用。", "Check your network or service. Local chats and other services remain available."))
                    } actions: {
                        Button(t("重試", "Retry"), action: web.retry).accessibilityIdentifier("bot.retry")
                    }.background(.background)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if web.loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("bot.loading") }
            }
            .navigationTitle(web.service.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Label(t("返回", "Back"), systemImage: "chevron.backward") }
                        .accessibilityIdentifier("bot.back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(t("掃描配對 QR", "Scan pairing QR"), systemImage: "qrcode.viewfinder") { showsPairing = true }
                        Button(t("重新載入", "Reload"), systemImage: "arrow.clockwise", action: web.retry)
                        Button(t("下載項目", "Downloads"), systemImage: "arrow.down.circle") { showsDownloads = true }
                        ShareLink(item: web.service.policy.url) { Label(t("分享服務網址", "Share service address"), systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("bot.menu")
                }
            }
        }
        .modifier(BrowserDownloadPresentations(manager: web.downloads, chat: chat, showsList: $showsDownloads,
                                               localizer: localizer, attach: attach))
        .sheet(isPresented: $showsPairing) {
            BotPairingView(service: web.service, localizer: localizer, connect: web.open)
        }
        .alert(t("在瀏覽器開啟外部連結？", "Open external link in browser?"), isPresented: Binding(
            get: { web.externalURL != nil }, set: { if !$0 { web.externalURL = nil } })) {
            Button(t("開啟", "Open")) { if let url = web.externalURL { openURL(url) }; web.externalURL = nil }
            Button(t("取消", "Cancel"), role: .cancel) { web.externalURL = nil }
        } message: { Text(web.externalURL?.host ?? "") }
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
}
#endif
