#if os(iOS)
import AssistantModels
import AuthenticationServices
import SafariServices
import SwiftUI
import UIKit

/// What Settings › 模型 shows for one signed-in provider: signed in or out on
/// this device, and the account's email or name (empty when unknown).
struct ModelAccountStatus: Equatable {
    let signedIn: Bool
    let label: String
}

/// A page the in-app browser shows (xAI's confirmation page).
struct ModelAccountBrowserPage: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// 用帳號登入 · 不用填 Key, as on the Android direct-download edition
/// (ModelSetupViewModel.signInWithChatGpt, signInWithAccount and
/// ChatGptSignIns): one sign-in at a time, started only from the explanation
/// sheet; progress, cancel and the reason a sign-in did not finish.
///
/// ChatGPT: a 127.0.0.1 loopback listener and OpenAI's page in
/// ASWebAuthenticationSession; the App stays in front, and the listener opens
/// again if iOS took it away while the App was in the background. xAI: a
/// device code, xAI's page in an in-app browser (SFSafariViewController) so
/// the App keeps polling, and the code with copy and reopen.
///
/// Sessions go only into the provider's Keychain item (ModelSettingsRepository);
/// no token, code or address is ever logged or shown.
@MainActor
final class ModelAccountSignIn: ObservableObject {
    static let shared = ModelAccountSignIn()

    /// The xAI code while its sign-in waits (Android AccountSignInUi.userCode).
    struct DeviceCode: Equatable {
        let userCode: String
        let openURL: URL?
        let expiresAt: Date
    }

    /// A sign-in that just finished; the model page opens the provider.
    struct Finished: Identifiable, Equatable {
        let id = UUID()
        let kind: ModelAccountKind
        let providerID: UUID
    }

    enum Listing: Equatable { case running, failed }

    @Published private(set) var running: ModelAccountKind?
    @Published private(set) var deviceCode: DeviceCode?
    @Published private(set) var failures: [ModelAccountKind: AppText] = [:]
    @Published var finished: Finished?
    @Published private(set) var statuses: [UUID: ModelAccountStatus] = [:]
    @Published private(set) var listing: [UUID: Listing] = [:]
    /// Signing out of ChatGPT cleared this device, but ChatGPT did not confirm the revoke.
    @Published private(set) var revokeUnconfirmed = false
    @Published var browserPage: ModelAccountBrowserPage?
    @Published private(set) var copiedCode = false
    #if DEBUG
    let fixture: ModelAccountSignInFixture?
    #endif

    private var task: Task<Void, Never>?
    /// The sign-in that owns the state; a cancelled one that ends late changes nothing.
    private var attempt: UUID?
    private var authSession: ASWebAuthenticationSession?
    private var server: LoopbackCallbackServer?
    private let presentation = ModelAccountPresentationAnchor()
    private var activation: NSObjectProtocol?

