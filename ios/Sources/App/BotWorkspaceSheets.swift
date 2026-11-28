#if WOOWTECHBOT
import AssistantPersistence
import SwiftUI

/// Android's three bottom sheets (BotServicesActivity, the manage sheet inside BotServiceActivity, BotPushSettingsActivity),
/// rebuilt from the same components: a hint, labelled cards of settings rows, a pill button, dialogs on the popover surface.

private func botText(_ localizer: AppLocalizer, _ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }

// MARK: Switch assistant or service

struct BotServicesSheet: View {
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    /// The service being shown, or nil when the local assistant is.
    let selectedID: UUID?
    var startAdding = false
    let onLocal: () -> Void
    let onOpen: (UUID) -> Void
    let onManage: (UUID) -> Void
    let onClose: () -> Void
    @State private var adding: Bool
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { botText(localizer, zh, en) }

    init(workspace: BotWorkspaceStore, localizer: AppLocalizer, selectedID: UUID?, startAdding: Bool = false,
         onLocal: @escaping () -> Void, onOpen: @escaping (UUID) -> Void, onManage: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.workspace = workspace; self.localizer = localizer; self.selectedID = selectedID
        self.startAdding = startAdding; self.onLocal = onLocal; self.onOpen = onOpen; self.onManage = onManage; self.onClose = onClose
        _adding = State(initialValue: startAdding)
    }

    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        BotSheetScaffold(title: t("切換助理／服務", "Switch assistant or service"), closeLabel: t("關閉", "Close"),
                         closeIdentifier: "bot.services.done", close: onClose) {
            Text(t("切換服務後會打開它的機器人列表。各服務的對話與登入分開保留。",
                   "Switching opens the service's bot list. Each service keeps its own conversations and sign-in."))
                .scaledFont(size: 14).foregroundStyle(palette.secondaryInk).lineSpacing(3)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            BotSectionLabel(text: t("這支手機", "This phone"))
            BotCard {
                BotSettingsRow(title: BotBrand.appName(localizer), subtitle: t("對話、工具與設定", "Your conversations, tools and settings"),
                               symbol: "bubble.left.and.bubble.right", identifier: "bot.serviceTools.local", action: onLocal) {
                    if selectedID == nil {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .regular)).foregroundStyle(palette.ink)
                            .accessibilityLabel(t("已選取", "Selected"))
                    } else { BotChevron() }
                }
            }
            BotSectionLabel(text: t("助理與服務", "Assistants and services"))
            if failed || !workspace.available {
                Text(failed ? t("無法儲存變更。若已清除多個工作階段，請重新啟動 App 完成舊設定檔刪除，再重試。",
                                "Could not save this change. If many sessions were cleared, restart the app to finish deleting old profiles and try again.")
                            : t("無法讀取服務資料，本機助理不受影響。", "Service metadata could not be read. Your local assistant is unaffected."))
                    .scaledFont(size: 13).foregroundStyle(palette.destructive).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("bot.services.error")
            }
            if !workspace.services.isEmpty {
                BotCard {
                    ForEach(Array(workspace.services.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { BotCardDivider() }
                        BotSettingsRow(title: service.name,
                                       subtitle: service.enabled ? service.origin : service.origin + "\n" + t("已在這支手機中斷連線", "Disconnected on this phone"),
                                       symbol: "link", enabled: workspace.available, identifier: "bot.service.\(service.id).open",
                                       action: { open(service) }) {
                            if selectedID == service.id {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .regular)).foregroundStyle(palette.ink)
                                    .accessibilityLabel(t("已選取", "Selected"))
                            }
                        } accessory: {
                            Button { manage(service) } label: {
                                Image(systemName: "ellipsis").font(.system(size: 17, weight: .regular)).foregroundStyle(palette.secondaryInk)
                                    .frame(width: 40, height: 40).contentShape(Circle())
                            }
                            .buttonStyle(.plain).padding(.trailing, 8).disabled(!workspace.available)
                            .accessibilityLabel(t("管理登入／移除服務", "Manage sign-in / remove service"))
                            .accessibilityIdentifier("bot.service.\(service.id).menu")
                        }
                    }
                }
            }
            BotPillButton(title: t("新增 woowtechbot 服務", "Add woowtechbot service"), symbol: "plus",
                          enabled: workspace.available && workspace.services.count < 20, identifier: "bot.services.add") { adding = true }
        }
        .botDialog(isPresented: adding, dismiss: { adding = false }) {
            BotAddServiceDialog(workspace: workspace, localizer: localizer) { adding = false }
        }
    }

    /// Opening a service does not claim it has authenticated; a disconnected one is connected again first.
    private func open(_ service: BotServiceRecord) {
        do { try workspace.setEnabled(service.id, true); onOpen(service.id) } catch { failed = true }
    }
    /// The "…" opens the service with its manage sheet; a disconnected service has no page to show without connecting first.
    private func manage(_ service: BotServiceRecord) {
        do { try workspace.setEnabled(service.id, true); onManage(service.id) } catch { failed = true }
    }
}

