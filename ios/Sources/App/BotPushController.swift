#if WOOWTECHBOT
import AssistantPersistence
import Combine
import CryptoKit
import FirebaseCore
import FirebaseMessaging
import OSLog
import UIKit
import UserNotifications
import WebKit

enum BotPushStatus {
    case off, unavailable, permission, simulator, waitingAPNs, checking, signIn, httpsRequired
    case serverNotReady, registered, retry, cleanupPending, signInUnavailable
    func text(_ localizer: AppLocalizer) -> String {
        let value: (String, String)
        switch self {
        case .off: value = ("推播已關閉", "Push is off")
        case .unavailable: value = ("此版本尚未提供遠端通知", "Remote notifications are unavailable in this build")
        case .permission: value = ("請在系統設定允許通知", "Allow notifications in system settings")
        case .simulator: value = ("請在實機驗收 APNs 推播", "Verify APNs push on a physical device")
        case .waitingAPNs: value = ("正在連接通知服務", "Connecting to the notification service")
        case .checking: value = ("正在檢查推播", "Checking push registration")
        case .signIn: value = ("請先在此服務配對或登入", "Pair or sign in to this service first")
        case .signInUnavailable: value = ("暫時無法讀取登入狀態，請開啟服務後重試", "Cannot read sign-in yet; open the service and retry")
        case .httpsRequired: value = ("遠端推播需要 HTTPS 服務", "Remote push requires an HTTPS service")
        case .serverNotReady: value = ("服務尚未提供 iOS 推播", "This service is not ready for iOS push")
        case .registered: value = ("已開啟此服務的通知", "Notifications enabled for this service")
        case .retry: value = ("尚未完成，請重試", "Not complete; retry")
        case .cleanupPending: value = ("舊推播註冊尚未確認撤銷", "Previous push registration removal is unconfirmed")
        }
        return localizer.language == .english ? value.1 : value.0
    }
}

/// The existing notification-center delegate remains the sole delegate. Firebase
/// swizzling and automatic token generation are disabled in the Bot-only plist.
@MainActor final class BotPushController: NSObject, ObservableObject, MessagingDelegate {
    static let shared = BotPushController()
    @Published private(set) var status: BotPushStatus = .off
    @Published private(set) var services: [UUID: BotPushStatus] = [:]
    private var worker: Task<Void, Never>?
    private var needsRefresh = false
    private var retiring = false
    private var epoch = UUID()
    private var apnsReady = false
    private var lastTap = UUID()
    private var authorized: [UUID: BotPushSession] = [:]
    private var workspace: BotWorkspaceStore { .shared }
    var optedIn: Bool { workspace.state.push?.enabled == true }
    var pendingCleanup: Int { workspace.state.push?.registrations.filter { !$0.acknowledged }.count ?? 0 }
    /// The language each registration carries, so the push relay writes the notification in the app's language.
    private(set) var locale = "zh-TW"
    /// A new interface language registers again, as smart re-registers its token string.
    func setInterfaceLanguage(english: Bool) {
        let next = english ? "en" : "zh-TW"
        guard next != locale else { return }
        locale = next
        if optedIn { schedule() }
    }

    private func configure() -> Bool {
        if FirebaseApp.app() != nil { return true }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.projectID == "woowtech-assistant", options.gcmSenderID == "795023111689",
              options.bundleID == "io.woowtech.assistant.bot",
              options.googleAppID == "1:795023111689:ios:289442214db27c7f442ad8",
              Bundle.main.bundleIdentifier == options.bundleID else { return false }
        FirebaseApp.configure(options: options)
        Messaging.messaging().isAutoInitEnabled = false
        Messaging.messaging().delegate = self
        return true
    }

    func setOptIn(_ enabled: Bool) {
        do {
            try workspace.change {
                var push = $0.push ?? BotPushPreferences(); push.enabled = enabled; $0.push = push
            }
        } catch { status = .retry; return }
        invalidate()
        if enabled {
            status = .checking
            Task {
                do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                catch { status = .permission }
                schedule()
            }
        } else { schedule() }
    }

