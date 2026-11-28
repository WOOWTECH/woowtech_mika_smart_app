import AssistantPersistence
import Foundation
import OSLog
import UserNotifications

/// Shows the bot that replied and the start of its reply (owner 2026-11-28, Android woow.26), read from the service with
/// the session the app verified when the service acknowledged this phone's registration. The push itself carries IDs
/// only; without a stored session, or when the service does not answer in time, the relay's generic text stays. Nothing
/// here navigates, approves or opens a URL: a tap still goes through the app's own checks.
final class NotificationService: UNNotificationServiceExtension {
    /// Outcome categories only: never a name, text, ID, cookie or address.
    private static let log = Logger(subsystem: "io.woowtech.assistant.bot", category: "BotPushPreview")
    private let lock = NSLock()
    private var handler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var work: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { contentHandler(request.content); return }
        lock.lock(); handler = contentHandler; self.content = content; lock.unlock()
        guard let target = Self.target(content.userInfo) else { Self.log.info("preview: not a bot notification"); finish(); return }
        let category = BotPushPreviewText.category(reason: target.reason)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WoowBotPreviewAccessGroup") as? String, !group.hasPrefix("$("),
              let credential = BotPushPreviewKeychain(accessGroup: group).load(target.serviceID)
        else { Self.log.info("preview: no verified session for this service"); finish { $0.categoryIdentifier = category }; return }
        work = Task { [weak self] in
            let preview = await BotPushPreviewFetch.preview(credential, botID: target.botID, threadID: target.threadID)
            Self.log.info("preview: name \(preview?.botName != nil, privacy: .public), excerpt \(preview?.excerpt != nil, privacy: .public)")
            self?.finish { content in
                content.categoryIdentifier = category
                if let name = preview?.botName { content.title = name }
                if let excerpt = preview?.excerpt {
                    content.body = BotPushPreviewText.body(excerpt: excerpt, reason: target.reason, english: credential.locale == "en")
                }
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Out of time: the relay's generic text is shown.
        Self.log.info("preview: out of time")
        work?.cancel()
        finish()
    }

    /// Hands the content over exactly once, whichever of the read and the system's deadline comes first.
    private func finish(_ update: ((UNMutableNotificationContent) -> Void)? = nil) {
        lock.lock()
        guard let handler, let content else { lock.unlock(); return }
        self.handler = nil; self.content = nil
        lock.unlock()
        update?(content)
        handler(content)
    }

    /// The same routing string the app reads: one `woowtechbot` JSON string of exactly six fields.
    static func target(_ info: [AnyHashable: Any]) -> BotNotificationTarget? {
        guard let text = info["woowtechbot"] as? String, text.utf8.count <= 2048,
              let fields = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) else { return nil }
        return try? BotNotificationTarget(fields: fields)
    }
}
