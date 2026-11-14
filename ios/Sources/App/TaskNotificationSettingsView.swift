import SwiftUI
import UIKit
import AssistantDomain

/// Play's Settings › 通知 (SettingsSubPages.kt NotificationsScreen at 964d7bec):
/// 通知總開關, the 任務通知 group with 需要你處理 and 任務結果, then a footer.
/// The page shows the state; iOS Settings is where it changes, as on Play.
/// iOS has one notification setting for the App, not a channel per kind, so
/// both kinds read the same and open the App's notification settings. Play's
/// 任務進度 row is left out: iOS has no ongoing progress notification.
@MainActor struct TaskNotificationSettingsView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var store: TaskNotificationStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    /// The same summary as the Settings row; nil until iOS was read once.
    private var summary: MikaNotificationSummary? {
        MikaNotificationSummary(enabled: store.service.enabled, settings: store.service.systemSettings)
    }
    /// Play's appAllowed: turned on in the App and allowed by iOS, so task
    /// notifications can actually be delivered.
    private var allowed: Bool? { summary.map { $0 != .off } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaSettingsCard { master }
                    .padding(.top, 12)
                if let notice = store.service.notice {
                    Text(verbatim: localizer.text(AppLocalizer.notificationNotice(notice)))
                        .font(.footnote).foregroundStyle(palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.top, 10)
                        .accessibilityIdentifier("notifications.notice")
                }
                MikaSettingsGroupLabel(title: localizer.text(.notificationTitle))
                    .padding(.top, 8)
                    .accessibilityIdentifier("notifications.group")
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        kindRow(.settingsNotificationsAttention, purpose: .settingsNotificationsAttentionWhen,
                                id: "notifications.attention")
                        Divider().padding(.leading, 60)
                        kindRow(.settingsNotificationsResult, purpose: .settingsNotificationsResultWhen,
                                id: "notifications.result")
                    }
                }
                Text(verbatim: localizer.text(.settingsNotificationsFooter))
                    .font(.footnote).foregroundStyle(palette.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 10)
                    .accessibilityIdentifier("notifications.footer")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestMode") { testControls }
                #endif
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.settingsNotificationsTitle))
        .navigationBarTitleDisplayMode(.inline)
        // Reads the system state only, never asks: on opening and on every
        // return to the App, such as from iOS Settings. No refresh button.
        .task { await store.service.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.service.refresh() } }
        }
    }

    /// Play's 通知總開關. Only while notifications cannot be delivered is the
    /// row a button: 去開啟 turns them on, as 允許 on the Settings status card.
    @ViewBuilder private var master: some View {
        if allowed == false {
            Button(action: allow) { masterRow }
                .buttonStyle(.plain)
                .disabled(store.service.requestingAuthorization)
                .accessibilityValue(Text(verbatim: masterState ?? ""))
                .accessibilityIdentifier("notifications.enabled")
        } else {
            masterRow
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(verbatim: masterState ?? ""))
                .accessibilityIdentifier("notifications.enabled")
        }
    }

    private var masterRow: TaskNotificationSettingsRow {
        TaskNotificationSettingsRow(
            title: localizer.text(.settingsNotificationsMaster),
            subtitle: allowed.map { localizer.text($0 ? .settingsNotificationsMasterOn : .settingsNotificationsMasterOff) },
            state: masterState, tone: allowed == false ? .bad : .plain, opens: allowed == false)
    }

    /// Play's settings_allowed or heads_up_action.
    private var masterState: String? {
        allowed.map { localizer.text($0 ? .notificationAuthorized : .settingsStatusTurnOn) }
    }

    /// Play's ChannelRowItem: the kind, when it is sent and how it shows up
    /// now. A tap opens the App's iOS notification settings.
    private func kindRow(_ title: AppText, purpose: AppText, id: String) -> some View {
        Button(action: openNotificationSettings) {
            TaskNotificationSettingsRow(title: localizer.text(title), subtitle: localizer.text(purpose),
                                        state: kindState.map { localizer.text($0.text) },
                                        tone: kindState?.lowered == true ? .warn : .plain, opens: true)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: kindState.map { localizer.text($0.text) } ?? ""))
        .accessibilityHint(Text(verbatim: localizer.text(.notificationOpenSettings)))
        .accessibilityIdentifier(id)
    }

    /// Play's ChannelLevel from the one App-level iOS state. Both kinds should
    /// pop up, so the quiet level is marked; while the master switch is off
    /// both are plain 已關閉, as on Play, where the master switch is the problem.
    private var kindState: (text: AppText, lowered: Bool)? {
        switch summary {
        case .normal?: return (.settingsNotificationsPopsUp, false)
        case .lowered?: return (.settingsNotificationsQuiet, true)
        case .off?: return (.notificationOff, false)
        case nil: return nil
        }
    }

    /// Android Fix.AllowNotifications: after a refusal only iOS Settings can
    /// allow them, so they open instead of asking again.
    private func allow() {
        Task { if await store.service.allowFromUserGesture() { openNotificationSettings() } }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }

    #if DEBUG
    /// UI tests only. Play has no test button, so the product has none: tests
    /// post the fixed test notification to check the actual system banner and
    /// what tapping it opens. The raw iOS authorization, which the page does
    /// not list, tells them whether 去開啟 brings up the system prompt.
    @ViewBuilder private var testControls: some View {
        Button(localizer.text(.notificationTest)) { Task { _ = await store.service.sendTestFromUserGesture() } }
            .font(.footnote)
            .disabled(!store.service.enabled || store.service.systemSettings.authorization != .authorized
                      || store.service.requestingAuthorization)
            .accessibilityIdentifier("notifications.test")
            .padding(.horizontal, 16).padding(.top, 12)
        Text(verbatim: store.service.systemSettings.authorization.rawValue)
            .font(.caption2).foregroundStyle(.clear).frame(height: 1)
            .accessibilityValue(Text(verbatim: store.service.systemSettings.authorization.rawValue))
            .accessibilityIdentifier("notifications.authorization")
    }
    #endif
}