    /// Synchronously revoke cached eligibility before an asynchronous retry.
    func invalidate() { epoch = UUID(); authorized = [:] }
    func schedule() {
        invalidate(); needsRefresh = true
        guard worker == nil, !retiring else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while self.needsRefresh && !Task.isCancelled {
                self.needsRefresh = false
                await self.reconcile()
            }
            self.worker = nil
        }
    }

    func didRegisterAPNs(_ token: Data) {
        guard optedIn, configure() else { return }
        Messaging.messaging().apnsToken = token; apnsReady = true; schedule()
    }
    func didFailAPNs() { apnsReady = false; invalidate(); status = .retry }
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Never persist/log the callback token; fetch the current token in the serialized worker.
        Task { @MainActor in if self.optedIn { self.schedule() } }
    }

    private func reconcile() async {
        guard workspace.available else { status = .retry; return }
        let generation = epoch
        status = .checking
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == epoch else { return }
        let permission = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let enabled = optedIn && permission
        let records = workspace.services.filter(\.enabled)
        services = Dictionary(uniqueKeysWithValues: records.map { ($0.id, enabled ? .checking : (optedIn ? .permission : .off)) })
        var cleanupOK = true
        for entry in workspace.state.push?.registrations ?? [] {
            let retained = enabled && records.contains { $0.id == entry.service.id && $0.profileID == entry.service.profileID && $0.origin == entry.service.origin }
            if !retained {
                do { try await revoke(entry, cookies: nil) }
                catch { cleanupOK = false; services[entry.service.id] = .cleanupPending }
            }
            guard generation == epoch, !Task.isCancelled else { return }
        }
        guard enabled else {
            UIApplication.shared.unregisterForRemoteNotifications(); apnsReady = false
            #if !targetEnvironment(simulator)
            if FirebaseApp.app() != nil {
                Messaging.messaging().isAutoInitEnabled = false
                do { try await Messaging.messaging().deleteToken() }
                catch { cleanupOK = false; BotPushDiagnostics.failure(error, stage: "delete-token") }
            }
            #endif
            status = cleanupOK ? (optedIn ? .permission : .off) : .cleanupPending
            return
        }
        #if !targetEnvironment(simulator)
        guard configure() else {
            services = Dictionary(uniqueKeysWithValues: records.map { ($0.id, .unavailable) })
            status = .unavailable; return
        }
        #endif
        // Discovery is useful on simulators, but simulator injection is never reported as FCM delivery.
        var ready: [BotPushSession] = []
        for service in records {
            guard service.origin.hasPrefix("https://") else { services[service.id] = .httpsRequired; continue }
            do {
                let connection = try await BotPushSession.discover(service)
                let current = await connection.current(in: workspace)
                guard generation == epoch, !Task.isCancelled else { return }
                guard current else { services[service.id] = .retry; continue }
                services[service.id] = connection.discovery.ready ? .waitingAPNs : .serverNotReady
                if connection.discovery.ready { ready.append(connection) }
            } catch BotPushFailure.signIn { services[service.id] = .signIn }
            catch BotPushFailure.cookieTimeout { services[service.id] = .signInUnavailable }
            catch BotServiceError.invalidData { services[service.id] = .serverNotReady }
            catch { services[service.id] = .retry; BotPushDiagnostics.failure(error, stage: "discovery") }
            guard generation == epoch, !Task.isCancelled else { return }
        }
        #if targetEnvironment(simulator)
        status = .simulator
        return
        #else
        guard !ready.isEmpty else { status = records.isEmpty ? .signIn : .serverNotReady; return }
        guard apnsReady else {
            UIApplication.shared.registerForRemoteNotifications(); status = .waitingAPNs; return
        }
        do {
            let token = try await Messaging.messaging().token()
            guard generation == epoch, optedIn, !Task.isCancelled else { return }
            let digest = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
            for connection in ready {
                let service = connection.service
                do {
                    let current = await connection.current(in: workspace)
                    guard generation == epoch, !Task.isCancelled else { return }
                    guard current else { services[service.id] = .retry; continue }
                    let old = workspace.state.push?.registrations ?? []
                    if old.contains(where: { $0.service.id == service.id && $0.identity != connection.discovery.identity }) {
                        services[service.id] = .cleanupPending; cleanupOK = false; continue
                    }
                    let entry = BotPushRegistration(service: service, identity: connection.discovery.identity, tokenDigest: digest)
                    // Persist ambiguity before making a request. Network errors never erase this ledger.
                    try save(entry)
                    let body = try BotPushDiscovery.registrationBody(serviceID: service.id, token: token, locale: locale)
                    let data = try await connection.request(method: "PUT", path: BotPushDiscovery.devicePath, body: body)
                    let stillCurrent = await connection.current(in: workspace)
                    guard generation == epoch, !Task.isCancelled else { return }
                    guard stillCurrent else { services[service.id] = .retry; continue }
                    try BotPushDiscovery.validateAcknowledgement(data, serviceID: service.id)
                    var confirmed = entry; confirmed.acknowledged = true; try save(confirmed)
                    authorized[service.id] = connection; services[service.id] = .registered
                } catch {
                    // One deployment's timeout or rejected ACK must not prevent
                    // the other independently authenticated services from registering.
                    services[service.id] = .retry
                    BotPushDiagnostics.failure(error, stage: "register")
                }
            }
            guard generation == epoch, !Task.isCancelled else { return }
            status = !cleanupOK ? .cleanupPending : (authorized.count == ready.count ? .registered : .retry)
        } catch { status = .retry }
        #endif
    }

    private func save(_ registration: BotPushRegistration) throws {
        try workspace.change {
            var push = $0.push ?? BotPushPreferences()
            push.registrations.removeAll { $0.identity == registration.identity }
            push.registrations.append(registration); $0.push = push
        }
    }
    private func revoke(_ entry: BotPushRegistration, cookies: [HTTPCookie]?) async throws {
        let connection = try await BotPushSession.discover(entry.service, cookies: cookies)
        guard connection.discovery.identity == entry.identity else { throw BotPushFailure.stale }
        let path = BotPushDiscovery.devicePath + "?serviceId=" + entry.service.id.uuidString.lowercased()
        let data = try await connection.request(method: "DELETE", path: path)
        try BotPushDiscovery.validateAcknowledgement(data, serviceID: nil)
        try workspace.change { $0.push?.registrations.removeAll { $0.identity == entry.identity } }
    }

    /// Uses the ORIGINAL cookie snapshot before website data is removed. No new
    /// profile may acknowledge cleanup of a retired identity.
    func retire(_ service: BotServiceRecord, cookies: [HTTPCookie]) async -> Bool {
        retiring = true; invalidate(); worker?.cancel()
        await worker?.value; worker = nil
        defer { retiring = false; schedule() }
        var complete = true
        for entry in workspace.state.push?.registrations.filter({ $0.service.profileID == service.profileID }) ?? [] {
            do { try await revoke(entry, cookies: cookies) } catch { complete = false }
        }
        let center = UNUserNotificationCenter.current()
        let own = await center.deliveredNotifications().filter {
            Self.target($0.request.content.userInfo)?.serviceID == service.id
        }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: own)
        return complete
    }

    static func target(_ info: [AnyHashable: Any]) -> BotNotificationTarget? {
        if let fields = info["woowtechbot"] as? [String: String] { return try? .init(fields: fields) }
        // FCM data values must be strings. Its reserved outer metadata is not routing input.
        if let text = info["woowtechbot"] as? String, text.utf8.count <= 2048,
           let fields = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) {
            return try? .init(fields: fields)
        }
        return nil
    }
    func mayPresent(_ info: [AnyHashable: Any]) async -> Bool {
        let generation = epoch
        guard optedIn, let target = Self.target(info), let connection = authorized[target.serviceID],
              await connection.current(in: workspace), generation == epoch, optedIn else { return false }
        return true
    }
    func open(_ info: [AnyHashable: Any]) async {
        guard optedIn, let target = Self.target(info),
              let record = workspace.services.first(where: { $0.id == target.serviceID && $0.enabled }) else { return }
        let tap = UUID(); lastTap = tap
        do {
            let connection = try await BotPushSession.discover(record)
            guard workspace.state.push?.registrations.contains(where: {
                $0.service.id == record.id && $0.identity == connection.discovery.identity
            }) == true else { return }
            // Ask the authenticated server, so a foreground token refresh's
            // durable "pending" entry cannot swallow a valid cold-start tap.
            let receipt = try await connection.request(method: "GET", path: BotPushDiscovery.devicePath)
            try BotPushDiscovery.validateAcknowledgement(receipt, serviceID: record.id)
            // Foreground refresh is expected during a cold-start tap. It may
            // invalidate registration caches, but must not discard this fresh
            // authentication result. Profile/cookie/consent and newest tap win.
            guard await connection.current(in: workspace), tap == lastTap, optedIn else { return }
            _ = workspace.openNotificationTarget(target)
        } catch { services[record.id] = .retry }
    }
}

