import Foundation
import Security

/// What a bot notification shows (owner 2026-11-28, Android woow.26 `BotPushPreview`): the bot that replied and the start
/// of its reply. The phone reads them from the service with its own verified session after the push arrives; the push
/// itself still carries IDs only, so nothing of a reply passes through APNs, FCM or the push relay.
public struct BotPushPreview: Equatable, Sendable {
    public let botName: String?
    public let excerpt: String?
    public init(botName: String?, excerpt: String?) { self.botName = botName; self.excerpt = excerpt }
}

/// Pure parsing of the website's own API answers, the same rules as Android's `BotPushPreviewText`. Anything unexpected
/// gives nil, so the generic text stays.
public enum BotPushPreviewText {
    public static let nameMax = 64
    public static let excerptMax = 400
    /// `GET /api/bots?messages=1`: `{bots:[{id,name}], groups:[{id,name}]}`; rooms are groups.
    public static let botsPath = "/api/bots?messages=1"
    /// `GET /api/threads/{thread}/messages?limit=8`, built only from a validated thread ID.
    public static func messagesPath(_ threadID: String) -> String? {
        BotNotificationTarget.validID(threadID) ? "/api/threads/" + threadID + "/messages?limit=8" : nil
    }
    public static func isPreviewPath(_ path: String) -> Bool {
        if path == botsPath { return true }
        let prefix = "/api/threads/", suffix = "/messages?limit=8"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix), path.count > prefix.count + suffix.count else { return false }
        return BotNotificationTarget.validID(String(path.dropFirst(prefix.count).dropLast(suffix.count)))
    }

    public static func name(_ json: Data, botID: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let all = ((root["bots"] as? [Any]) ?? []) + ((root["groups"] as? [Any]) ?? [])
        let found = all.compactMap { $0 as? [String: Any] }.first { ($0["id"] as? String) == botID }
        guard let name = found?["name"] as? String else { return nil }
        let text = clean(name, max: nameMax, singleLine: true)
        return text.isEmpty ? nil : text
    }

    /// `{messages:[{role,kind,text}]}`, oldest first. The reply is every bot text after the last user message, as the
    /// website's own inbox shows it; without one, the last bot text.
    public static func excerpt(_ json: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let messages = ((root["messages"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        func text(_ m: [String: Any]) -> String? {
            guard let t = m["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return t
        }
        let lastUser = messages.lastIndex { ($0["role"] as? String) == "user" } ?? -1
        let reply = messages.dropFirst(lastUser + 1).filter { ($0["role"] as? String) == "bot" }.compactMap(text)
        let chosen = reply.isEmpty
            ? [messages.last { ($0["role"] as? String) == "bot" && text($0) != nil }.flatMap(text)].compactMap { $0 }
            : reply
        let result = clean(chosen.joined(separator: "\n"), max: excerptMax, singleLine: false)
        return result.isEmpty ? nil : result
    }

    /// Plain text for a notification: no Markdown marks, control or direction-override characters, bounded length
    /// (counted in UTF-16 units, as Android).
    public static func clean(_ raw: String, max: Int, singleLine: Bool) -> String {
        func replace(_ text: String, _ pattern: String, _ template: String, multiline: Bool = false) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: multiline ? [.anchorsMatchLines] : []) else { return text }
            return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        var text = replace(raw, "```[^\\n]*\\n?", "")
        text = replace(text, "!?\\[([^\\]\\n]*)\\]\\([^)\\n]*\\)", "$1")
        text = replace(text, "^[ \\t]{0,3}(#{1,6}|>|[-*+]|\\d{1,3}[.)])[ \\t]+", "", multiline: true)
        text = replace(text, "\\*\\*|__|~~|`", "")
        text = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0x0A { return true }
            let control = v <= 0x1F || (0x7F...0x9F).contains(v)
            let direction = (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) || v == 0x200E || v == 0x200F
            return !(control || direction)
        }))
        if singleLine { text = replace(text, "\\s+", " ") }
        else { text = replace(replace(text, "[ \\t]+", " "), " ?\\n[ \\n]*", "\n") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let units = Array(text.utf16)
        guard units.count > max else { return text }
        var cut = Array(units.prefix(max - 1))
        if let last = cut.last, UTF16.isLeadSurrogate(last) {
            cut.removeLast()
            return String(decoding: cut, as: UTF16.self) + "…"
        }
        let head = String(decoding: cut, as: UTF16.self)
        let trimmed = head.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return trimmed + "…"
    }

    /// The notification's text for a reason: the excerpt as it is for a finished run, with a prefix for a question
    /// (permission, attention) or a failure.
    public static func body(excerpt: String, reason: String, english: Bool) -> String {
        switch reason {
        case "finished": return excerpt
        case "failed": return (english ? "Couldn't finish: " : "未能完成：") + excerpt
        default: return (english ? "Needs you: " : "需要處理：") + excerpt
        }
    }
    /// The generic sentence the push relay writes, used as the hidden-preview placeholder (Android's public version).
    public static func generic(reason: String, english: Bool) -> String {
        switch reason {
        case "finished": return english ? "A bot has finished. Open to review." : "機器人已完成，請開啟查看。"
        case "failed": return english ? "A bot couldn't finish. Open to review." : "機器人未能完成，請開啟查看。"
        default: return english ? "A bot needs your attention. Open to review." : "機器人需要您的注意，請開啟查看。"
        }
    }
    /// Notification category per kind of reason: its placeholder is what iOS shows when previews are hidden.
    public static func category(reason: String) -> String {
        "woowtechbot." + (reason == "finished" ? "finished" : reason == "failed" ? "failed" : "attention")
    }
}

