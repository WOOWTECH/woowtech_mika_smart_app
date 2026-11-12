#if os(iOS)
import AssistantSkills
import AssistantModels
import SwiftUI

/// Settings root and its model destination share the existing stores. The
/// model form remains iOS's single configured service, with a real back path.
@MainActor
struct MikaAlignedSettingsView<MCPDestination: View, MemoryDestination: View>: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var preferences: SelfConfigurationStore
    @ObservedObject var notifications: TaskNotificationStore
    @ObservedObject var languages: AppLanguageStore
    private let mcpDestination: () -> MCPDestination
    private let memoryDestination: () -> MemoryDestination
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var aboutCopy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }
    private var aboutInfo: MikaAboutInfo { MikaAboutInfo(bundle: .main) }
    private var configuredModelName: String {
        session.hasStoredKey ? (session.savedSettings?.model ?? localizer.text(.settingsModelNotSet))
                             : localizer.text(.settingsModelNotSet)
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
                MikaModelStatusCard(session: session, localizer: localizer, palette: palette)
                    .padding(.top, 12)
                MikaSettingsGroupLabel(title: localizer.text(.settingsHomeBasic))
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        NavigationLink {
                            MikaModelSettingsDetailView(session: session, languages: languages)
                        } label: {
                            MikaSettingsRow(icon: .spark, title: localizer.text(.settingsHomeModel),
                                            subtitle: localizer.text(.settingsHomeModelDetail),
                                            value: configuredModelName)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text(verbatim: localizer.text(.settingsHomeModelOpenHint)))
                        .accessibilityIdentifier("settings.modelJump")
                        Divider().padding(.leading, 60)
                        NavigationLink {
                            SelfConfigurationView(store: preferences, modelAccess: session.modelAccess,
                                                  languages: languages)
                        } label: {
                            MikaSettingsRow(icon: .globe, title: localizer.text(.languageAppearanceTitle),
                                            subtitle: localizer.text(.settingsHomeAppearanceDetail),
                                            value: localizer.languageName(languages.language))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearance")
                        Divider().padding(.leading, 60)
                        NavigationLink {
                            TaskNotificationSettingsView(store: notifications)
                        } label: {
                            MikaSettingsRow(icon: .bell, title: localizer.text(.notificationTitle),
                                            subtitle: localizer.text(.settingsHomeNotificationDetail))
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
                        MikaSettingsRow(icon: .link, title: localizer.text(.shellMCPServers),
                                        subtitle: localizer.text(.settingsHomeMCPDetail))
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

@MainActor
private struct MikaModelStatusCard: View {
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let palette: MikaSettingsPalette

    var body: some View {
        MikaSettingsCard {
            HStack(spacing: 12) {
                MikaSettingsIconShape(icon: .spark)
                    .stroke(palette.ink,
                            style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 36)
                    .background(palette.tile, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localizer.text(session.hasStoredKey ? .settingsModelConfigured : .settingsModelUnconfigured))
                        .font(.headline).foregroundStyle(palette.ink)
                        .accessibilityIdentifier("settings.status")
                    Text(verbatim: localizer.text(session.hasStoredKey ? .settingsModelKeyStored : .settingsModelKeyMissing))
                        .font(.caption).foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("settings.keyStatus")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

@MainActor
private struct MikaModelSettingsDetailView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var languages: AppLanguageStore
    @StateObject private var connection = MikaModelConnectionViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editingField: Field?

    private enum Field: Hashable { case baseURL, model, key }
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var configuredModelName: String {
        session.hasStoredKey ? (session.savedSettings?.model ?? localizer.text(.settingsModelNotSet))
                             : localizer.text(.settingsModelNotSet)
    }
    private var savedInputsMatch: Bool {
        guard let saved = session.savedSettings, session.hasStoredKey else { return false }
        return session.baseURLDraft == saved.baseURL.absoluteString && session.modelDraft == saved.model
            && session.keyDraft.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaModelStatusCard(session: session, localizer: localizer, palette: palette)
                    .padding(.top, 12)
                MikaSettingsGroupLabel(title: localizer.text(.settingsModelRoles))
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        MikaSettingsRow(icon: .spark, title: localizer.text(.settingsModelMain),
                                        subtitle: localizer.text(.settingsModelMainDetail),
                                        value: configuredModelName, accessory: .none)
                        Divider().padding(.leading, 60)
                        // Android models_sees_images: the user says whether the main model can see images.
                        Toggle(isOn: Binding(get: { session.seesImages == true }, set: { session.setSeesImages($0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: localizer.text(.settingsSeesImages))
                                Text(verbatim: localizer.text(session.seesImages == nil ? .settingsSeesImagesUnconfirmed : .settingsSeesImagesUser))
                                    .font(.footnote).foregroundStyle(palette.hint)
                            }
                        }
                        .disabled(session.savedSettings == nil || !session.hasStoredKey || session.isSubmitting)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .accessibilityIdentifier("settings.seesImages")
                        Divider().padding(.leading, 60)
                        NavigationLink {
                            VoiceSettingsView(languages: languages)
                        } label: {
                            MikaSettingsRow(icon: .spark, title: localizer.text(.voiceChoiceTitle),
                                            subtitle: localizer.text(.voiceChoiceRowDetail))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.voice.open")
                    }
                }
                MikaSettingsGroupLabel(title: localizer.text(.settingsModelProviders))
                    .padding(.top, 8)
                modelConfigurationCard
                Text(verbatim: localizer.text(.settingsModelSaveExplanation))
                    .font(.footnote).foregroundStyle(palette.hint)
                    .padding(.horizontal, 16).padding(.top, 8)
                Text(verbatim: localizer.text(.settingsModelChangeExplanation))
                    .font(.footnote).foregroundStyle(palette.hint)
                    .padding(.horizontal, 16).padding(.top, 6)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.settingsHomeModel))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { editingField = nil }
        .onDisappear { connection.reset(); session.keyDraft = "" }
        .onChange(of: session.baseURLDraft) { _, _ in connection.reset() }
        .onChange(of: session.modelDraft) { _, _ in connection.reset() }
        .onChange(of: session.keyDraft) { _, _ in connection.reset() }
        .onChange(of: session.savedSettings?.credentialAccount) { _, _ in connection.reset() }
        .onChange(of: session.isSubmitting) { _, submitting in if submitting { connection.reset() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { connection.reset() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.keyboardDone)) { editingField = nil }
                    .accessibilityIdentifier("settings.dismissKeyboard")
            }
        }
    }

    private var modelConfigurationCard: some View {
        MikaSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                MikaSettingsRow(icon: .key, title: localizer.text(.settingsModelConnection),
                                subtitle: localizer.text(.settingsModelConnectionDetail), accessory: .none)
                Divider().padding(.leading, 60)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(verbatim: localizer.text(.settingsModelBaseURL))
                        Spacer()
                        Button(localizer.text(.settingsModelClearURL)) {
                            session.baseURLDraft = ""
                            editingField = .baseURL
                        }
                        .accessibilityIdentifier("settings.clearBaseURL")
                    }
                    TextField(localizer.text(.settingsModelBaseURLPlaceholder), text: $session.baseURLDraft)
                        .keyboardType(.URL)
                        .focused($editingField, equals: .baseURL)
                        .accessibilityIdentifier("settings.baseURL")
                    Text(verbatim: localizer.text(.settingsModelName))
                    TextField(localizer.text(.settingsModelNamePlaceholder), text: $session.modelDraft)
                        .focused($editingField, equals: .model)
                        .accessibilityIdentifier("settings.model")
                    Text(verbatim: localizer.text(.settingsModelAPIKey))
                    SecureField(localizer.text(.settingsModelAPIKeyPlaceholder), text: $session.keyDraft)
                        .focused($editingField, equals: .key)
                        .privacySensitive()
                        .accessibilityIdentifier("settings.apiKey")
                    HStack {
                        Button(localizer.text(.settingsModelSave)) {
                            editingField = nil
                            connection.reset()
                            session.saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("settings.save")
                        Button(localizer.text(.settingsModelRemove), role: .destructive) {
                            editingField = nil
                            connection.reset()
                            session.removeSettings()
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("settings.remove")
                    }
                    Text(verbatim: connectionCopy(.explanation))
                        .font(.footnote).foregroundStyle(palette.hint)
                    HStack {
                        Button(connectionCopy(.test)) {
                            editingField = nil
                            do { connection.start(try session.modelAccess()) }
                            catch { connection.credentialsUnavailable() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!savedInputsMatch || session.isSubmitting || scenePhase != .active || connection.state == .testing)
                        .accessibilityIdentifier("settings.testConnection")
                        if connection.state == .testing {
                            Button(connectionCopy(.cancel)) { connection.reset() }
                                .accessibilityIdentifier("settings.cancelConnectionTest")
                        }
                    }
                    Text(verbatim: connectionStatus)
                        .foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("settings.connectionStatus")
                    #if DEBUG
                    if let fixture = connection.fixture {
                        ModelConnectionFixtureControls(fixture: fixture)
                    }
                    #endif
                    if let error = session.settingsError {
                        Text(verbatim: localizer.modelSettingsDisplayMessage(error))
                            .foregroundStyle(.red).accessibilityIdentifier("settings.error")
                    }
                    if let notice = displayedSettingsNotice {
                        Text(verbatim: notice)
                            .accessibilityIdentifier("settings.notice")
                    }
                    Text(verbatim: localizer.text(.settingsModelPrivacy))
                        .font(.footnote).foregroundStyle(palette.hint)
                }
                .textFieldStyle(.roundedBorder)
                .padding(16)
            }
        }
    }

    private var displayedSettingsNotice: String? {
        guard let notice = session.settingsNotice else { return nil }
        if connection.state == .passed {
            return notice.contains("舊金鑰清理失敗") ? connectionCopy(.cleanupNotice) : nil
        }
        return localizer.modelSettingsDisplayMessage(notice)
    }

    private enum ConnectionCopy { case test, cancel, explanation, untested, testing, passed, cleanupNotice, credentials,
        configuration, authentication, notFound, rateLimited, server, rejected, response, redirect, timeout, network }

    private var connectionStatus: String {
        let key: ConnectionCopy
        switch connection.state {
        case .untested: key = .untested
        case .testing: key = .testing
        case .passed: key = .passed
        case .failed(let failure):
            switch failure {
            case .credentials: key = .credentials
            case .configuration: key = .configuration
            case .authentication: key = .authentication
            case .notFound: key = .notFound
            case .rateLimited: key = .rateLimited
            case .server: key = .server
            case .rejected: key = .rejected
            case .response: key = .response
            case .redirect: key = .redirect
            case .timeout: key = .timeout
            case .network: key = .network
            }
        }
        return connectionCopy(key)
    }

    private func connectionCopy(_ key: ConnectionCopy) -> String {
        let values: (String, String, String)
        switch key {
        case .test: values = ("測試連線", "测试连接", "Test connection")
        case .cancel: values = ("取消測試", "取消测试", "Cancel test")
        case .explanation: values = ("請先儲存修改。測試會向已儲存的服務傳送固定短句，可能產生費用；不傳送對話。僅測試文字回覆。", "请先保存修改。测试会向已保存的服务发送固定短句，可能产生费用；不发送对话。仅测试文字回复。", "Save changes first. The test sends a fixed short prompt to the saved service and may incur charges. No conversation is sent. Tests text replies only.")
        case .untested: values = ("尚未測試連線。", "尚未测试连接。", "Connection not tested.")
        case .testing: values = ("正在測試連線…", "正在测试连接…", "Testing connection…")
        case .passed: values = ("文字回覆測試通過；未驗證工具或其他能力。", "文字回复测试通过；未验证工具或其他能力。", "Text reply test passed; tools and other capabilities were not tested.")
        case .cleanupNotice: values = ("舊金鑰清理失敗，可用移除功能清除此 App 的模型金鑰。", "旧密钥清理失败，可用移除功能清除此 App 的模型密钥。", "The old key could not be removed. Use Remove to clear this app's model keys.")
        case .credentials: values = ("無法讀取已儲存的金鑰，請檢查設定。", "无法读取已保存的密钥，请检查设置。", "Could not read the saved key. Check settings.")
        case .configuration: values = ("設定無效，請檢查網址與模型。", "设置无效，请检查网址与模型。", "Invalid settings. Check the address and model.")
        case .authentication: values = ("服務拒絕授權，請檢查金鑰與權限。", "服务拒绝授权，请检查密钥与权限。", "Authorization was rejected. Check the key and permissions.")
        case .notFound: values = ("找不到介面或模型，請檢查網址與模型名稱。", "找不到接口或模型，请检查网址与模型名称。", "Endpoint or model not found. Check the address and model.")
        case .rateLimited: values = ("服務限制請求，請稍後再試。", "服务限制请求，请稍后再试。", "The service is rate limited. Try again later.")
        case .server: values = ("服務端發生錯誤，請稍後再試。", "服务端发生错误，请稍后再试。", "The service reported an error. Try again later.")
        case .rejected: values = ("服務拒絕測試請求，請檢查介面與模型設定。", "服务拒绝测试请求，请检查接口与模型设置。", "The service rejected the test. Check the endpoint and model.")
        case .response: values = ("服務未回傳完整文字回覆。", "服务未返回完整文字回复。", "The service did not return a complete text reply.")
        case .redirect: values = ("服務要求轉址；為保護金鑰，測試已停止。", "服务要求重定向；为保护密钥，测试已停止。", "The service requested a redirect; the test stopped to protect the key.")
        case .timeout: values = ("測試逾時，請檢查連線後再試。", "测试超时，请检查连接后再试。", "The test timed out. Check the connection and try again.")
        case .network: values = ("無法完成連線，請檢查網路與服務網址。", "无法完成连接，请检查网络与服务网址。", "Could not complete the connection. Check the network and service address.")
        }
        switch languages.resolved {
        case .traditionalChinese: return values.0
        case .simplifiedChinese: return values.1
        case .english: return values.2
        }
    }
}

@MainActor
private final class MikaModelConnectionViewModel: ObservableObject {
    @Published private(set) var state: ModelConnectionCheck.State = .untested
    private let check: ModelConnectionCheck

    #if DEBUG
    let fixture: ModelConnectionUITestFixture?
    #endif
    init() {
        #if DEBUG
        fixture = ModelConnectionUITestFixture.selected(arguments: ProcessInfo.processInfo.arguments)
        // Only the opt-in simulator fixture gets extra time for native UI gestures.
        check = ModelConnectionCheck(timeoutNanoseconds: fixture == nil ? 20_000_000_000 : 120_000_000_000)
        if let fixture { check.onFixtureAttemptSettled = { fixture.attemptSettled() } }
        #else
        check = ModelConnectionCheck()
        #endif
        check.onChange = { [weak self] state in self?.state = state }
    }
    func start(_ access: ModelAccess) {
        #if DEBUG
        if let fixture {
            check.start(client: DelayedModelConnectionUITestClient(fixture: fixture),
                        configuration: access.configuration, apiKey: access.key)
            return
        }
        #endif
        check.start(client: access.client, configuration: access.configuration, apiKey: access.key)
    }
    func reset() { check.reset() }
    func credentialsUnavailable() { check.credentialsUnavailable() }
}

#if DEBUG
@MainActor
private struct ModelConnectionFixtureControls: View {
    @ObservedObject var fixture: ModelConnectionUITestFixture
    var body: some View {
        VStack(alignment: .leading) {
            Text("Fixture: \(fixture.started),\(fixture.cancelled),\(fixture.released),\(fixture.settled)")
                .accessibilityIdentifier("settings.connectionFixture")
            Button("Release fixture") { fixture.releaseNext() }
                .disabled(fixture.released >= fixture.started)
                .accessibilityIdentifier("settings.connectionFixture.release")
        }
    }
}
#endif
#endif