private enum BotPushFailure: Error { case signIn, stale, transport, oversize, cookieTimeout, http(Int) }

private enum BotPushDiagnostics {
    static let log = Logger(subsystem: "io.woowtech.assistant.bot", category: "BotPush")
    static func failure(_ error: Error, stage: String) {
        // Only internal categories and numeric codes: never an error description,
        // URL, cookie, registration token, account or server response body.
        let category = (error as? BotPushFailure).map { String(describing: $0) }
            ?? (error is URLError ? "connection" : "other")
        log.error("\(stage, privacy: .public): \(category, privacy: .public), code \((error as NSError).code)")
    }
}

/// Cookies are process-only, captured from one WKWebsiteDataStore. The transport
/// has no shared cookie jar, redirect following, cache, token logging or URL from a server.
@MainActor private struct BotPushSession {
    let service: BotServiceRecord
    let cookie: String
    let discovery: BotPushDiscovery
    static func discover(_ service: BotServiceRecord, cookies suppliedCookies: [HTTPCookie]? = nil) async throws -> Self {
        guard service.origin.hasPrefix("https://") else { throw BotPushFailure.signIn }
        let cookies: [HTTPCookie]
        if let supplied = suppliedCookies { cookies = supplied }
        else {
            let workspace = BotWorkspaceStore.shared
            let known = workspace.services.contains { $0.id == service.id && $0.profileID == service.profileID && $0.origin == service.origin }
                || workspace.state.registry.retiredProfiles.contains(service.profileID)
            guard known else { throw BotPushFailure.signIn }
            cookies = try await BotPushCookieRead.read(workspace.websiteDataStore(service.profileID))
        }
        let cookie = try capture(service, cookies: cookies)
        let data = try await BotPushHTTP.send(service: service, cookie: cookie, sessionID: nil,
            method: "GET", path: "/api/auth/session", body: nil)
        return try Self(service: service, cookie: cookie, discovery: BotPushDiscovery(data: data, service: service))
    }
    static func capture(_ service: BotServiceRecord, cookies: [HTTPCookie]) throws -> String {
        func header(_ path: String) -> String {
            let host = service.policy.url.host ?? ""
            return cookies.filter {
                let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
                return (host == domain || ($0.domain.hasPrefix(".") && host.hasSuffix("." + domain))) &&
                    ($0.expiresDate.map { $0 > Date() } ?? true) &&
                    (path == $0.path || path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/"))
            }.sorted { ($0.name, $0.path, $0.value) < ($1.name, $1.path, $1.value) }
                .map { $0.name + "=" + $0.value }.joined(separator: "; ")
        }
        let value = header("/api/auth/session")
        guard !value.isEmpty, value.utf8.count <= 16384, value == header(BotPushDiscovery.devicePath),
              !value.contains("\r"), !value.contains("\n") else { throw BotPushFailure.signIn }
        return value
    }
    func current(in workspace: BotWorkspaceStore) async -> Bool {
        guard workspace.available, workspace.services.contains(where: {
            $0.id == service.id && $0.enabled && $0.profileID == service.profileID && $0.origin == service.origin
        }) else { return false }
        guard let cookies = try? await BotPushCookieRead.read(workspace.websiteDataStore(service.profileID)) else { return false }
        return workspace.available && workspace.services.contains(where: {
            $0.id == service.id && $0.enabled && $0.profileID == service.profileID && $0.origin == service.origin
        }) && (try? Self.capture(service, cookies: cookies)) == cookie
    }
    func request(method: String, path: String, body: Data? = nil) async throws -> Data {
        try await BotPushHTTP.send(service: service, cookie: cookie, sessionID: discovery.sessionID, method: method, path: path, body: body)
    }
}

@MainActor private final class BotPushCookieRead {
    private var completion: CheckedContinuation<[HTTPCookie], Error>?
    private init(_ completion: CheckedContinuation<[HTTPCookie], Error>) { self.completion = completion }
    private func finish(_ result: Result<[HTTPCookie], Error>) {
        guard let completion else { return }; self.completion = nil
        completion.resume(with: result)
    }
    static func read(_ store: WKWebsiteDataStore) async throws -> [HTTPCookie] {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { completion in
            let pending = BotPushCookieRead(completion)
            let timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                BotPushDiagnostics.log.error("cookie read timed out")
                pending.finish(.failure(BotPushFailure.cookieTimeout))
            }
            store.httpCookieStore.getAllCookies { cookies in
                // WebKit delivers this callback on MainActor. Resume directly;
                // an extra unstructured task needlessly delays the completion.
                withExtendedLifetime(store) {}
                BotPushDiagnostics.log.debug("cookie read callback received")
                timeout.cancel(); pending.finish(.success(cookies))
            }
        }
    }
}

