import AssistantDomain

/// Android NotificationOverview.summary for the Settings › 通知 row. The app's
/// task-notification switch and the system permission stand in for Android's
/// app-level permission. iOS has one alert setting for both kinds Android
/// expects to pop up (需要你處理, 任務結果), so a lowered state counts two.
enum MikaNotificationSummary: Equatable {
    case normal, lowered(count: Int), off

    static let popUpKinds = 2

    /// Nil until the system settings have been read once.
    init?(enabled: Bool, settings: TaskNotificationSettings) {
        guard enabled else { self = .off; return }
        switch settings.authorization {
        case .unknown: return nil
        case .notDetermined, .denied: self = .off
        // Provisional delivery goes quietly to Notification Center only.
        case .provisional: self = .lowered(count: Self.popUpKinds)
        case .authorized, .ephemeral:
            self = settings.alert == .disabled ? .lowered(count: Self.popUpKinds) : .normal
        }
    }

    var text: AppText {
        switch self {
        case .normal: return .settingsNotificationsNormal
        case .lowered(let count): return .settingsNotificationsLowered(count: count)
        case .off: return .notificationOff
        }
    }
}