/// Android ListRow as Play's notification page uses it: a bell tile coloured
/// only for a state (TileTone Bad or Warn), the title, when it applies, the
/// current state as a third line and a chevron when a tap leads somewhere.
/// The state line is read out as the row's accessibility value instead.
private struct TaskNotificationSettingsRow: View {
    let title: String
    let subtitle: String?
    let state: String?
    let tone: MikaSettingsTone
    let opens: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 14) {
            MikaSettingsIconShape(icon: .bell)
                .stroke(tone == .plain ? colors.ink : colors.color(for: tone),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .background(colors.softColor(for: tone), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body).foregroundStyle(colors.ink)
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(colors.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let state {
                    Text(verbatim: state).font(.caption).foregroundStyle(colors.hint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 11)
            Spacer(minLength: 4)
            if opens {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.hint).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

@MainActor private final class TaskNotificationBridgeOwner: ObservableObject {
    private var bridge: TaskNotificationChatBridge?
    private weak var session: ChatSession?
    func bind(_ chat: ChatSession, service: TaskNotificationService) {
        guard session !== chat else { return }
        bridge?.invalidate(); session = chat
        bridge = TaskNotificationChatBridge(session: chat, service: service)
    }
}

@MainActor private struct TaskNotificationModifier: ViewModifier {
    let chat: ChatSession
    @ObservedObject var store: TaskNotificationStore
    let onOpen: (TaskNotificationDestination) -> Void
    @StateObject private var owner = TaskNotificationBridgeOwner()
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onAppear {
                owner.bind(chat, service: store.service)
                openPendingRoute()
            }
            .task { await store.service.refresh() }
            .onChange(of: store.route?.id) { _, _ in openPendingRoute() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.service.clearNotices()
                    Task { await store.service.refresh() }
                } else {
                    store.service.invalidateApprovals()
                    // iOS pauses a web task in the background: say so, or that it waits for the person.
                    if phase == .background, let task = chat.webTask, task.isRunning {
                        store.service.postNotice(task.waitsForUser ? .webNeedsYou : .webPaused, destination: .chat)
                    }
                }
            }
    }
    private func openPendingRoute() {
        guard let route = store.route else { return }
        onOpen(route.destination); store.consumeRoute(route.id)
    }
}

extension View {
    @MainActor func taskNotifications(chat: ChatSession, store: TaskNotificationStore,
                                     onOpen: @escaping (TaskNotificationDestination) -> Void) -> some View {
        modifier(TaskNotificationModifier(chat: chat, store: store, onOpen: onOpen))
    }
}
