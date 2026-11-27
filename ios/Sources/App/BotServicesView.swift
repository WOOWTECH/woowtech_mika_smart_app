#if WOOWTECHBOT
import AssistantPersistence
import SwiftUI

struct BotServicesView: View {
    @ObservedObject var workspace: BotWorkspaceStore
    @ObservedObject private var push = BotPushController.shared
    let localizer: AppLocalizer
    let open: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var allowLAN = false
    @State private var error: String?
    @State private var retirement: Retirement?
    @State private var busy = false
    private struct Retirement: Identifiable { let service: BotServiceRecord; let remove: Bool; var id: UUID { service.id } }
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(t("本機助理可獨立使用", "Local assistant works independently"), systemImage: "iphone")
                    Text(t("每個服務各自保存登入狀態。請在服務原本的頁面完成配對或登入。", "Each service has its own sign-in data. Pair or sign in on the service's original page."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(t("我的服務", "My services")) {
                    if workspace.services.isEmpty { Text(t("尚未新增服務", "No services yet")).foregroundStyle(.secondary) }
                    ForEach(workspace.services) { service in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(service.name).font(.headline)
                                    Text(service.origin).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                Menu {
                                    Button(t("登出", "Sign out"), role: .destructive) { retirement = .init(service: service, remove: false) }
                                    Button(t("移除服務", "Remove service"), role: .destructive) { retirement = .init(service: service, remove: true) }
                                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                                .accessibilityIdentifier("bot.service.\(service.id).menu")
                            }
                            Toggle(t("啟用服務", "Enable service"), isOn: Binding(get: { service.enabled }, set: { value in
                                do { try workspace.setEnabled(service.id, value) } catch { showError() }
                            })).accessibilityIdentifier("bot.service.\(service.id).enabled")
                            Button(t("開啟服務", "Open service")) { dismiss(); open(service.id) }
                                .disabled(!service.enabled)
                                .accessibilityIdentifier("bot.service.\(service.id).open")
                            if let status = push.services[service.id] {
                                Text(status.text(localizer)).font(.footnote).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("bot.service.\(service.id).push")
                            }
                        }
                    }
                }
                Section(t("新增 woowtechbot", "Add woowtechbot")) {
                    TextField(t("服務名稱", "Service name"), text: $name).accessibilityIdentifier("bot.add.name")
                    TextField("https://…", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).accessibilityIdentifier("bot.add.address")
                    Toggle(t("允許此區網服務使用 HTTP", "Allow HTTP for this LAN service"), isOn: $allowLAN)
                        .accessibilityIdentifier("bot.add.lan")
                    if allowLAN {
                        Text(t("僅限私人 IP 或 .local 位址。HTTP 不會加密登入及對話內容。", "Private IP or .local addresses only. HTTP does not encrypt sign-in or conversation data."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(t("新增服務", "Add service")) {
                        do {
                            _ = try workspace.add(name: name, address: address, allowLAN: allowLAN)
                            name = ""; address = ""; allowLAN = false; error = nil
                        } catch BotServiceError.invalidAddress {
                            error = t("請填服務首頁網址，不含配對碼、路徑或帳密。HTTPS 或已允許的區網 HTTP 才可使用。", "Enter the service origin without pairing codes, paths or credentials. Use HTTPS or explicitly allowed LAN HTTP.")
                        } catch BotServiceError.invalidName { error = t("請填 1–80 字的服務名稱。", "Enter a service name of 1–80 characters.") }
                        catch { showError() }
                    }.accessibilityIdentifier("bot.add.save")
                }
                Section(t("服務通知", "Service notifications")) {
                    Toggle(t("允許服務推播", "Allow service push"), isOn: Binding(get: { push.optedIn }, set: { enabled in
                        push.setOptIn(enabled)
                    })).accessibilityIdentifier("bot.push.enabled")
                    Text(push.status.text(localizer))
                        .font(.footnote).accessibilityIdentifier("bot.push.status")
                    Text(t("PaaS、Home Assistant add-on、Podman 各自配對與註冊。通知只提示開啟查看，不會執行核准或操作。", "Pair and register PaaS, Home Assistant add-on and Podman separately. Notifications invite you to open the service; they do not approve or execute actions."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(t("重新檢查推播", "Check push again")) { push.schedule() }
                        .accessibilityIdentifier("bot.push.retry")
                    Button(t("開啟通知設定", "Open notification settings")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }.accessibilityIdentifier("bot.push.settings")
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("bot.services.error") } }
            }
            .disabled(!workspace.available || busy)
            .navigationTitle(t("woowtechbot 服務", "woowtechbot services"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(t("完成", "Done")) { dismiss() }.accessibilityIdentifier("bot.services.done")
            } }
            .confirmationDialog(retirement.map { $0.remove ? t("移除這個服務？", "Remove this service?") : t("登出這個服務？", "Sign out of this service?") } ?? "",
                isPresented: Binding(get: { retirement != nil }, set: { if !$0 { retirement = nil } }),
                titleVisibility: .visible, presenting: retirement) { action in
                Button(action.remove ? t("移除", "Remove") : t("登出", "Sign out"), role: .destructive) {
                    busy = true; retirement = nil
                    Task {
                        defer { busy = false }
                        do { try await workspace.retire(action.service.id, remove: action.remove) }
                        catch { showError() }
                    }
                }
                Button(t("取消", "Cancel"), role: .cancel) { retirement = nil }
            } message: { _ in
                Text(t("將清除此服務在這台裝置的登入與網頁資料；再次開啟需要重新配對。", "This clears this service's sign-in and website data on this device. Pair again when reopening."))
            }
        }
    }
    private func showError() { error = t("設定尚未保存，請解鎖後重試。", "Settings were not saved. Unlock and try again.") }
}
#endif
