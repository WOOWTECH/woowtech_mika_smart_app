#if os(iOS)
import AssistantSkills
import AssistantModels
import SwiftUI
import UIKit

/// Settings root and its model destination share the existing stores. The
/// model page (ModelProviderSettingsView) lists providers as Android does.
@MainActor
struct MikaAlignedSettingsView<MCPDestination: View, MemoryDestination: View>: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var preferences: SelfConfigurationStore
    @ObservedObject var notifications: TaskNotificationStore
    @ObservedObject var languages: AppLanguageStore
    private let mcpDestination: () -> MCPDestination
    private let memoryDestination: () -> MemoryDestination
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var aboutCopy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }
    private var aboutInfo: MikaAboutInfo { MikaAboutInfo(bundle: .main) }
    /// Android names the main model's provider here, never the model ID.
    private var configuredProviderName: String {
        guard session.hasStoredKey, let saved = session.savedSettings else { return localizer.text(.settingsModelNotSet) }
        return session.providerDocument.mainProvider?.name ?? ModelProviderName.name(for: saved.baseURL)
    }
    /// The status card's line once everything is ready: 主模型：{模型} · {服務商}.
    private var readyDetail: AppText {
        guard session.hasStoredKey, let saved = session.savedSettings else { return .settingsStatusReadyDetail }
        return .settingsStatusReadyMain(model: saved.model, provider: configuredProviderName)
    }
    private var notificationSummary: MikaNotificationSummary? {
        MikaNotificationSummary(enabled: notifications.service.enabled,
                                settings: notifications.service.systemSettings)
    }
    /// Android StatusCopy.notificationSummary tones: 正常 ok, lowered warn, 已關閉 bad.
    private var notificationTone: MikaSettingsTone {
        switch notificationSummary {
        case .normal?: return .ok
        case .lowered?: return .warn
        case .off?: return .bad
        case nil: return .plain
        }
    }
    private var problem: MikaSettingsProblem? {
        MikaSettingsProblem.first(hasModel: session.savedSettings != nil && session.hasStoredKey,
                                  notifications: notificationSummary)
    }

    init(session: ChatSession, preferences: SelfConfigurationStore,
         notifications: TaskNotificationStore, languages: AppLanguageStore,
         @ViewBuilder mcpDestination: @escaping () -> MCPDestination,
         @ViewBuilder memoryDestination: @escaping () -> MemoryDestination) {
        self.session = session
        self.preferences = preferences
        self.notifications = notifications
        self.languages = languages
        self.mcpDestination = mcpDestination
        self.memoryDestination = memoryDestination
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaSettingsStatusCard(problem: problem, readyDetail: readyDetail, localizer: localizer, palette: palette) { statusFix }
                    .padding(.top, 12)
                MikaSettingsGroupLabel(title: localizer.text(.settingsHomeBasic))
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        NavigationLink {
                            MikaModelSettingsDetailView(session: session, languages: languages)
                        } label: {
                            MikaSettingsRow(icon: .spark, title: localizer.text(.settingsHomeModel),
                                            subtitle: localizer.text(.settingsHomeModelDetail),
                                            value: configuredProviderName)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text(verbatim: localizer.text(.settingsHomeModelOpenHint)))
                        .accessibilityIdentifier("settings.modelJump")
                        Divider().padding(.leading, 60)
                        NavigationLink {
                            MikaLanguageAppearanceView(preferences: preferences, languages: languages)
                        } label: {
                            // Android settings_language_appearance has no subtitle.
                            MikaSettingsRow(icon: .globe, title: localizer.text(.settingsHomeLanguageAppearance),
                                            value: localizer.languageName(languages.language))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearance")
                        Divider().padding(.leading, 60)
                        NavigationLink {
                            TaskNotificationSettingsView(store: notifications)
                        } label: {
                            MikaSettingsRow(icon: .bell, title: localizer.text(.settingsNotificationsTitle),
                                            subtitle: localizer.text(.settingsHomeNotificationDetail),
                                            value: notificationSummary.map { localizer.text($0.text) },
                                            valueTone: notificationTone)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.notifications")
                    }
                }
                MikaSettingsGroupLabel(title: localizer.text(.settingsHomeMyData))
                    .padding(.top, 8)
                MikaSettingsCard {
                    NavigationLink {
                        memoryDestination()
                    } label: {
                        MikaSettingsRow(icon: .heart, title: localizer.text(.shellMemoryTitle),
                                        subtitle: localizer.text(.settingsHomeMemoryDetail))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.memoryJump")
                }
                MikaSettingsGroupLabel(title: aboutCopy.text(.group))
                    .padding(.top, 8)
                MikaSettingsCard {
                    NavigationLink {
                        MikaAdvancedSettingsView(languages: languages, mcpDestination: mcpDestination)
                    } label: {
                        MikaSettingsRow(icon: .wrench, title: localizer.text(.settingsAdvancedTitle),
                                        subtitle: localizer.text(.settingsAdvancedDetail))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.advanced")
                }
                .padding(.bottom, 8)
                MikaSettingsCard {
                    NavigationLink {
                        MikaAboutView(languages: languages, info: aboutInfo)
                    } label: {
                        MikaSettingsRow(icon: .info, title: aboutCopy.text(.title),
                                        value: aboutInfo.version ?? aboutCopy.text(.unavailable))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about")
                    .accessibilityLabel(aboutCopy.text(.title))
                    .accessibilityValue(aboutInfo.version ?? aboutCopy.text(.unavailable))
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.settingsHomeTitle))
        .navigationBarTitleDisplayMode(.inline)
        // Reads the system state only; never asks for permission.
        .task { await notifications.service.refresh() }
    }

    /// Android StatusCopy.directFix: open the model page, ask for notification
    /// permission, or open the system page where banners are turned on.
    @ViewBuilder private var statusFix: some View {
        switch problem {
        case .noModel?:
            NavigationLink {
                MikaModelSettingsDetailView(session: session, languages: languages)
            } label: {
                MikaSettingsStatusFix(title: localizer.text(.settingsStatusAdd), palette: palette)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.status.fix")
        case .notificationsOff?:
            Button(action: allowNotifications) {
                MikaSettingsStatusFix(title: localizer.text(.settingsStatusAllow), palette: palette)
            }
            .buttonStyle(.plain)
            .disabled(notifications.service.requestingAuthorization)
            .accessibilityIdentifier("settings.status.fix")
        case .alertsLowered?:
            Button(action: openNotificationSettings) {
                MikaSettingsStatusFix(title: localizer.text(.settingsStatusTurnOn), palette: palette)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.status.fix")
        case nil:
            EmptyView()
        }
    }

    /// Turns on task notifications and asks the system once. After a refusal
    /// only the system settings can allow them, as with Android's fix. The
    /// notification page's 去開啟 does the same.
    private func allowNotifications() {
        Task { if await notifications.service.allowFromUserGesture() { openNotificationSettings() } }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}

/// Android groups connection settings under Advanced. Only the supported iOS
/// destination is exposed; no proxy or execution environment is implied.
@MainActor
private struct MikaAdvancedSettingsView<MCPDestination: View>: View {
    @ObservedObject var languages: AppLanguageStore
    let mcpDestination: () -> MCPDestination
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaSettingsGroupLabel(title: localizer.text(.settingsHomeConnections))
                MikaSettingsCard {
                    NavigationLink {
                        mcpDestination()
                            .navigationTitle(localizer.text(.shellMCPServers))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        // Android mcp_servers_title has no subtitle.
                        MikaSettingsRow(icon: .link, title: localizer.text(.shellMCPServers))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.mcpJump")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.settingsAdvancedTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Android SettingsScreen StatusSummary: 一切就緒 in green, or the first
/// problem (red when it blocks tasks, amber otherwise) and its fix button.
/// The model page has no such card on Android.
@MainActor
private struct MikaSettingsStatusCard<Fix: View>: View {
    let problem: MikaSettingsProblem?
    let readyDetail: AppText
    let localizer: AppLocalizer
    let palette: MikaSettingsPalette
    @ViewBuilder let fix: () -> Fix

    private var tone: MikaSettingsTone {
        switch problem {
        case nil: return .ok
        case .noModel?: return .bad
        case .notificationsOff?, .alertsLowered?: return .warn
        }
    }

    private var copy: (title: AppText, detail: AppText) {
        switch problem {
        case nil: return (.settingsStatusReady, readyDetail)
        case .noModel?: return (.settingsStatusNoModel, .settingsStatusNoModelDetail)
        case .notificationsOff?: return (.settingsStatusNotificationsOff, .settingsStatusNotificationsOffDetail)
        case .alertsLowered?: return (.settingsStatusAlertsLowered, .settingsStatusAlertsLoweredDetail)
        }
    }

    var body: some View {
        MikaSettingsCard {
            HStack(spacing: 12) {
                Image(systemName: problem == nil ? "checkmark" : "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.color(for: tone))
                    .frame(width: 36, height: 36)
                    .background(palette.softColor(for: tone), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localizer.text(copy.title))
                        .font(.headline).foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.status")
                    Text(verbatim: localizer.text(copy.detail))
                        .font(.caption).foregroundStyle(palette.hint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.status.detail")
                }
                Spacer(minLength: 0)
                fix()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

/// Android MikaButton(kind = Tonal, size = Small): a 32 point capsule.
private struct MikaSettingsStatusFix: View {
    let title: String
    let palette: MikaSettingsPalette

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(palette.fill, in: Capsule())
            .contentShape(Capsule())
    }
}

#endif
