#if WOOWTECHBOT
import AssistantPersistence
import Combine
import Foundation
import WebKit

struct BotChatPresentation: Codable, Equatable {
    var title: String?
    var avatar = BotConversationAvatar()
    var draft = ""
    var updatedAt = Date()
    var hasSavedContent: Bool { !draft.isEmpty || title != nil || !avatar.isDefault }
}

enum BotWorkspaceNotice {
    case unreadable, draftUnsaved, busy, signedOut, remoteLogoutUnconfirmed
    case notificationUnsaved, titleUnsaved, changesUnsaved, deletedMetadataUnsaved, pushCleanupUnconfirmed
    func text(_ localizer: AppLocalizer) -> String {
        let words: (String, String)
        switch self {
        case .unreadable: words = ("無法讀取服務設定；原檔保留，請解鎖後重試。", "Cannot read service settings. The original file is preserved; unlock and retry.")
        case .draftUnsaved: words = ("草稿尚未保存，請解鎖後重試。", "Draft was not saved. Unlock and try again.")
        case .busy: words = ("請先完成目前工作或保存回覆，再切換對話。", "Finish the current task or save its reply before switching conversations.")
        case .signedOut: words = ("這個服務已登出；其他服務與本機對話保留。", "This service is signed out. Other services and local chats are preserved.")
        case .remoteLogoutUnconfirmed: words = ("本機登入已清除。伺服器登出尚未確認，可在服務的裝置管理撤銷舊登入。", "Local sign-in was cleared. Server logout is unconfirmed; revoke the old sign-in in the service's device settings.")
        case .notificationUnsaved: words = ("無法保存通知開啟紀錄，請解鎖後重試。", "Could not save the notification opening record. Unlock and retry.")
        case .titleUnsaved: words = ("對話已保存，但名稱尚未同步；請重新編輯名稱。", "The conversation was saved, but its name was not synchronized. Edit its name again.")
        case .changesUnsaved: words = ("變更尚未保存，請重試。", "Changes were not saved. Try again.")
        case .deletedMetadataUnsaved: words = ("對話已刪除，但圖示與草稿清除尚未保存。", "Conversation deleted; icon and draft cleanup was not saved.")
        case .pushCleanupUnconfirmed: words = ("本機登入已清除，但舊推播註冊尚未確認撤銷；請在服務的裝置管理撤銷舊登入。", "Local sign-in was cleared, but push registration removal is unconfirmed. Revoke the old sign-in in the service's device settings.")
        }
        return localizer.language == .english ? words.1 : words.0
    }
}

struct BotWorkspaceSnapshot: Codable {
    var registry = BotServiceRegistry()
    var chats: [String: BotChatPresentation] = [:]
    var currentChat: String?
    var openedEvents: [String] = []
    // Optional preserves decoding of pre-push encrypted workspaces.
    var push: BotPushPreferences?
    /// The service shown when the app last went out of sight, kept until the user closes that screen (owner 2026-11-28,
    /// Android `BotResumeEntry` as of woow.27): reopening the app after it was closed returns there. Only the service ID.
    var resume: UUID?
    func validate() throws {
        try registry.validate()
        try push?.validate()
        guard chats.count <= 300, openedEvents.count <= 256,
              currentChat.map({ UUID(uuidString: $0) != nil }) ?? true else { throw BotServiceError.invalidData }
        for (id, chat) in chats {
            guard UUID(uuidString: id) != nil, chat.draft.utf8.count <= 128_000,
                  chat.title.map({ ConversationArchive.normalizedTitle($0) == $0 }) ?? true,
                  chat.updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw BotServiceError.invalidData }
            try chat.avatar.validate()
        }
    }
}

