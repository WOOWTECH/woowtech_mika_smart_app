#if WOOWTECHBOT
import AssistantPersistence
import Foundation
import SwiftUI

struct BotServiceActions {
    let name: String
    let url: URL
    let local: () -> Void
    let downloads: () -> Void
    let pairing: () -> Void
}

struct BotPushSettingsSection: View {
    let localizer: AppLocalizer
    @ObservedObject private var push = BotPushController.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    var body: some View {
        Section(t("服務通知", "Service notifications")) {
            Toggle(t("允許服務推播", "Allow service push"), isOn: Binding(get: { push.optedIn }, set: push.setOptIn))
                .accessibilityIdentifier("bot.push.enabled")
            Text(push.status.text(localizer)).font(.footnote).accessibilityIdentifier("bot.push.status")
            Text(t("PaaS、Home Assistant add-on、Podman 各自配對與註冊。通知只提示開啟查看，不會執行核准或操作。", "Pair and register PaaS, Home Assistant add-on and Podman separately. Notifications invite you to open the service; they do not approve or execute actions."))
                .font(.footnote).foregroundStyle(.secondary)
            Button(t("重新檢查推播", "Check push again")) { push.schedule() }.accessibilityIdentifier("bot.push.retry")
            Button(t("開啟通知設定", "Open notification settings")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }.accessibilityIdentifier("bot.push.settings")
        }.disabled(!workspace.available)
    }
}

struct BotNotificationSettingsView: View {
    @ObservedObject var store: TaskNotificationStore
    let localizer: AppLocalizer
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @ObservedObject private var push = BotPushController.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var palette: MikaVisualPalette { .init(scheme) }
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    var body: some View {
        NavigationStack {
            Form {
                BotPushSettingsSection(localizer: localizer)
                Section(t("我的服務", "My services")) {
                    ForEach(workspace.services) { service in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(service.name).font(.headline)
                            Text((service.enabled ? push.services[service.id] ?? (push.optedIn ? .checking : .off) : .off).text(localizer))
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("bot.notification.service.\(service.id)")
                        }
                    }
                }
                Section {
                    NavigationLink {
                        TaskNotificationSettingsView(store: store)
                    } label: { Label(t("本機助理通知", "Local assistant notifications"), systemImage: "iphone") }
                    .accessibilityIdentifier("bot.notifications.local")
                }
            }
            .scrollContentBackground(.hidden).background(palette.background).tint(palette.accent)
            .navigationTitle(t("通知", "Notifications")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(t("完成", "Done")) { dismiss() }.accessibilityIdentifier("bot.notifications.done")
            } }
        }
    }
}

enum BotWorkspaceScript {
    private static let template: String? = {
        guard let url = Bundle.main.url(forResource: "workspace-controls", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    static func source(dark: Bool, localizer: AppLocalizer) -> String? {
        let english = localizer.language == .english
        let config = ["skin": dark ? "midnight" : "daylight", "services": english ? "Services" : "服務", "notifications": english ? "Notifications" : "通知"]
        guard let template, let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "__WOOW_CONFIGURATION__", with: json)
    }
}
#endif