    private init() {
        #if DEBUG
        fixture = ModelAccountSignInFixture.selected(arguments: ProcessInfo.processInfo.arguments)
        #endif
        activation = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.listenAgainIfNeeded() }
        }
    }

    // MARK: State for the screens

    /// Each account provider's status, read again from its Keychain item.
    func reload(_ session: ChatSession) {
        let repository = session.voiceModelRepository
        var next: [UUID: ModelAccountStatus] = [:]
        for provider in session.providerDocument.providers {
            switch provider.kind.account {
            case .chatGPT?:
                let saved = try? repository.accountSession(ChatGPTSession.self, providerID: provider.id)
                next[provider.id] = ModelAccountStatus(signedIn: saved?.signedIn == true, label: saved?.email ?? "")
            case .xai?:
                let saved = try? repository.accountSession(XAISession.self, providerID: provider.id)
                next[provider.id] = ModelAccountStatus(signedIn: saved?.signedIn == true, label: saved?.label ?? "")
            case nil:
                continue
            }
        }
        if next != statuses { statuses = next }
    }

    func status(_ providerID: UUID) -> ModelAccountStatus? { statuses[providerID] }

    /// The provider of this kind signed in on this device, if there is one.
    func signedInProvider(_ kind: ModelAccountKind, in document: ModelProvidersDocument) -> UUID? {
        guard let provider = document.accountProvider(kind), statuses[provider.id]?.signedIn == true else { return nil }
        return provider.id
    }

    func clearFailure(_ kind: ModelAccountKind) { failures[kind] = nil }

    // MARK: Signing in

    /// Starts a sign-in after the person continued on the explanation sheet.
    /// Only one runs at a time (Android signin_busy).
    func start(_ kind: ModelAccountKind, session: ChatSession, localizer: AppLocalizer) {
        guard running == nil else { return }
        failures[kind] = nil
        revokeUnconfirmed = false
        copiedCode = false
        running = kind
        let attempt = UUID()
        self.attempt = attempt
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result: (providerID: UUID, listFailed: Bool)
                switch kind {
                case .chatGPT: result = try await self.signInWithChatGPT(session: session, localizer: localizer)
                case .xai: result = try await self.signInWithXAI(session: session)
                }
                session.reloadProviders()
                self.reload(session)
                guard self.attempt == attempt else { return }
                self.end()
                self.listing[result.providerID] = result.listFailed ? .failed : nil
                self.finished = Finished(kind: kind, providerID: result.providerID)
            } catch {
                guard self.attempt == attempt else { return }
                self.end()
                // Cancelling is not a failure; anything else says why, never with a token or body.
                if !(error is CancellationError) { self.failures[kind] = Self.failureText(kind, error) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        end()
    }

    private func end() {
        task = nil
        attempt = nil
        closePages()
        running = nil
    }

    /// Android copyAndReopen: the code on the clipboard, and xAI's page again.
    func copyCodeAndReopen() {
        guard let code = deviceCode else { return }
        UIPasteboard.general.string = code.userCode
        copiedCode = true
        #if DEBUG
        if let fixture { fixture.reopened += 1; return }
        #endif
        if let url = code.openURL { browserPage = ModelAccountBrowserPage(url: url) }
    }

    private func signInWithChatGPT(session: ChatSession, localizer: AppLocalizer) async throws -> (providerID: UUID, listFailed: Bool) {
        let repository = session.voiceModelRepository
        let store = ModelAccountRepositoryBox(repository: repository)
        #if DEBUG
        if let fixture {
            guard try await fixture.decision() else { throw ChatGPTSignInError(.denied, code: "access_denied") }
            let signedIn = ModelAccountSignInFixture.chatGPTSession()
            return (try repository.connectAccount(.chatGPT, session: signedIn, models: ModelAccountSignInFixture.chatGPTModels).id, false)
        }
        #endif
        let registration = repository.chatGPTRegistration()
        let previous = session.providerDocument.accountProvider(.chatGPT)
            .flatMap { try? repository.accountSession(ChatGPTSession.self, providerID: $0.id) }
        let server = try await LoopbackCallbackServer.open()
        self.server = server
        defer {
            server.close()
            self.server = nil
        }
        let pages = ModelAccountCallbackPage(localizer: localizer)
        let signedIn = try await ChatGPTSignIn.signIn(
            auth: ChatGPTAuthClient(), server: server, hostID: registration.hostID, clientID: registration.clientID,
            previous: previous,
            openBrowser: { [weak self] url in await self?.presentAuthPage(url) },
            onRegistered: { id in store.repository.rememberChatGPTClient(id) },
            page: { error in pages.html(error) })
        closePages()
        let models = try? await AccountModelList.fetch(base: ChatGPTSignIn.apiBase, accessToken: signedIn.accessToken)
        let provider = try repository.connectAccount(.chatGPT, session: signedIn, models: models)
        return (provider.id, models == nil)
    }

    private func signInWithXAI(session: ChatSession) async throws -> (providerID: UUID, listFailed: Bool) {
        let repository = session.voiceModelRepository
        #if DEBUG
        if let fixture {
            show(ModelAccountSignInFixture.xaiChallenge, openPage: false)
            guard try await fixture.decision() else { throw XAISignInError(.denied, code: "access_denied") }
            let signedIn = ModelAccountSignInFixture.xaiSession()
            return (try repository.connectAccount(.xai, session: signedIn, models: ModelAccountSignInFixture.xaiModels).id, false)
        }
        #endif
        let signedIn = try await XAIAuthClient().signIn(onChallenge: { [weak self] challenge in
            await self?.show(challenge, openPage: true)
        })
        closePages()
        let base = URL(string: signedIn.apiBase).flatMap { OAuthHosts.allowed($0.absoluteString, hosts: ["api.x.ai"]) } ?? XAISignIn.apiBase
        let models = try? await AccountModelList.fetch(base: base, accessToken: signedIn.accessToken)
        let provider = try repository.connectAccount(.xai, session: signedIn, models: models)
        return (provider.id, models == nil)
    }

    private func show(_ challenge: XAIDeviceChallenge, openPage: Bool) {
        let url = URL(string: challenge.openURL)
        deviceCode = DeviceCode(userCode: challenge.userCode, openURL: url,
                                expiresAt: Date().addingTimeInterval(TimeInterval(challenge.expiresIn)))
        if openPage, let url { browserPage = ModelAccountBrowserPage(url: url) }
    }

    private func presentAuthPage(_ url: URL) {
        let handler: ASWebAuthenticationSession.CompletionHandler = { [weak self] _, error in
            // The loopback callback finishes a sign-in; this only ends one the person closed first.
            Task { @MainActor in self?.authPageClosed(error) }
        }
        let session: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.unusedCallbackScheme), completionHandler: handler)
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.unusedCallbackScheme, completionHandler: handler)
        }
        session.presentationContextProvider = presentation
        // Like a browser: someone already signed in to ChatGPT in Safari need not type it again.
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() { cancel() }
    }

    /// No page ever redirects here; OpenAI sends the browser back to the loopback listener.
    private static let unusedCallbackScheme = "io.woowtech.assistant.signin"

    private func authPageClosed(_ error: Error?) {
        guard authSession != nil else { return }
        authSession = nil
        // Closing OpenAI's page before signing in cancels the sign-in.
        if running == .chatGPT, (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cancel() }
    }

    private func closePages() {
        let page = authSession
        authSession = nil
        page?.cancel()
        browserPage = nil
        deviceCode = nil
    }

    /// iOS may take a suspended App's listening socket away; the authorize
    /// request named this port, so listen on it again.
    private func listenAgainIfNeeded() {
        guard running == .chatGPT, let server, !server.isListening else { return }
        Task { try? await server.reopen() }
    }

    // MARK: Signing out and listing models

    /// Clears the sign-in on this device only; the provider, its models and
    /// the roles that use it stay. ChatGPT's refresh token is also revoked;
    /// xAI's grant is disconnected in the xAI account settings.
    func signOut(providerID: UUID, session: ChatSession) {
        guard let provider = session.providerDocument.provider(id: providerID), let kind = provider.kind.account else { return }
        let repository = session.voiceModelRepository
        revokeUnconfirmed = false
        listing[providerID] = nil
        switch kind {
        case .chatGPT:
            let before = try? repository.signOutAccount(ChatGPTSession.self, providerID: providerID)
            reload(session)
            guard let before, !before.refreshToken.isEmpty else { return }
            #if DEBUG
            if fixture != nil { return }
            #endif
            Task { [weak self] in
                let confirmed = await ChatGPTAuthClient().revoke(clientID: before.clientId, refreshToken: before.refreshToken)
                self?.revokeUnconfirmed = !confirmed
            }
        case .xai:
            _ = try? repository.signOutAccount(XAISession.self, providerID: providerID)
            reload(session)
        }
    }

    /// Lists the account's models again with its token (refreshed first when it is due).
    func refreshModels(providerID: UUID, session: ChatSession) {
        guard let provider = session.providerDocument.provider(id: providerID), let route = provider.accountRoute,
              listing[providerID] != .running else { return }
        let repository = session.voiceModelRepository
        listing[providerID] = .running
        Task { [weak self] in
            do {
                let models: [ListedModel]
                #if DEBUG
                if self?.fixture != nil {
                    models = route.kind == .chatGPT ? ModelAccountSignInFixture.chatGPTModels : ModelAccountSignInFixture.xaiModels
                } else {
                    models = try await Self.listModels(route: route, base: provider.baseURL, repository: repository)
                }
                #else
                models = try await Self.listModels(route: route, base: provider.baseURL, repository: repository)
                #endif
                try repository.updateAccountModels(providerID: providerID, models: models)
                session.reloadProviders()
                self?.listing[providerID] = nil
            } catch {
                self?.listing[providerID] = .failed
            }
        }
    }

    private static func listModels(route: ModelAccountRoute, base: URL, repository: ModelSettingsRepository) async throws -> [ListedModel] {
        let token = try await ModelAccountTokens(repository: repository).accessToken(for: route, rejected: nil)
        return try await AccountModelList.fetch(base: base, accessToken: token)
    }

    // MARK: Words

    /// Android ModelsCopy.chatGptFailure and accountFailure; only a server's
    /// error code (never a secret) is named.
    nonisolated static func failureText(_ kind: ModelAccountKind, _ error: Error) -> AppText {
        switch kind {
        case .chatGPT:
            guard let error = error as? ChatGPTSignInError else { return .chatgptFailNetwork }
            switch error.reason {
            case .denied: return .chatgptFailDenied
            case .stateMismatch, .clientMismatch: return .chatgptFailMismatch
            case .noClientID: return .chatgptFailNoClient
            case .timedOut: return .chatgptFailTimedOut
            case .exchange: return .chatgptFailExchange(code: shownCode(error.code))
            case .codeExpired: return .chatgptFailCodeExpired
            case .region: return .chatgptFailRegion
            case .blocked: return .chatgptFailBlocked
            case .idToken: return .chatgptFailIDToken
            case .noPlanScope: return .chatgptFailNoPlan
            case .network: return .chatgptFailNetwork
            }
        case .xai:
            guard let error = error as? XAISignInError else { return .accountFailNetwork }
            switch error.reason {
            case .denied: return .accountFailDenied
            case .expired: return .accountFailExpired
            case .timedOut: return .accountFailTimedOut
            case .rejected: return .accountFailRejected(code: shownCode(error.code))
            case .noSubscription: return .accountFailNoSub
            case .network: return .accountFailNetwork
            case .badIssuer: return .accountFailIssuer
            }
        }
    }

    /// A server's error code as shown: short, and only the characters codes use.
    nonisolated static func shownCode(_ code: String?) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard let code, !code.isEmpty, code.count <= 64, code.unicodeScalars.allSatisfy(allowed.contains) else { return "unknown" }
        return code
    }
}