/// A dialog on the website's popover surface (Android `AddServiceDialog`).
private struct BotAddServiceDialog: View {
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    let done: () -> Void
    @State private var name = ""
    @State private var address = ""
    @State private var allowLAN = false
    @State private var invalid = false
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { botText(localizer, zh, en) }

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        BotDialogSurface {
            BotDialogTitle(text: t("新增 woowtechbot 服務", "Add woowtechbot service"), size: 19)
            VStack(alignment: .leading, spacing: 12) {
                BotTextField(label: t("服務名稱", "Service name"), text: Binding(get: { name }, set: { name = String($0.prefix(80)) }),
                             identifier: "bot.add.name", look: .app)
                BotTextField(label: t("服務網址（https://bot.example.com）", "Service origin (https://bot.example.com)"),
                             text: Binding(get: { address }, set: { address = String($0.prefix(2048)) }),
                             identifier: "bot.add.address", keyboard: .URL, look: .app)
                Button { allowLAN.toggle() } label: {
                    HStack(alignment: .top, spacing: 4) {
                        BotCheckbox(checked: allowLAN)
                        Text(t("允許信任的區域網路位址（私有 IP 或 .local）使用未加密 HTTP。同一網路可能看見密碼與訊息。",
                               "Allow unencrypted HTTP for a trusted LAN address (private IP or .local). Passwords and messages may be visible on that network."))
                            .scaledFont(size: 13).lineSpacing(2).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.leading)
                            .padding(.top, 14).padding(.trailing, 4).frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityRepresentation { Toggle(t("允許此區網服務使用 HTTP", "Allow HTTP for this LAN service"), isOn: $allowLAN).accessibilityIdentifier("bot.add.lan") }
                if invalid || failed {
                    Text(failed ? t("無法儲存變更。若已清除多個工作階段，請重新啟動 App 完成舊設定檔刪除，再重試。",
                                    "Could not save this change. If many sessions were cleared, restart the app to finish deleting old profiles and try again.")
                                : t("請輸入名稱與服務來源網址，不含路徑、登入碼、帳密或查詢參數。除非啟用信任的區網 HTTP，否則必須使用 HTTPS。",
                                    "Enter a name and an origin only: no path, sign-in code, credentials, or query. HTTPS is required unless trusted LAN HTTP is enabled."))
                        .scaledFont(size: 13).foregroundStyle(palette.destructive).accessibilityIdentifier("bot.services.error")
                }
            }.padding(.top, 16)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: done) {
                    Text(t("取消", "Cancel")).scaledFont(size: 14, weight: .medium).foregroundStyle(palette.secondaryInk)
                        .padding(.horizontal, 12).frame(minHeight: 40).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("bot.add.cancel")
                BotPillButton(title: t("新增 woowtechbot 服務", "Add woowtechbot service"), primary: true, fill: false, look: .app,
                              identifier: "bot.add.save", action: add)
            }.padding(.top, 24)
        }
    }

    private func add() {
        invalid = false; failed = false
        do { _ = try workspace.add(name: name, address: address, allowLAN: allowLAN); done() }
        catch BotServiceError.invalidAddress { invalid = true }
        catch BotServiceError.invalidName { invalid = true }
        catch { failed = true }
    }
}

/// Material's checkbox: an 18-point box, filled with the accent when checked, in a 48-point target.
private struct BotCheckbox: View {
    let checked: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 3).strokeBorder(checked ? Color.clear : palette.secondaryInk, lineWidth: 2)
            if checked {
                RoundedRectangle(cornerRadius: 3).fill(palette.accent)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.background)
            }
        }.frame(width: 18, height: 18).frame(width: 48, height: 48).accessibilityHidden(true)
    }
}

// MARK: Manage one service

/// The sheet behind a service's "…" (Android's manage sheet): the address, then the actions on this service.
struct BotManageSheet: View {
    let service: BotServiceRecord
    let localizer: AppLocalizer
    let scan: () -> Void
    let reload: () -> Void
    let downloads: () -> Void
    let disconnect: () -> Void
    let logout: () -> Void
    let remove: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { botText(localizer, zh, en) }

    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        BotSheetScaffold(title: service.name, closeLabel: t("關閉", "Close"), closeIdentifier: "bot.manage.close", close: close) {
            Text(service.origin).scaledFont(size: 13).foregroundStyle(palette.secondaryInk).textSelection(.enabled)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            BotCard {
                BotSettingsRow(title: t("掃描配對 QR", "Scan pairing QR"), symbol: "camera", enabled: service.enabled,
                               identifier: "bot.manage.scan", action: scan)
                BotCardDivider()
                BotSettingsRow(title: t("重新載入網頁", "Reload website"), symbol: "arrow.clockwise", identifier: "bot.manage.reload", action: reload)
                BotCardDivider()
                ShareLink(item: service.policy.url) {
                    BotRowLabel(title: t("分享服務網址", "Share service address"), symbol: "square.and.arrow.up").contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("bot.manage.share")
                BotCardDivider()
                BotSettingsRow(title: t("下載項目", "Downloads"), symbol: "arrow.down.circle", identifier: "bot.manage.downloads", action: downloads)
                BotCardDivider()
                BotSettingsRow(title: t("中斷連線", "Disconnect"), symbol: "link", identifier: "bot.manage.disconnect", action: disconnect)
                BotCardDivider()
                BotSettingsRow(title: t("登出服務", "Log out of service"), symbol: "lock", identifier: "bot.manage.logout", action: logout)
                BotCardDivider()
                BotSettingsRow(title: t("移除服務", "Remove service"), symbol: "trash", destructive: true, identifier: "bot.manage.remove", action: remove)
            }
        }
    }
}