/// What the notification service extension needs to read a preview from one registered service: written by the app only
/// after the service acknowledged this phone's push registration, removed when it is revoked or push is turned off.
public struct BotPushPreviewCredential: Codable, Equatable, Sendable {
    public let v: Int
    public let serviceId: UUID
    public let origin: String
    public let cookie: String
    public let sessionId: String?
    public let locale: String

    public init(serviceId: UUID, origin: String, cookie: String, sessionId: String?, locale: String) throws {
        v = 1; self.serviceId = serviceId; self.origin = origin; self.cookie = cookie; self.sessionId = sessionId; self.locale = locale
        try validate()
    }
    public func validate() throws {
        let policy = try BotServiceOrigin(origin)
        // Scalars, not Characters: "\r\n" is one Character, so `contains("\n")` would miss it.
        func oneLine(_ text: String) -> Bool { !text.unicodeScalars.contains { $0 == "\r" || $0 == "\n" } }
        guard v == 1, policy.value == origin, origin.hasPrefix("https://"), !cookie.isEmpty, cookie.utf8.count <= 16384,
              oneLine(cookie), ["zh-TW", "en"].contains(locale),
              sessionId.map({ (1...256).contains($0.utf8.count) && oneLine($0) }) ?? true
        else { throw BotServiceError.invalidData }
    }
}

/// Keychain items shared with the notification service extension through one access group (this device only, readable
/// after the first unlock so a notification on the lock screen can still be read). Nothing else of the app is in it.
public struct BotPushPreviewKeychain: Sendable {
    public static let service = "io.woowtech.assistant.bot.push-preview"
    public let accessGroup: String
    public init(accessGroup: String) { self.accessGroup = accessGroup }

    private func query(_ id: UUID?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                kSecAttrAccessGroup as String: accessGroup, kSecUseDataProtectionKeychain as String: true]
        if let id { q[kSecAttrAccount as String] = id.uuidString.lowercased() }
        return q
    }
    public func save(_ credential: BotPushPreviewCredential) throws {
        try credential.validate()
        let data = try JSONEncoder().encode(credential)
        let base = query(credential.serviceId)
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw BotServiceError.unavailable }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw BotServiceError.unavailable }
    }
    public func load(_ id: UUID) -> BotPushPreviewCredential? {
        var q = query(id)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count <= 65536,
              let credential = try? JSONDecoder().decode(BotPushPreviewCredential.self, from: data),
              credential.serviceId == id, (try? credential.validate()) != nil else { return nil }
        return credential
    }
    public func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
    public func deleteAll() { SecItemDelete(query(nil) as CFDictionary) }
}

/// Two fixed GETs of the website's own API with the verified session: no shared cookie jar, cache or redirect, 5 s and
/// 1 MiB each (Android woow.26). Any failure leaves that part out; both failing gives nil.
public enum BotPushPreviewFetch {
    public static let timeout: TimeInterval = 5
    public static let limit = 1_048_576

    public static func preview(_ credential: BotPushPreviewCredential, botID: String, threadID: String,
                               configuration: URLSessionConfiguration = .ephemeral) async -> BotPushPreview? {
        guard BotNotificationTarget.validID(botID), let messages = BotPushPreviewText.messagesPath(threadID) else { return nil }
        async let bots = get(credential, path: BotPushPreviewText.botsPath, configuration: configuration)
        async let thread = get(credential, path: messages, configuration: configuration)
        let name = await bots.flatMap { BotPushPreviewText.name($0, botID: botID) }
        let excerpt = await thread.flatMap { BotPushPreviewText.excerpt($0) }
        return name == nil && excerpt == nil ? nil : BotPushPreview(botName: name, excerpt: excerpt)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }

    static func get(_ credential: BotPushPreviewCredential, path: String, configuration: URLSessionConfiguration) async -> Data? {
        guard BotPushPreviewText.isPreviewPath(path), (try? credential.validate()) != nil,
              let url = URL(string: credential.origin + path), (try? BotServiceOrigin(credential.origin))?.allows(url) == true
        else { return nil }
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(credential.origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 WOOWTECH-Assistant-iOS", forHTTPHeaderField: "User-Agent")
        if let id = credential.sessionId { request.setValue(id, forHTTPHeaderField: "X-Woowtech-Session-Id") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == url else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }
}