/// Separate encrypted sidecar: neither the existing archive nor any website's
/// credentials are migrated into this file. Failed reads disable writes.
@MainActor final class BotWorkspaceStore: ObservableObject {
    static let shared = BotWorkspaceStore()
    @Published private(set) var state = BotWorkspaceSnapshot()
    @Published private(set) var available = false
    @Published var notice: BotWorkspaceNotice?
    @Published var selectedService: UUID?
    /// Set with `selectedService` when the service's own "…" asked to open its management sheet (not persisted).
    @Published var manageOnOpen = false
    private let vault: EncryptedLearningFile?
    private var sessions: [UUID: BotWebSession] = [:]
    private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    private var cleaning = Set<UUID>()
    var services: [BotServiceRecord] { state.registry.services }

    init(vault: EncryptedLearningFile? = nil) {
        let file: EncryptedLearningFile?
        do {
            if let vault { file = vault }
            else {
                let location = try ConversationArchiveStore.location(arguments: ProcessInfo.processInfo.arguments)
                file = EncryptedLearningFile(url: location.url.deletingLastPathComponent().appendingPathComponent("woowtechbot.vault"),
                    keys: LearningKeychainStore(service: location.service + ".woowtechbot"))
            }
        } catch { file = nil }
        self.vault = file
        do {
            try reload()
            Task { await cleanRetiredProfiles() }
        } catch { notice = .unreadable }
    }

    func reload() throws {
        do {
            guard let vault else { throw BotServiceError.unavailable }
            let next = try vault.withExclusiveAccess { try vault.load(BotWorkspaceSnapshot.self) ?? BotWorkspaceSnapshot() }
            try next.validate(); state = next; available = true
        } catch { available = false; throw error }
    }

    func change(_ edit: (inout BotWorkspaceSnapshot) throws -> Void) throws {
        guard available, let vault else { throw BotServiceError.unavailable }
        let next = try vault.withExclusiveAccess {
            var next = try vault.load(BotWorkspaceSnapshot.self) ?? BotWorkspaceSnapshot()
            try next.validate(); try edit(&next); try next.validate(); try vault.save(next)
            return next
        }
        state = next
    }

    @discardableResult func add(name: String, address: String, allowLAN: Bool) throws -> UUID {
        let record = try BotServiceRecord(name: name, address: address, allowHTTPLAN: allowLAN)
        try change { try $0.registry.add(record) }; return record.id
    }

    /// Opening or switching to a service lands on its bot list, behind the transition page (owner 2026-11-27).
    func openService(_ id: UUID, manage: Bool = false) {
        manageOnOpen = manage
        session(id)?.openList()
        selectedService = id
    }

    /// The service screen went out of sight without the user closing it; it stays recorded while it is open.
    func rememberResume(_ id: UUID) {
        guard state.resume != id else { return }
        try? change { $0.resume = id }
    }
    /// The user closed the service screen.
    func forgetResume() {
        guard state.resume != nil else { return }
        try? change { $0.resume = nil }
    }
    /// At launch: reopen the service the app was left on, if it is still enabled.
    func resumeIfNeeded() {
        guard let id = state.resume else { return }
        forgetResume()
        guard selectedService == nil, let web = session(id) else { return }
        web.openResume(); selectedService = id
    }

    func session(_ id: UUID) -> BotWebSession? {
        guard available, let record = services.first(where: { $0.id == id && $0.enabled }) else { return nil }
        if let current = sessions[id], current.service.profileID == record.profileID { return current }
        let session = BotWebSession(service: record, dataStore: websiteDataStore(record.profileID))
        sessions[id] = session
        return session
    }

    /// Retain one data-store object per profile, including while native push
    /// reads its cookie store. A temporary parent can disappear during an async read.
    func websiteDataStore(_ profile: UUID) -> WKWebsiteDataStore {
        if let stored = dataStores[profile] { return stored }
        let stored = WKWebsiteDataStore(forIdentifier: profile)
        dataStores[profile] = stored
        return stored
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) throws {
        // Disconnecting closes its screen: reopening the app no longer returns to it.
        try change { try $0.registry.setEnabled(id, enabled); if !enabled, $0.resume == id { $0.resume = nil } }
        if !enabled {
            if selectedService == id { selectedService = nil }
            sessions.removeValue(forKey: id)?.invalidate()
        }
        BotPushController.shared.schedule()
    }