/// Logout and removal share one confirmation (Android `MikaDialog`): ink pill buttons, removal in red.
struct BotRetireDialog: View {
    let remove: Bool
    let localizer: AppLocalizer
    let confirm: () -> Void
    let cancel: () -> Void
    private func t(_ zh: String, _ en: String) -> String { botText(localizer, zh, en) }
    var body: some View {
        BotDialogSurface {
            BotDialogTitle(text: remove ? t("移除服務", "Remove service") : t("登出服務", "Log out of service"))
            BotDialogBody(text: t("清除此服務在手機上的 Cookie 與網頁資料，並嘗試撤銷伺服器登入。若離線，請稍後在服務的工作階段設定撤銷。其他服務與本機助理不受影響。",
                                  "Clear this service’s cookies and website data on this phone. We will also try to revoke the server session; if offline, revoke it later in the service’s session settings. Other services and the local assistant are unaffected."))
            HStack(spacing: 10) {
                BotDialogButton(title: t("取消", "Cancel"), kind: .dismiss, identifier: "bot.retire.cancel", action: cancel)
                BotDialogButton(title: t("確認", "Confirm"), kind: remove ? .destructive : .confirm, identifier: "bot.retire.confirm", action: confirm)
            }.padding(.top, 24)
        }
    }
}

// MARK: Bot notifications

/// Bot notifications as a bottom sheet (Android `BotPushSettingsActivity`): a privacy line, one card with the switch, the retry
/// row when a check is incomplete and the system settings row, then one status row per enabled service.
struct BotNotificationsSheet: View {
    let localizer: AppLocalizer
    let close: () -> Void
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @ObservedObject private var push = BotPushController.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    private func t(_ zh: String, _ en: String) -> String { botText(localizer, zh, en) }

    /// Android: enabled = (configured || opted in) && not pending - greyed when this build has no push at all, and while a
    /// registration pass is still running.
    private var switchEnabled: Bool {
        let configured = push.status != .unavailable
        let pending = push.status == .waitingAPNs || push.status == .checking
        return workspace.available && (configured || push.optedIn) && !pending
    }

    private var retryable: Bool {
        switch push.status { case .retry, .serverNotReady, .signInUnavailable, .cleanupPending: return true; default: return false }
    }

    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        BotSheetScaffold(title: t("機器人通知", "Bot notifications"), closeLabel: t("關閉", "Close"),
                         closeIdentifier: "bot.notifications.done", close: close) {
            Text(t("通知會顯示是哪個機器人回覆和內容摘要；內容由手機直接向服務讀取，不經過推播服務。",
                   "Notifications show which bot replied and the start of its reply. The phone reads them from the service itself; they never pass through the push service."))
                .scaledFont(size: 14).foregroundStyle(palette.secondaryInk).lineSpacing(3)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            BotCard {
                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 17, weight: .regular)).frame(width: 20, height: 20)
                        .foregroundStyle(palette.secondaryInk).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("允許機器人通知", "Allow bot notifications")).scaledFont(size: 15, weight: .medium).foregroundStyle(palette.ink)
                        Text(push.status.text(localizer)).scaledFont(size: 13).foregroundStyle(palette.secondaryInk)
                            .accessibilityIdentifier("bot.push.status")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    BotSwitch(isOn: Binding(get: { push.optedIn }, set: push.setOptIn),
                              enabled: switchEnabled, label: t("允許機器人通知", "Allow bot notifications"), identifier: "bot.push.enabled")
                }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 12)
                if retryable {
                    BotCardDivider()
                    BotSettingsRow(title: t("重新檢查註冊", "Retry registration check"), symbol: "arrow.clockwise", identifier: "bot.push.retry",
                                   action: { push.schedule() }) { BotChevron() }
                }
                BotCardDivider()
                BotSettingsRow(title: t("iOS 通知設定", "iOS notification settings"), symbol: "gearshape", identifier: "bot.push.settings", action: {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }) { BotChevron() }
            }
            let enabled = workspace.services.filter(\.enabled)
            if !enabled.isEmpty {
                BotSectionLabel(text: t("助理與服務", "Assistants and services"))
                BotCard {
                    ForEach(Array(enabled.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { BotCardDivider() }
                        BotSettingsRow(title: service.name,
                                       subtitle: (push.services[service.id] ?? (push.optedIn ? .checking : .off)).text(localizer),
                                       symbol: "link", identifier: "bot.notification.service.\(service.id)")
                    }
                }
            }
        }
        .onAppear { push.schedule() }
    }
}
#endif