/// The repository handed to the listener's callback, which runs off the main actor.
private struct ModelAccountRepositoryBox: @unchecked Sendable {
    let repository: ModelSettingsRepository
}

/// The page the loopback listener answers the browser with, in the interface language.
private struct ModelAccountCallbackPage: @unchecked Sendable {
    let localizer: AppLocalizer

    func html(_ error: ChatGPTSignInError?) -> String {
        let message = error.map { localizer.text(ModelAccountSignIn.failureText(.chatGPT, $0)) } ?? localizer.text(.chatgptPageDone)
        let title = Self.escaped(localizer.text(.shellBrandTitle))
        return "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<title>\(title)</title></head><body style=\"font-family:-apple-system,sans-serif;margin:40px 24px;text-align:center\">"
            + "<h2>\(title)</h2><p>\(Self.escaped(message))</p></body></html>"
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// The window ASWebAuthenticationSession shows OpenAI's page over.
@MainActor
private final class ModelAccountPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}

/// xAI's confirmation page in the App, so the sign-in keeps polling.
struct ModelAccountSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#if DEBUG
/// DEBUG-only UI-test fixture: -UITestAccountSignIn with -UITestMode. The
/// sign-ins open no page and reach no server; a test approves or refuses them
/// with the fixture buttons on the sign-in sheet. Its sessions hold dummy
/// strings, never a real token, and go into the test's own Keychain service.
@MainActor
final class ModelAccountSignInFixture: ObservableObject {
    static let flag = "-UITestAccountSignIn"
    @Published private(set) var started = 0
    @Published var reopened = 0
    @Published private(set) var waiting = false
    private var answer: Bool?