    /// Commit a new identity first. Requests finishing afterwards cannot revive
    /// the old profile, even if the server is unreachable.
    func retire(_ id: UUID, remove: Bool) async throws {
        guard let record = services.first(where: { $0.id == id }) else { throw BotServiceError.stale }
        let dataStore = websiteDataStore(record.profileID)
        try change { _ = try $0.registry.retire(id, remove: remove); if $0.resume == id { $0.resume = nil } }
        if selectedService == id { selectedService = nil }
        sessions.removeValue(forKey: id)?.invalidate()
        let cookies = await dataStore.httpCookieStore.allCookies()
        let pushRevoked = await BotPushController.shared.retire(record, cookies: cookies)
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        let revoked = await BotRemoteLogout.revoke(record, cookies: cookies)
        notice = !pushRevoked ? .pushCleanupUnconfirmed : (revoked ? .signedOut : .remoteLogoutUnconfirmed)
        await cleanRetiredProfiles()
    }

    func cleanRetiredProfiles() async {
        for id in state.registry.retiredProfiles where !cleaning.contains(id) {
            cleaning.insert(id)
            dataStores.removeValue(forKey: id)
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                try change { $0.registry.acknowledgeRemoval(id) }
            } catch { /* In-use profiles remain queued for the next process. */ }
            cleaning.remove(id)
        }
    }

    func presentation(_ id: String) -> BotChatPresentation { state.chats[id] ?? .init() }
    func saveDraft(_ id: String, text: String) throws {
        guard presentation(id).draft != text || state.currentChat != id else { return }
        try change {
            var chat = $0.chats[id] ?? .init(); chat.draft = text; chat.updatedAt = Date()
            $0.chats[id] = chat; $0.currentChat = id
            // Blank untouched chats have no recoverable content. Keeping one
            // for every New tap would eventually exhaust the sidecar's bound.
            $0.chats = $0.chats.filter { $0.value.hasSavedContent }
        }
    }
    func savePresentation(_ id: String, title: String?, avatar: BotConversationAvatar) throws {
        try change {
            var chat = $0.chats[id] ?? .init(); chat.title = title; chat.avatar = avatar
            $0.chats[id] = chat
        }
    }
    func forgetChat(_ id: String) throws {
        try change {
            $0.chats.removeValue(forKey: id)
            if $0.currentChat == id { $0.currentChat = nil }
        }
    }

    /// The push controller calls this only after verifying current authentication.
    /// Payloads contain IDs, never URLs, commands, model text or credentials.
    @discardableResult func openNotificationTarget(_ target: BotNotificationTarget) -> Bool {
        guard !state.openedEvents.contains(target.deduplicationKey),
              let record = services.first(where: { $0.id == target.serviceID }),
              let url = try? target.url(for: record), let web = session(record.id) else { return false }
        do {
            try change {
                $0.openedEvents.append(target.deduplicationKey)
                $0.openedEvents = Array($0.openedEvents.suffix(256))
            }
        } catch { notice = .notificationUnsaved; return false }
        web.openTarget(url); selectedService = record.id; return true
    }
}

private final class BotRemoteLogout: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    static func revoke(_ service: BotServiceRecord, cookies: [HTTPCookie]) async -> Bool {
        let url = service.policy.url.appendingPathComponent("api/auth/logout")
        let relevant = cookies.filter {
            let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
            let host = url.host ?? ""
            let pathMatches = url.path == $0.path || url.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/")
            return (host == domain || host.hasSuffix("." + domain)) && pathMatches &&
                (!$0.isSecure || url.scheme == "https") && ($0.expiresDate.map { $0 > Date() } ?? true)
        }
        guard !relevant.isEmpty else { return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: BotRemoteLogout(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue(service.origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in HTTPCookie.requestHeaderFields(with: relevant) { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  response.url == url else { return false }
            if http.statusCode == 204 { return true }
            var data = Data()
            for try await byte in bytes { guard data.count < 4096 else { return false }; data.append(byte) }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true
        } catch { return false }
    }
}
#endif