private final class BotPushHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private actor RetryWindow {
        var until: [String: Date] = [:]
        func check(_ origin: String) throws {
            if let date = until[origin], date > Date() { throw BotPushFailure.transport }
        }
        func limit(_ origin: String, seconds: TimeInterval) { until[origin] = Date().addingTimeInterval(max(30, min(seconds, 86400))) }
    }
    private static let retryWindow = RetryWindow()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    static func send(service: BotServiceRecord, cookie: String, sessionID: String?, method: String, path: String, body: Data?) async throws -> Data {
        let valid = (method == "GET" && ["/api/auth/session", BotPushDiscovery.devicePath].contains(path)) ||
            (method == "PUT" && path == BotPushDiscovery.devicePath) ||
            (method == "DELETE" && path == BotPushDiscovery.devicePath + "?serviceId=" + service.id.uuidString.lowercased())
        guard valid, service.origin.hasPrefix("https://"), let url = URL(string: service.origin + path), service.policy.allows(url) else { throw BotPushFailure.transport }
        try await retryWindow.check(service.origin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: BotPushHTTP(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(service.origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 WOOWTECH-Assistant-iOS", forHTTPHeaderField: "User-Agent")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "X-Woowtech-Session-Id") }
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw BotPushFailure.transport }
        if response.statusCode == 429 {
            await retryWindow.limit(service.origin, seconds: TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30)
        }
        if [401, 403].contains(response.statusCode) { throw BotPushFailure.signIn }
        guard response.statusCode == 200 else { throw BotPushFailure.http(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65536 else { throw BotPushFailure.oversize }
            data.append(byte)
        }
        return data
    }
}
#endif