    static func selected(arguments: [String]) -> ModelAccountSignInFixture? {
        arguments.contains(flag) && arguments.contains("-UITestMode") ? ModelAccountSignInFixture() : nil
    }

    func approve() { if waiting { answer = true } }
    func refuse() { if waiting { answer = false } }

    /// Waits for a fixture button; cancelling the sign-in ends the wait.
    func decision() async throws -> Bool {
        started += 1
        answer = nil
        waiting = true
        defer { waiting = false }
        while answer == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let result = answer ?? false
        answer = nil
        return result
    }

    static let chatGPTModels = [ListedModel(id: "gpt-fixture", vision: true), ListedModel(id: "gpt-fixture-mini", vision: false)]
    static let xaiModels = [ListedModel(id: "grok-fixture", vision: false)]
    static let xaiChallenge = XAIDeviceChallenge(userCode: "WOOW-FIX1", verificationURI: XAISignIn.fallbackVerify,
                                                 verificationURIComplete: nil, expiresIn: 900, interval: 5)

    static func chatGPTSession() -> ChatGPTSession {
        ChatGPTSession(clientId: "fixture-client", sub: "fixture-user", email: "fixture@example.invalid",
                       accessToken: "fixture-access-not-a-token", refreshToken: "fixture-refresh-not-a-token",
                       expiresAtMs: ModelAccountClock.nowMs() + 3_600_000, scopes: [ChatGPTSignIn.planScope])
    }

    static func xaiSession() -> XAISession {
        XAISession(accountId: "fixture-user", label: "fixture@example.invalid", accessToken: "fixture-access-not-a-token",
                   refreshToken: "fixture-refresh-not-a-token", expiresAtMs: ModelAccountClock.nowMs() + 3_600_000,
                   scopes: [XAISignIn.scopeAPI], apiBase: XAISignIn.apiBase.absoluteString, clientId: XAISignIn.clientID,
                   issuer: XAISignIn.issuer, tokenURL: XAISignIn.issuer + "/oauth2/token")
    }
}
#endif
#endif
