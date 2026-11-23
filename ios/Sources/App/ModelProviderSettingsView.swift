#if os(iOS)
import AssistantModels
import SwiftUI

/// One connection test on a Settings › 模型 screen. Phase 1b's test is the
/// existing one: a fixed text message to the typed or chosen model; Android's
/// model listing and tool-call trial come later. The opt-in DEBUG fixture
/// replaces the client for the delayed-result UI tests.
@MainActor
final class ModelConnectionTester: ObservableObject {
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

    func start(client: any ChatModelClient, configuration: ModelConfiguration, apiKey: String) {
        #if DEBUG
        if let fixture {
            check.start(client: DelayedModelConnectionUITestClient(fixture: fixture), configuration: configuration, apiKey: apiKey)
            return
        }
        #endif
        check.start(client: client, configuration: configuration, apiKey: apiKey)
    }

    func reset() { check.reset() }
    func credentialsUnavailable() { check.credentialsUnavailable() }
}

/// The consent screen and what agreeing or declining does.
struct ModelConsentRequest: Identifiable {
    let prompt: ModelConsentPrompt
    let agree: () -> Void
    let decline: () -> Void
    var id: UUID { prompt.id }
}

/// Settings › 模型, as Android's ModelsScreen: the roles (the main model and
/// speech to text in phase 1), the providers with 新增服務商, the add form
/// (open while there is no provider), and the note about keys. Changes apply
/// at once, so the page has only Back.
///
/// On first launch it is Android's ModelSetupScreen in onboarding mode: 設定模型
/// with a lead, the providers before the roles (the main model only), a note
/// that only the main model is needed, and 下一步 once one is chosen.
@MainActor
struct MikaModelSettingsDetailView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var languages: AppLanguageStore
    /// 下一步 of the first-launch flow; nil in Settings.
    var onboardingNext: (() -> Void)? = nil
    @ObservedObject private var voice = VoicePreferences.shared
    @ObservedObject private var signIn = ModelAccountSignIn.shared
    @StateObject private var tester = ModelConnectionTester()
    @State private var signInSheet: ModelAccountSheetTarget?
    @State private var openedProvider: ModelProviderRoute?
    @State private var form = ModelProviderFormInput()
    @State private var formOpen = false
    @State private var showsKey = false
    @State private var confirmsUntested = false
    @State private var consent: ModelConsentRequest?
    @State private var declinedName: String?
    @State private var pageVisible = false
    @State private var deviceRecognition = VoiceSettingsView.deviceRecognitionAvailable()
    @FocusState private var field: Field?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private enum Field: Hashable { case baseURL, name, key, model }
    private enum SaveKind { case tested, untested }
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var providers: [ModelProvider] { session.providerDocument.providers }
    private var showsForm: Bool { formOpen || providers.isEmpty }
    private var onboarding: Bool { onboardingNext != nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Android: on first launch connect a provider, then choose;
                    // in Settings the roles come first.
                    if onboarding {
                        onboardingLead
                        providersPart
                        rolesSection
                        onboardingNote
                    } else {
                        rolesSection
                        providersPart
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: formOpen) { _, open in
                guard open else { return }
                withAnimation { proxy.scrollTo("models.addForm", anchor: .top) }
            }
        }
        .mikaReadableColumn()
        .mikaPageCanvas(palette.page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Android hides it while the keyboard is up, leaving the room to the form.
            if let onboardingNext, field == nil {
                OnboardingNextBar(localizer: localizer, enabled: session.savedSettings != nil, next: onboardingNext)
                    .mikaReadableColumn()
            }
        }
        .navigationTitle(localizer.text(onboarding ? .modelSetupTitle : .settingsHomeModel))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { field = nil }
        .onAppear {
            pageVisible = true; session.reloadProviders(); signIn.reload(session)
            deviceRecognition = VoiceSettingsView.deviceRecognitionAvailable()
        }
        .onChange(of: session.providerDocument) { _, _ in signIn.reload(session) }
        .onDisappear {
            pageVisible = false
            tester.reset(); form.key = ""; showsKey = false
            declinedName = nil; session.clearProviderNotice()
        }
        // Android edit(): any change to the form drops a running test and its result.
        .onChange(of: form) { _, _ in tester.reset(); declinedName = nil }
        .onChange(of: tester.state) { _, state in if state == .passed { testPassed() } }
        .onChange(of: session.isSubmitting) { _, submitting in if submitting { tester.reset() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { tester.reset() } }
        .alert(localizer.text(.modelSaveUntestedTitle), isPresented: $confirmsUntested) {
            // The consent sheet comes after the alert has gone.
            Button(localizer.text(.modelSaveUntestedConfirm)) { DispatchQueue.main.async { requestSave(.untested) } }
            Button(localizer.text(.commonCancel), role: .cancel) {}
        } message: {
            Text(verbatim: localizer.text(.modelSaveUntestedBody))
        }
        .sheet(item: $consent) { request in
            ModelConsentSheet(prompt: request.prompt, localizer: localizer,
                              agree: { consent = nil; request.agree() },
                              decline: { consent = nil; request.decline() })
        }
        .sheet(item: $signInSheet, onDismiss: signInSheetClosed) { target in
            ModelAccountSignInSheet(signIn: signIn, session: session, kind: target.kind, localizer: localizer,
                                    useAPIKey: target.kind == .xai ? { useXAIKey() } : nil,
                                    close: { signInSheet = nil })
        }
        .navigationDestination(item: $openedProvider) { route in
            ModelProviderDetailView(session: session, languages: languages, providerID: route.id)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if field != nil {
                MikaKeyboardDoneBar(title: localizer.text(.keyboardDone),
                                    identifier: "settings.dismissKeyboard") { field = nil }
            }
        }
    }

    // MARK: First launch (Android ModelSetupContent, onboarding)

    private var onboardingLead: some View {
        Text(verbatim: localizer.text(.modelSetupLead))
            .font(.subheadline).foregroundStyle(palette.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4).padding(.bottom, 12)
            .accessibilityIdentifier("setup.lead")
    }

    private var onboardingNote: some View {
        Text(verbatim: localizer.text(.modelSetupOnboardingNote))
            .font(.footnote).foregroundStyle(palette.hint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 28)
            .accessibilityIdentifier("setup.onboardingNote")
    }

    // MARK: Roles

    private var rolesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MikaSettingsGroupLabel(title: localizer.text(.settingsModelRoles))
                .padding(.top, onboarding ? 8 : 0)
            MikaSettingsCard {
                VStack(spacing: 0) {
                    mainRoleRow
                    // Android leaves the other roles and speech to text out of the first launch.
                    if !onboarding {
                        ForEach(ModelSideRole.allCases, id: \.self) { role in
                            Divider().padding(.leading, 70)
                            sideRoleRow(role)
                        }
                        Divider().padding(.leading, 70)
                        NavigationLink {
                            VoiceSettingsView(languages: languages)
                        } label: {
                            let speech = speechLine
                            ModelRoleCard(icon: .mic, label: localizer.text(.voiceChoiceTitle) + " · " + localizer.text(.roleSpeechWhat),
                                          title: speech.title, subtitle: speech.subtitle, subtitleOk: speech.ok,
                                          isModel: false, unset: speech.unset)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.voice.open")
                    }
                }
            }
            if session.mainNeedsConsent, let provider = session.providerDocument.mainProvider {
                consentNeededNotice(provider)
            }
        }
    }

    /// Android ModelsCopy.speechLine (SpeechOptions.summary): the choice, and
    /// under the device's recognizer whether it can be used. iOS records only
    /// with on-device recognition, so a usable one works offline (green).
    private var speechLine: (title: String, subtitle: String?, ok: Bool, unset: Bool) {
        let system = localizer.text(.voiceChoiceSystem)
        switch voice.choice {
        case .automatic, .system:
            if deviceRecognition { return (system, localizer.text(.voiceChoiceSystemOffline), true, false) }
            // Chosen but missing here: say so. The default without one shows 未設定.
            if voice.choice == .system { return (system, localizer.text(.voiceChoiceSystemGone), false, false) }
            return (localizer.text(.settingsModelNotSet), nil, false, true)
        case .off: return (localizer.text(.voiceChoiceOff), nil, false, false)
        case .unavailable: return (localizer.text(.settingsModelNotSet), nil, false, true)
        }
    }

    /// Android RoleCard for the main model; with no provider yet it opens the
    /// add form, as Android's onPick does.
    @ViewBuilder private var mainRoleRow: some View {
        let card = ModelRoleCard(icon: .spark, label: localizer.text(.settingsModelMain) + " · " + localizer.text(.settingsModelMainDetail),
                                 title: mainTitle, subtitle: mainSubtitle,
                                 isModel: session.savedSettings != nil, unset: session.savedSettings == nil)
        if providers.isEmpty {
            Button { formOpen = true } label: { card }
                .buttonStyle(.plain)
                .accessibilityIdentifier("models.role.main")
        } else {
            NavigationLink {
                ModelMainPickerView(session: session, languages: languages, addProvider: { formOpen = true })
            } label: { card }
                .buttonStyle(.plain)
                .disabled(session.isSubmitting)
                .accessibilityIdentifier("models.role.main")
        }
    }

    /// Android RoleCard for vision and light: what the role uses; it opens
    /// the role's picker.
    private func sideRoleRow(_ role: ModelSideRole) -> some View {
        let line = roleLine(role)
        return NavigationLink {
            ModelMainPickerView(session: session, languages: languages, role: role, addProvider: { formOpen = true })
        } label: {
            ModelRoleCard(icon: role == .vision ? .eye : .leaf,
                          label: localizer.text(role == .vision ? .roleVision : .roleLight) + " · "
                              + localizer.text(role == .vision ? .roleVisionWhat : .roleLightWhat),
                          title: line.title, subtitle: line.subtitle, isModel: line.isModel, unset: false)
        }
        .buttonStyle(.plain)
        .disabled(session.isSubmitting)
        .accessibilityIdentifier("models.role." + role.rawValue)
    }

    /// Android ModelsCopy.roleLine for vision and light.
    private func roleLine(_ role: ModelSideRole) -> (title: String, subtitle: String?, isModel: Bool) {
        let document = session.providerDocument
        switch document.choice(for: role) {
        case .sameAsMain:
            return (localizer.text(.modelsSameAsMain), document.roles.main?.model ?? localizer.text(.modelsMainNotPicked), false)
        case .off:
            return (localizer.text(.modelsOff), localizer.text(.modelsOffNote), false)
        case .model(let ref):
            guard let provider = document.provider(id: ref.providerID) else {
                return (localizer.text(.settingsModelNotSet), nil, false)
            }
            return (ref.model, provider.name, true)
        }
    }

    private var mainTitle: String {
        session.savedSettings?.model ?? localizer.text(.settingsModelNotSet)
    }

    private var mainSubtitle: String {
        if session.savedSettings != nil, let provider = session.providerDocument.mainProvider { return provider.name }
        return localizer.text(providers.isEmpty ? .modelsMainAddFirst : .modelsMainPick)
    }

    private func consentNeededNotice(_ provider: ModelProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: localizer.text(.modelsConsentNeeded(provider: provider.name)))
                .font(.footnote).foregroundStyle(palette.warn)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("models.consentNeeded")
            Button(localizer.text(.modelsConsentReview)) {
                consent = ModelConsentRequest(prompt: ModelConsentPrompt(provider: provider, purpose: .send),
                                              agree: { session.agreeToMainProvider() }, decline: {})
            }
            .font(.footnote.weight(.medium))
            .accessibilityIdentifier("models.consentReview")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: Providers

    /// Android ProvidersSection: the providers, what the last change did, the
    /// add form and the note about keys.
    @ViewBuilder private var providersPart: some View {
        providersSection
        noticeSection
        if showsForm {
            addProviderForm.id("models.addForm")
        }
        #if DEBUG
        // Only while this page is on top, so a pushed page's controls are the only ones.
        if pageVisible, let fixture = tester.fixture {
            ModelConnectionFixtureControls(fixture: fixture).padding(.top, 12)
        }
        #endif
        Text(verbatim: localizer.text(.modelsKeyNote))
            .font(.footnote).foregroundStyle(palette.hint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, onboarding ? 0 : 28)
            .accessibilityIdentifier("models.keyNote")
    }

    @ViewBuilder private var providersSection: some View {
        if !providers.isEmpty {
            MikaSettingsGroupLabel(title: localizer.text(.settingsModelProviders))
                .padding(.top, 8)
            MikaSettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { Divider().padding(.leading, 60) }
                        NavigationLink {
                            ModelProviderDetailView(session: session, languages: languages, providerID: provider.id)
                        } label: {
                            ModelProviderRow(name: provider.name, line: providerLine(provider), warning: providerWarning(provider))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("models.provider." + provider.name)
                    }
                    if !showsForm {
                        Divider().padding(.leading, 60)
                        Button { formOpen = true } label: {
                            ModelActionRow(icon: .plus, title: localizer.text(.modelsAddProvider), tint: .accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("models.addProvider")
                    }
                }
            }
        }
    }

    /// Android providerLine: 已連線 (an account: signed in or out on this
    /// device), how many models it listed, and which roles use it; a list
    /// that could not be made says so instead.
    private func providerLine(_ provider: ModelProvider) -> String {
        if signIn.listing[provider.id] == .failed { return localizer.text(.modelsListFailed) }
        let state = provider.kind.account == nil ? localizer.text(.modelsConnected)
            : localizer.text(signIn.status(provider.id)?.signedIn == true ? .signinSignedIn : .signinSignedOut)
        var parts = [state]
        if let models = provider.models, !models.isEmpty { parts.append(localizer.text(.modelsCount(count: models.count))) }
        let used = session.providerDocument.rolesUsing(providerID: provider.id)
        let names = [(used.main, AppText.settingsModelMain), (used.vision, .roleVision), (used.light, .roleLight)]
            .filter(\.0).map { localizer.text($0.1) }
        if !names.isEmpty {
            parts.append(localizer.text(.modelsUsedBy(roles: names.joined(separator: localizer.language == .english ? ", " : "、"))))
        }
        return parts.joined(separator: " · ")
    }

    /// Android Provider.untested: a model in use that no test call ever
    /// confirmed, on a provider with no model list (a provider its key listed
    /// is connected). An account's sign-in already checked it (Android
    /// untested leaves out ChatGPT and xAI).
    private func providerWarning(_ provider: ModelProvider) -> String? {
        guard provider.kind.account == nil, (provider.models ?? []).isEmpty,
              let main = session.providerDocument.roles.main, main.providerID == provider.id,
              !provider.verifiedModels.contains(main.model) else { return nil }
        return localizer.text(.modelsUnverified)
    }

    // MARK: Notices

    @ViewBuilder private var noticeSection: some View {
        // 1a's import: the single v1 setting could not be read, so nothing moved over.
        if providers.isEmpty && session.providerDocument.legacySettings == .unreadable {
            Text(verbatim: localizer.text(.modelsLegacyUnreadable))
                .font(.footnote).foregroundStyle(palette.warn)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 10)
                .accessibilityIdentifier("models.legacyUnreadable")
        }
        if let notice = displayedNotice {
            Text(verbatim: notice)
                .font(.footnote).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 10)
                .accessibilityIdentifier("settings.notice")
        }
        // Android setup-pick-main: a provider saved without a test while no main
        // model is chosen; the picker tests the chosen model first.
        if session.pickMainProvider != nil && session.providerDocument.roles.main == nil {
            NavigationLink {
                ModelMainPickerView(session: session, languages: languages, addProvider: { formOpen = true })
            } label: {
                Text(verbatim: localizer.text(.modelPickMain)).font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 16).padding(.top, 6)
            .accessibilityIdentifier("setup.pickMain")
        }
        if let error = session.settingsError {
            Text(verbatim: localizer.modelSettingsDisplayMessage(error))
                .font(.footnote).foregroundStyle(palette.bad)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 10)
                .accessibilityIdentifier("settings.error")
        }
    }

    private var displayedNotice: String? {
        if let declinedName { return localizer.text(.modelNotSavedDeclined(name: declinedName)) }
        if let notice = session.providerNotice { return localizer.text(notice) }
        return session.settingsNotice.map(localizer.modelSettingsDisplayMessage)
    }

    // MARK: Add provider (Android AddProviderForm)

    private var addProviderForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MikaSettingsGroupLabel(title: localizer.text(.modelsAddProvider))
                Spacer()
                if !providers.isEmpty {
                    Button(localizer.text(.commonCancel)) { closeForm() }
                        .font(.subheadline)
                        .accessibilityIdentifier("setup.cancel")
                }
            }
            .padding(.top, 8)
            ModelAccountSignInGroup(signIn: signIn, document: session.providerDocument, localizer: localizer,
                                    open: { kind in signIn.clearFailure(kind); signInSheet = ModelAccountSheetTarget(kind: kind) },
                                    openProvider: { openedProvider = ModelProviderRoute(id: $0) })
            Text(verbatim: localizer.text(.signinKeyGroup))
                .font(.footnote).foregroundStyle(palette.hint)
                .padding(.bottom, 8)
            ModelChipFlow(spacing: 8) {
                ForEach(ModelProviderPresets.all, id: \.name) { preset in
                    presetChip(title: preset.name, selected: form.preset == preset.name, id: preset.name) {
                        selectPreset(preset.name)
                    }
                }
                presetChip(title: localizer.text(.presetCustom), selected: form.isCustom, id: "custom") {
                    selectPreset(nil)
                }
            }
            .padding(.bottom, 12)
            MikaSettingsCard { formFields }
            formHints
            formButtons
        }
    }

    private func presetChip(title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : palette.ink)
                .padding(.horizontal, 14).frame(minHeight: 34)
                .background(selected ? Color.accentColor : palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("setup.preset." + id)
    }

    /// Android selectPreset: another chip keeps the typed key.
    private func selectPreset(_ name: String?) {
        guard form.preset != name else { return }
        form = ModelProviderFormInput(preset: name, key: form.key)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if form.isCustom {
                fieldLabel(.modelBaseURL)
                TextField("https://…", text: $form.baseURL)
                    .keyboardType(.URL)
                    .focused($field, equals: .baseURL)
                    .accessibilityIdentifier("settings.baseURL")
                fieldLabel(.modelProviderName)
                TextField(form.urlProblem == nil && !form.defaultName.isEmpty ? form.defaultName : localizer.text(.modelProviderNameHint),
                          text: $form.name)
                    .focused($field, equals: .name)
                    .accessibilityIdentifier("setup.name")
            }
            HStack {
                fieldLabel(.modelAPIKey)
                Spacer()
                Button(localizer.text(showsKey ? .commonHide : .commonShow)) { showsKey.toggle() }
                    .font(.footnote)
                    .accessibilityIdentifier("setup.showKey")
            }
            keyField
            fieldLabel(.modelManualName)
            TextField(localizer.text(form.modelExample), text: $form.model)
                .keyboardType(.URL)
                .focused($field, equals: .model)
                .accessibilityIdentifier("settings.model")
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
    }

    @ViewBuilder private var keyField: some View {
        let placeholder = localizer.text(form.keyRequired ? .modelKeyHint : .modelKeyOptional)
        if showsKey {
            TextField(placeholder, text: $form.key)
                .focused($field, equals: .key)
                .privacySensitive()
                .accessibilityIdentifier("settings.apiKey")
        } else {
            SecureField(placeholder, text: $form.key)
                .focused($field, equals: .key)
                .privacySensitive()
                .accessibilityIdentifier("settings.apiKey")
        }
    }

    private func fieldLabel(_ text: AppText) -> some View {
        Text(verbatim: localizer.text(text)).font(.subheadline).foregroundStyle(palette.ink)
    }

    @ViewBuilder private var formHints: some View {
        if let problem = form.urlProblem {
            hint(localizer.text(problem), color: palette.bad, id: "setup.urlProblem")
        }
        if let problem = form.keyProblem {
            hint(localizer.text(problem), color: palette.bad, id: "setup.keyProblem")
        }
        if let preset = form.suggestedPreset {
            hint(localizer.text(.modelPresetMatch(name: preset.name)), color: palette.warn, id: "setup.presetHint")
            Button(localizer.text(.modelUsePreset(name: preset.name))) { selectPreset(preset.name) }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16).padding(.top, 4)
                .accessibilityIdentifier("setup.usePreset")
        }
    }

    private func hint(_ text: String, color: Color, id: String) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 8)
            .accessibilityIdentifier(id)
    }

    private var testing: Bool { tester.state == .testing }

    private var formButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: startTest) {
                Text(verbatim: localizer.text(testing ? .modelTesting : .modelTestSave)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!form.canTest || testing || session.isSubmitting)
            .accessibilityIdentifier("setup.test")
            if case .failed(let failure) = tester.state {
                Text(verbatim: localizer.text(.modelFailed(reason: localizer.text(failure.reason))))
                    .font(.footnote).foregroundStyle(palette.bad)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("setup.testFailed")
            }
            // Android: a real action, a button rather than a line of small print.
            Button { field = nil; confirmsUntested = true } label: {
                Text(verbatim: localizer.text(.modelSaveUntested)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!form.canSaveUntested || testing || session.isSubmitting)
            .accessibilityIdentifier("settings.save")
            Text(verbatim: localizer.text(.modelTestNote))
                .font(.footnote).foregroundStyle(palette.hint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private func startTest() {
        field = nil
        declinedName = nil
        guard let configuration = form.testConfiguration else { return }
        tester.start(client: session.connectionTestClient, configuration: configuration, apiKey: form.trimmedKey)
    }

    private func testPassed() { requestSave(.tested) }

    /// Saves after the consent when this save makes the first main model
    /// (App Review 5.1.2(i)); declining saves nothing.
    private func requestSave(_ kind: SaveKind) {
        declinedName = nil
        let snapshot = form
        guard let draft = snapshot.draft(tested: kind == .tested) else { return }
        guard session.providerDocument.consentRequirement(forAdding: draft) != nil else {
            save(snapshot, kind: kind, consented: false)
            return
        }
        consent = ModelConsentRequest(
            prompt: ModelConsentPrompt(name: draft.name, baseURL: draft.baseURL, purpose: .save),
            agree: { save(snapshot, kind: kind, consented: true) },
            decline: { tester.reset(); declinedName = draft.name })
    }

    private func save(_ snapshot: ModelProviderFormInput, kind: SaveKind, consented: Bool) {
        let saved = session.addProvider(
            name: snapshot.providerName, baseURL: snapshot.address?.absoluteString ?? snapshot.baseURL,
            sessionHeader: snapshot.sessionHeader, keyRequired: snapshot.keyRequired, key: snapshot.trimmedKey,
            model: snapshot.trimmedModel.isEmpty ? nil : snapshot.trimmedModel, tested: kind == .tested, consented: consented)
        tester.reset()
        declinedName = nil
        // Android: a saved provider clears and folds the form, and its models are listed.
        if saved {
            form = ModelProviderFormInput(); formOpen = false; showsKey = false; field = nil
            signIn.ensureListed(session: session)
        }
    }

    private func closeForm() {
        tester.reset()
        form = ModelProviderFormInput()
        formOpen = false; showsKey = false; field = nil; declinedName = nil
    }

    // MARK: Account sign-ins

    /// Android SignInSheetActions.useApiKey: the xAI preset in the key form.
    private func useXAIKey() {
        signInSheet = nil
        form = ModelProviderFormInput(preset: "xAI", key: form.key)
        formOpen = true
    }

    /// A finished sign-in opens its provider. With no main model yet its first
    /// model becomes the main one (Android signInWithChatGpt and
    /// signInWithAccount), after the consent when it is needed.
    private func signInSheetClosed() {
        guard let finished = signIn.finished else { return }
        signIn.finished = nil
        let route = ModelProviderRoute(id: finished.providerID)
        let document = session.providerDocument
        guard document.roles.main == nil, let provider = document.provider(id: finished.providerID),
              let model = document.defaultModel(of: provider.id) else {
            openedProvider = route
            return
        }
        let ref = ModelRef(providerID: provider.id, model: model)
        guard document.consentRequirement(forMain: ref) != nil else {
            session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: false)
            openedProvider = route
            return
        }
        consent = ModelConsentRequest(
            prompt: ModelConsentPrompt(provider: provider, purpose: .save),
            agree: {
                session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: true)
                openedProvider = route
            },
            decline: { openedProvider = route })
    }
}

// MARK: - Role picker (Android RolePickerContent)

/// Picks the main model, or what the vision or light role uses: Android's
/// fixed choices on top, then every connected provider's models (its
/// remembered list), a filter once there are more than eight, and a typed
/// model name under each provider, which one test call checks first.
@MainActor
struct ModelMainPickerView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var languages: AppLanguageStore
    /// nil picks the main model.
    var role: ModelSideRole? = nil
    let addProvider: () -> Void
    @StateObject private var tester = ModelConnectionTester()
    @ObservedObject private var signIn = ModelAccountSignIn.shared
    @State private var manual: [UUID: String] = [:]
    @State private var trial: ModelRef?
    @State private var consent: ModelConsentRequest?
    @State private var filter = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Android FILTER_FROM and PICK_AT_MOST.
    private static let filterFrom = 8
    private static let pickAtMost = 80

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var document: ModelProvidersDocument { session.providerDocument }
    private var query: String { filter.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var title: AppText {
        switch role {
        case nil: return .settingsModelMain
        case .vision: return .roleVision
        case .light: return .roleLight
        }
    }

    private var hint: AppText {
        switch role {
        case nil: return .roleMainHint
        case .vision: return .roleVisionHint
        case .light: return .roleLightHint
        }
    }

    private func shown(_ provider: ModelProvider) -> [String] {
        let models = document.knownModels(of: provider.id)
        return query.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let total = document.providers.reduce(0) { $0 + document.knownModels(of: $1.id).count }
        let groups = document.providers.filter { query.isEmpty || !shown($0).isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: localizer.text(hint))
                    .font(.subheadline).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4).padding(.bottom, 4)
                if let role { fixedChoices(role) }
                if document.providers.isEmpty {
                    footnote(localizer.text(.modelsRoleEmpty), color: palette.hint)
                }
                if total > Self.filterFrom {
                    MikaSettingsGroupLabel(title: localizer.text(.modelsPickFrom)).padding(.top, 8)
                    TextField(localizer.text(.modelsFilterHint), text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("picker.filter")
                        .padding(.bottom, 4)
                }
                ForEach(groups) { provider in
                    providerGroup(provider)
                }
                if !query.isEmpty && groups.isEmpty {
                    footnote(localizer.text(.modelsNoMatch), color: palette.hint)
                        .accessibilityIdentifier("picker.noMatch")
                }
                MikaSettingsCard {
                    Button { dismiss(); addProvider() } label: {
                        ModelActionRow(icon: .plus, title: localizer.text(.modelsAddProvider), tint: .accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("picker.addProvider")
                }
                .padding(.top, 16)
                footnote(localizer.text(.modelsPickNote), color: palette.hint)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .mikaReadableColumn()
        .mikaPageCanvas(palette.page)
        .navigationTitle(localizer.text(title))
        .navigationBarTitleDisplayMode(.inline)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        // Android ensureListed: a provider not listed yet is listed now.
        .onAppear { signIn.ensureListed(session: session) }
        .onChange(of: tester.state) { _, state in if state == .passed { trialPassed() } }
        .onChange(of: manual) { _, _ in tester.reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { tester.reset() } }
        .onDisappear { tester.reset() }
        .sheet(item: $consent) { request in
            ModelConsentSheet(prompt: request.prompt, localizer: localizer,
                              agree: { consent = nil; request.agree() },
                              decline: { consent = nil; request.decline() })
        }
    }

    /// Android fixedChoices: 用主模型 and 不用 for vision, 用主模型 for light.
    private func fixedChoices(_ role: ModelSideRole) -> some View {
        MikaSettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(ModelProvidersDocument.fixedChoices(for: role).enumerated()), id: \.offset) { index, choice in
                    if index > 0 { Divider().padding(.leading, 50) }
                    MikaSettingsRadioRow(title: localizer.text(choice == .off ? .modelsOff : .modelsSameAsMain),
                                         subtitle: localizer.text(choice == .off ? .modelsOffNote
                                             : role == .vision ? .modelsVisionSameNote : .modelsLightSameNote),
                                         selected: document.choice(for: role) == choice) {
                        if session.chooseRoleModel(role, choice, consented: false) { dismiss() }
                    }
                    .disabled(session.isSubmitting)
                    .accessibilityIdentifier(choice == .off ? "picker.off" : "picker.sameAsMain")
                }
            }
        }
        .padding(.top, 8)
    }

    private func isSelected(_ ref: ModelRef) -> Bool {
        guard let role else { return document.roles.main == ref }
        return document.choice(for: role) == .model(ref)
    }

    private func providerGroup(_ provider: ModelProvider) -> some View {
        let models = shown(provider)
        return VStack(alignment: .leading, spacing: 0) {
            MikaSettingsGroupLabel(title: provider.name).padding(.top, 8)
            MikaSettingsCard {
                VStack(spacing: 0) {
                    ForEach(models.prefix(Self.pickAtMost), id: \.self) { model in
                        MikaSettingsRadioRow(title: model,
                                             subtitle: provider.typedModels.contains(model) ? localizer.text(.capTyped) : nil,
                                             selected: isSelected(ModelRef(providerID: provider.id, model: model))) {
                            // Android probeBeforePick: a provider saved without a test is tried first.
                            if provider.savedUntested { tryManual(provider, model: model) }
                            else { choose(ModelRef(providerID: provider.id, model: model), typed: false, verified: false) }
                        }
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("picker.model." + model)
                        Divider().padding(.leading, 50)
                    }
                    manualRow(provider)
                }
            }
            if trial?.providerID == provider.id, case .failed(let failure) = tester.state {
                footnote(localizer.text(.modelFailed(reason: localizer.text(failure.reason))), color: palette.bad)
                    .accessibilityIdentifier("picker.failed." + provider.name)
            } else if trial?.providerID == provider.id, tester.state == .testing {
                footnote(localizer.text(.modelTesting), color: palette.hint)
                    .accessibilityIdentifier("picker.testing." + provider.name)
            } else if signIn.listing[provider.id] == .running {
                footnote(localizer.text(.signinListing), color: palette.hint)
                    .accessibilityIdentifier("picker.listing." + provider.name)
            } else if signIn.listing[provider.id] == .failed {
                footnote(localizer.text(.modelsListFailed), color: palette.bad)
                    .accessibilityIdentifier("picker.listFailed." + provider.name)
            } else if models.count > Self.pickAtMost {
                footnote(localizer.text(.modelsMore(count: models.count - Self.pickAtMost)), color: palette.hint)
                    .accessibilityIdentifier("picker.more." + provider.name)
            }
        }
    }

    /// Android ManualModel: a name from the provider's docs; 使用 makes one
    /// test call first and chooses it only if the call works.
    private func manualRow(_ provider: ModelProvider) -> some View {
        let running = trial?.providerID == provider.id && tester.state == .testing
        let name = (manual[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 10) {
            TextField(localizer.text(.modelManualName), text: Binding(get: { manual[provider.id] ?? "" },
                                                                      set: { manual[provider.id] = $0 }))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .accessibilityIdentifier("picker.manual." + provider.name)
            Button(localizer.text(running ? .modelTesting : .modelsUse)) { tryManual(provider, model: name) }
                .font(.subheadline.weight(.medium))
                .disabled(name.isEmpty || running || session.isSubmitting)
                .accessibilityIdentifier("picker.use." + provider.name)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func footnote(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 8)
    }

    private func tryManual(_ provider: ModelProvider, model: String) {
        guard !model.isEmpty else { return }
        trial = ModelRef(providerID: provider.id, model: model)
        do {
            let key = try session.providerKey(id: provider.id)
            tester.start(client: session.connectionTestClient, configuration: provider.testConfiguration(model: model), apiKey: key)
        } catch { tester.credentialsUnavailable() }
    }

    private func trialPassed() {
        guard let trial else { return }
        choose(trial, typed: true, verified: true)
    }

    /// Another provider than the one agreed to asks first; declining keeps
    /// the main model, or the role as it was.
    private func choose(_ ref: ModelRef, typed: Bool, verified: Bool) {
        if let role { chooseForRole(role, ref, typed: typed, verified: verified); return }
        guard document.roles.main != ref || typed else { dismiss(); return }
        guard let provider = document.provider(id: ref.providerID) else { return }
        guard document.consentRequirement(forMain: ref) != nil else {
            if session.chooseMainModel(providerID: ref.providerID, model: ref.model, typed: typed, verified: verified, consented: false) { dismiss() }
            return
        }
        consent = ModelConsentRequest(
            prompt: ModelConsentPrompt(provider: provider, purpose: .switchMain),
            agree: {
                if session.chooseMainModel(providerID: ref.providerID, model: ref.model, typed: typed, verified: verified, consented: true) {
                    dismiss()
                }
            },
            decline: { tester.reset() })
    }

    private func chooseForRole(_ role: ModelSideRole, _ ref: ModelRef, typed: Bool, verified: Bool) {
        let choice = ModelRoleChoice.model(ref)
        guard document.choice(for: role) != choice || typed else { dismiss(); return }
        guard let provider = document.provider(id: ref.providerID) else { return }
        guard document.consentRequirement(for: choice) != nil else {
            if session.chooseRoleModel(role, choice, typed: typed, verified: verified, consented: false) { dismiss() }
            return
        }
        consent = ModelConsentRequest(
            prompt: ModelConsentPrompt(provider: provider, purpose: .role),
            agree: {
                if session.chooseRoleModel(role, choice, typed: typed, verified: verified, consented: true) { dismiss() }
            },
            decline: { tester.reset() })
    }
}

// MARK: - One provider (Android ProviderDetailContent)

/// A role picked in the "用作" sheet, applied once the sheet has closed.
private struct ModelRoleUseTarget {
    let role: ModelSideRole
    let model: String
}

/// What a closed "用作" sheet asked for (Android UseAsSheet onUse): the main
/// model or a role, applied at once, or the consent to ask first when its
/// provider was never agreed to (App Review 5.1.2(i)).
@MainActor
private enum ModelUseAsFollowUp {
    static func apply(main model: String?, role: ModelRoleUseTarget?, provider: ModelProvider,
                      session: ChatSession) -> ModelConsentRequest? {
        let document = session.providerDocument
        if let role {
            let choice = ModelRoleChoice.model(ModelRef(providerID: provider.id, model: role.model))
            guard document.choice(for: role.role) != choice else { return nil }
            guard document.consentRequirement(for: choice) != nil else {
                _ = session.chooseRoleModel(role.role, choice, consented: false)
                return nil
            }
            return ModelConsentRequest(prompt: ModelConsentPrompt(provider: provider, purpose: .role),
                                       agree: { _ = session.chooseRoleModel(role.role, choice, consented: true) },
                                       decline: {})
        }
        guard let model else { return nil }
        let ref = ModelRef(providerID: provider.id, model: model)
        guard document.roles.main != ref else { return nil }
        guard document.consentRequirement(forMain: ref) != nil else {
            session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: false)
            return nil
        }
        return ModelConsentRequest(
            prompt: ModelConsentPrompt(provider: provider, purpose: .switchMain),
            agree: { session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: true) },
            decline: {})
    }
}

extension ModelProvidersDocument {
    /// Android ModelSetupUi.sortedOptions: the provider's models, the ones in
    /// use first, the rest in their order.
    func modelsInUseFirst(of providerID: UUID) -> [String] {
        let known = knownModels(of: providerID)
        let used = known.filter { !roleNames(of: ModelRef(providerID: providerID, model: $0), nil).isEmpty }
        return used + known.filter { !used.contains($0) }
    }

    /// Android rolesOf: the roles this model is actually used for (with the
    /// ones that follow 用主模型), in the order 主模型、看圖模型、輕量模型.
    func roleNames(of ref: ModelRef, _ localizer: AppLocalizer?) -> [String] {
        var names: [String] = []
        if roles.main == ref { names.append(localizer?.text(.settingsModelMain) ?? "main") }
        if resolvedModel(for: .vision) == ref { names.append(localizer?.text(.roleVision) ?? "vision") }
        if resolvedModel(for: .light) == ref { names.append(localizer?.text(.roleLight) ?? "light") }
        return names
    }
}

/// Android AllModelsContent: 「<服務商> · 全部模型」, the filter fixed under the
/// bar and only the list scrolling. The list is lazy, so hundreds of models
/// stay quick to show and to read. A model opens the same 用作 sheet; the
/// refresh button lists the provider again.
@MainActor
struct ModelAllModelsView: View {
    /// Android MODEL_PREVIEW: the models the provider page shows before 查看全部.
    static let preview = 3

    @ObservedObject var session: ChatSession
    @ObservedObject var languages: AppLanguageStore
    let providerID: UUID
    @ObservedObject private var signIn = ModelAccountSignIn.shared
    @State private var filter = ""
    @State private var using: ModelUseTarget?
    @State private var mainAfterSheet: String?
    @State private var roleAfterSheet: ModelRoleUseTarget?
    @State private var consent: ModelConsentRequest?
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var document: ModelProvidersDocument { session.providerDocument }
    private var provider: ModelProvider? { document.provider(id: providerID) }

    private var shown: [String] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let all = document.modelsInUseFirst(of: providerID)
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(localizer.text(.modelsFilterHint), text: $filter)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
                .accessibilityIdentifier("allModels.filter")
            ScrollView {
                let models = shown
                if models.isEmpty {
                    Text(verbatim: localizer.text(.modelsNoMatch)).font(.footnote).foregroundStyle(palette.hint)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(models.enumerated()), id: \.element) { index, model in
                            if index > 0 { Divider().padding(.leading, 16) }
                            Button { using = ModelUseTarget(model: model) } label: {
                                ModelListRow(model: model, typed: provider?.typedModels.contains(model) == true,
                                             roles: document.roleNames(of: ModelRef(providerID: providerID, model: model), localizer),
                                             localizer: localizer)
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isSubmitting)
                            .accessibilityIdentifier("provider.model." + model)
                        }
                    }
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
        .mikaReadableColumn()
        .mikaPageCanvas(palette.page)
        .navigationTitle(localizer.text(.modelsAllTitle(name: provider?.name ?? "")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { signIn.refreshModels(providerID: providerID, session: session) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(signIn.listing[providerID] == .running || session.isSubmitting)
                .accessibilityLabel(localizer.text(.signinRefresh))
                .accessibilityIdentifier("allModels.refresh")
            }
        }
        .sheet(item: $using, onDismiss: useAsDismissed) { target in
            ModelUseAsSheet(session: session, localizer: localizer, providerID: providerID, model: target.model,
                            useAsMain: { mainAfterSheet = target.model; using = nil },
                            useAsRole: { roleAfterSheet = ModelRoleUseTarget(role: $0, model: target.model); using = nil },
                            close: { using = nil })
        }
        .sheet(item: $consent) { request in
            ModelConsentSheet(prompt: request.prompt, localizer: localizer,
                              agree: { consent = nil; request.agree() },
                              decline: { consent = nil; request.decline() })
        }
    }

    private func useAsDismissed() {
        let main = mainAfterSheet, role = roleAfterSheet
        mainAfterSheet = nil; roleAfterSheet = nil
        guard let provider else { return }
        consent = ModelUseAsFollowUp.apply(main: main, role: role, provider: provider, session: session)
    }
}

/// The model a "用作" sheet is open for.
private struct ModelUseTarget: Identifiable {
    let model: String
    var id: String { model }
}

@MainActor
struct ModelProviderDetailView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var languages: AppLanguageStore
    let providerID: UUID
    @StateObject private var tester = ModelConnectionTester()
    @State private var changingKey = false
    @State private var newKey = ""
    @State private var confirmsDelete = false
    @State private var using: ModelUseTarget?
    @State private var mainAfterSheet: String?
    @State private var roleAfterSheet: ModelRoleUseTarget?
    @State private var consent: ModelConsentRequest?
    @State private var retestTarget: String?
    @State private var retested: String?
    @ObservedObject private var signIn = ModelAccountSignIn.shared
    @State private var signInSheet: ModelAccountSheetTarget?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var document: ModelProvidersDocument { session.providerDocument }
    private var provider: ModelProvider? { document.provider(id: providerID) }

    var body: some View {
        ScrollView {
            if let provider {
                content(provider)
            }
        }
        .mikaReadableColumn()
        .mikaPageCanvas(palette.page)
        // Android ensureListed, as on the pickers.
        .onAppear { signIn.ensureListed(session: session) }
        .navigationTitle(provider?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: tester.state) { _, state in if state == .passed { retestPassed() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { tester.reset() } }
        .onAppear { signIn.reload(session) }
        .onDisappear { tester.reset() }
        .sheet(item: $signInSheet, onDismiss: {
            if signIn.finished?.providerID == providerID { signIn.finished = nil }
        }) { target in
            ModelAccountSignInSheet(signIn: signIn, session: session, kind: target.kind, localizer: localizer,
                                    useAPIKey: nil, close: { signInSheet = nil })
        }
        .alert(localizer.text(.modelsChangeKey), isPresented: $changingKey) {
            SecureField(localizer.text(.modelsNewKeyHint), text: $newKey)
                .accessibilityIdentifier("provider.newKey")
            Button(localizer.text(.commonSave)) {
                let key = newKey; newKey = ""
                if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    session.changeProviderKey(providerID: providerID, key: key)
                }
            }
            Button(localizer.text(.commonCancel), role: .cancel) { newKey = "" }
        }
        .alert(localizer.text(.modelsDeleteTitle(name: provider?.name ?? "")), isPresented: $confirmsDelete) {
            Button(localizer.text(.commonDelete), role: .destructive) {
                if session.deleteProvider(id: providerID) { dismiss() }
            }
            Button(localizer.text(.commonCancel), role: .cancel) {}
        } message: {
            Text(verbatim: deleteMessage)
        }
        .sheet(item: $using, onDismiss: useAsDismissed) { target in
            ModelUseAsSheet(session: session, localizer: localizer, providerID: providerID, model: target.model,
                            useAsMain: { mainAfterSheet = target.model; using = nil },
                            useAsRole: { roleAfterSheet = ModelRoleUseTarget(role: $0, model: target.model); using = nil },
                            close: { using = nil })
        }
        .sheet(item: $consent) { request in
            ModelConsentSheet(prompt: request.prompt, localizer: localizer,
                              agree: { consent = nil; request.agree() },
                              decline: { consent = nil; request.decline() })
        }
    }

    private func content(_ provider: ModelProvider) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kind = provider.kind.account {
                ModelAccountConnectionSection(signIn: signIn, session: session, provider: provider, kind: kind, localizer: localizer,
                                              signInAgain: { signIn.clearFailure(kind); signInSheet = ModelAccountSheetTarget(kind: kind) },
                                              useAsMain: useAccountModelAsMain)
            } else {
                MikaSettingsGroupLabel(title: localizer.text(.modelsConnection))
                MikaSettingsCard { connectionRows(provider) }
            }
            MikaSettingsGroupLabel(title: localizer.text(.modelsModels)).padding(.top, 8)
            let models = document.modelsInUseFirst(of: provider.id)
            if !models.isEmpty {
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        // Android ProviderDetailContent: the first MODEL_PREVIEW models
                        // (in use first) and 查看全部, so the page stays short.
                        ForEach(Array(models.prefix(ModelAllModelsView.preview).enumerated()), id: \.element) { index, model in
                            if index > 0 { Divider().padding(.leading, 16) }
                            Button { using = ModelUseTarget(model: model) } label: {
                                ModelListRow(model: model, typed: provider.typedModels.contains(model),
                                             roles: document.roleNames(of: ModelRef(providerID: provider.id, model: model), localizer),
                                             localizer: localizer)
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isSubmitting)
                            .accessibilityIdentifier("provider.model." + model)
                        }
                        if models.count > ModelAllModelsView.preview {
                            Divider().padding(.leading, 16)
                            NavigationLink {
                                ModelAllModelsView(session: session, languages: languages, providerID: provider.id)
                            } label: {
                                HStack {
                                    Text(verbatim: localizer.text(.modelsViewAll(count: models.count))).foregroundStyle(Color.accentColor)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.hint).accessibilityHidden(true)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("provider.allModels")
                        }
                    }
                }
                note(localizer.text(.modelsModelsNote), color: palette.hint)
            }
            if provider.kind.account != nil {
                // The plan's own list, listed again with the account's token.
                Button { signIn.refreshModels(providerID: provider.id, session: session) } label: {
                    Text(verbatim: localizer.text(.signinRefresh)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(signIn.listing[provider.id] == .running || signIn.status(provider.id)?.signedIn != true || session.isSubmitting)
                .padding(.top, 12)
                .accessibilityIdentifier("provider.account.refresh")
            } else {
                if provider.savedUntested {
                    note(localizer.text(.modelsUntestedNote), color: palette.warn).accessibilityIdentifier("provider.untested")
                }
                retestSection(provider, models: models)
            }
            MikaSettingsCard {
                Button { confirmsDelete = true } label: {
                    ModelActionRow(icon: .trash, title: localizer.text(.modelsDelete), tint: palette.bad)
                }
                .buttonStyle(.plain)
                .disabled(session.isSubmitting)
                .accessibilityIdentifier("provider.delete")
            }
            .padding(.top, 16)
            if let error = session.settingsError {
                note(localizer.modelSettingsDisplayMessage(error), color: palette.bad).accessibilityIdentifier("provider.error")
            }
            #if DEBUG
            if let fixture = tester.fixture {
                ModelConnectionFixtureControls(fixture: fixture).padding(.top, 12)
            }
            #endif
        }
        .padding(.horizontal, 16).padding(.bottom, 24)
    }

    private func connectionRows(_ provider: ModelProvider) -> some View {
        VStack(spacing: 0) {
            ModelValueRow(title: localizer.text(.modelsStatus), value: localizer.text(.modelsConnected), tone: .ok)
                .accessibilityIdentifier("provider.status")
            Divider().padding(.leading, 16)
            ModelValueRow(title: localizer.text(.modelKind), value: localizer.text(.modelsOpenAICompat), tone: .plain)
            Divider().padding(.leading, 16)
            // The address never changes: a key is only ever sent where it was typed for.
            ModelValueRow(title: localizer.text(.modelsURL), value: Self.shortURL(provider.baseURL), tone: .plain)
                .accessibilityIdentifier("provider.url")
            Divider().padding(.leading, 16)
            HStack(spacing: 12) {
                Text(verbatim: localizer.text(.modelAPIKey)).font(.body).foregroundStyle(palette.ink)
                Spacer(minLength: 4)
                Text(verbatim: localizer.text(hasKey(provider) ? .modelsKeySaved : .modelsKeyNone))
                    .font(.subheadline).foregroundStyle(palette.hint)
                    .accessibilityIdentifier("provider.keyStatus")
                Button(localizer.text(.modelsChange)) { newKey = ""; changingKey = true }
                    .font(.subheadline.weight(.medium))
                    .disabled(session.isSubmitting)
                    .accessibilityIdentifier("provider.changeKey")
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
        }
    }

    /// The account's item is there; a restored device keeps the provider but
    /// not its key, and then says 沒有填.
    private func hasKey(_ provider: ModelProvider) -> Bool {
        guard provider.credentialAccount != nil else { return false }
        return session.keyedProviders.map { $0.contains(provider.id) } ?? true
    }

    @ViewBuilder private func retestSection(_ provider: ModelProvider, models: [String]) -> some View {
        if let model = retestModel(provider, models: models) {
            Button { startRetest(provider, model: model) } label: {
                Text(verbatim: localizer.text(tester.state == .testing ? .modelTesting : .modelsRetest)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(tester.state == .testing || session.isSubmitting)
            .padding(.top, 12)
            .accessibilityIdentifier("provider.retest")
            if case .failed(let failure) = tester.state {
                note(localizer.text(.modelFailed(reason: localizer.text(failure.reason))), color: palette.bad)
                    .accessibilityIdentifier("provider.retestStatus")
            }
        }
        // Stays after the pass, when the button itself is no longer needed.
        if let retested {
            note(localizer.text(.modelsRetestPassed(model: retested)), color: palette.ok)
                .accessibilityIdentifier("provider.retestStatus")
        }
    }

    /// Android retest: the model in use when it was never confirmed, or the
    /// first model of a provider saved without a test.
    private func retestModel(_ provider: ModelProvider, models: [String]) -> String? {
        if let main = document.roles.main, main.providerID == provider.id, !provider.verifiedModels.contains(main.model) {
            return main.model
        }
        return provider.savedUntested ? models.first : nil
    }

    private func startRetest(_ provider: ModelProvider, model: String) {
        retested = nil
        retestTarget = model
        do {
            let key = try session.providerKey(id: provider.id)
            tester.start(client: session.connectionTestClient, configuration: provider.testConfiguration(model: model), apiKey: key)
        } catch { tester.credentialsUnavailable() }
    }

    private func retestPassed() {
        guard let model = retestTarget else { return }
        session.markModelVerified(providerID: providerID, model: model)
        retested = model
        tester.reset()
    }

    /// The "用作" sheet closed; 主模型 there asks for the consent now when
    /// it is another provider than the one agreed to.
    private func useAsDismissed() {
        let main = mainAfterSheet, role = roleAfterSheet
        mainAfterSheet = nil; roleAfterSheet = nil
        guard let provider else { return }
        consent = ModelUseAsFollowUp.apply(main: main, role: role, provider: provider, session: session)
    }

    /// Android useAsMain: an account's default model becomes the main one,
    /// after the consent when its provider is not the one agreed to.
    private func useAccountModelAsMain(_ model: String) {
        guard let provider else { return }
        let ref = ModelRef(providerID: provider.id, model: model)
        guard document.roles.main != ref else { return }
        guard document.consentRequirement(forMain: ref) != nil else {
            session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: false)
            return
        }
        consent = ModelConsentRequest(
            prompt: ModelConsentPrompt(provider: provider, purpose: .switchMain),
            agree: { session.chooseMainModel(providerID: provider.id, model: model, typed: false, verified: false, consented: true) },
            decline: {})
    }

    private var deleteMessage: String {
        let usedByMain = document.roles.main?.providerID == providerID
        let roles = usedByMain ? localizer.text(.modelsDeleteUsed(roles: localizer.text(.settingsModelMain)))
                               : localizer.text(.modelsDeleteUnused)
        return localizer.text(.modelsDeleteBody) + (localizer.language == .english ? " " : "") + roles
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 8)
    }

    /// Android shortUrl: the address without its scheme.
    static func shortURL(_ url: URL) -> String {
        let raw = url.absoluteString
        return raw.hasPrefix("https://") ? String(raw.dropFirst("https://".count)) : raw
    }
}

/// Android UseAsSheet: 「<服務商> · 用作」主模型 / 看圖模型 / 輕量模型, applied at
/// once, then the 能看圖 switch with Android's note on where its answer comes from.
@MainActor
private struct ModelUseAsSheet: View {
    @ObservedObject var session: ChatSession
    let localizer: AppLocalizer
    let providerID: UUID
    let model: String
    let useAsMain: () -> Void
    let useAsRole: (ModelSideRole) -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var document: ModelProvidersDocument { session.providerDocument }
    private var provider: ModelProvider? { document.provider(id: providerID) }
    private var ref: ModelRef { ModelRef(providerID: providerID, model: model) }
    private var isMain: Bool { document.roles.main == ref }
    /// The vision role uses this model (用主模型 for the main one, or chosen): it sees images.
    private var usedForVision: Bool { document.resolvedModel(for: .vision) == ref }
    /// Android ModelOptions.seesImages: what the chat goes by.
    private var sees: Bool { document.seesImages(ref) == true }
    /// Android ModelsCopy.seesNote: the vision role, the person's own answer, the list, or unconfirmed.
    private var seesNote: AppText {
        if usedForVision { return .settingsSeesImagesVision }
        if provider?.visionOverrides[model] != nil { return .settingsSeesImagesUser }
        return document.seesImages(ref) == nil ? .settingsSeesImagesUnconfirmed : .settingsSeesImagesListed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model)
                .font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(palette.ink)
                .lineLimit(2)
                .padding(.horizontal, 16).padding(.top, 20)
            Text(verbatim: localizer.text(.modelsUseAs(name: provider?.name ?? "")))
                .font(.caption).foregroundStyle(palette.hint)
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
            MikaSettingsRadioRow(title: localizer.text(.settingsModelMain),
                                 subtitle: localizer.text(isMain ? .modelsInUse : .settingsModelMainDetail),
                                 selected: isMain) { if !isMain { useAsMain() } }
                .disabled(session.isSubmitting)
                .accessibilityIdentifier("useAs.main")
            ForEach(ModelSideRole.allCases, id: \.self) { role in
                let picked = document.resolvedModel(for: role) == ref
                Divider().padding(.leading, 16)
                MikaSettingsRadioRow(title: localizer.text(role == .vision ? .roleVision : .roleLight),
                                     subtitle: localizer.text(picked ? .modelsInUse : role == .vision ? .roleVisionWhat : .roleLightWhat),
                                     selected: picked) { if !picked { useAsRole(role) } }
                    .disabled(session.isSubmitting)
                    .accessibilityIdentifier("useAs." + role.rawValue)
            }
            Divider().padding(.leading, 16)
            Toggle(isOn: Binding(get: { sees },
                                 set: { session.setModelVision(providerID: providerID, model: model, sees: $0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localizer.text(.settingsSeesImages))
                    Text(verbatim: localizer.text(seesNote))
                        .font(.footnote).foregroundStyle(palette.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The vision role decides for the model it uses; change the role to change it.
            .disabled(session.isSubmitting || usedForVision)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityIdentifier("useAs.seesImages")
            Divider().padding(.leading, 16)
            Button(action: close) {
                Text(verbatim: localizer.text(.commonCancel)).foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("useAs.cancel")
            Spacer(minLength: 0)
        }
        .background(palette.surface)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - The AI-sharing consent (App Review 5.1.2(i))

/// Says which service and host receive what (the list the App Store
/// compliance check asked for), that declining sends nothing, and links the
/// privacy policy. Only the two buttons close it.
@MainActor
struct ModelConsentSheet: View {
    let prompt: ModelConsentPrompt
    let localizer: AppLocalizer
    let agree: () -> Void
    let decline: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }

    private var declineText: AppText {
        switch prompt.purpose {
        case .save: return .consentDeclineSave
        case .switchMain: return .consentDeclineSwitch
        case .send: return .consentDeclineSend
        case .role: return .consentDeclineRole
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MikaSettingsIconTile(icon: .shield)
                Text(verbatim: localizer.text(.consentTitle(provider: prompt.providerName)))
                    .font(.title3.weight(.semibold)).foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("consent.title")
                paragraph(localizer.text(.consentLead(provider: prompt.providerName, host: prompt.host)), id: "consent.body")
                // The one list of what can be sent (ModelSharedContent), as the privacy policy has it.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ModelSharedContent.allCases, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "•").foregroundStyle(palette.hint).accessibilityHidden(true)
                            Text(verbatim: localizer.text(item.text))
                                .font(.callout).foregroundStyle(palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("consent.item." + item.rawValue)
                    }
                }
                // Web tasks from chat, after the ten items; the privacy policy has the same section.
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: localizer.text(.chatWebConsentTitle))
                        .font(.callout.weight(.semibold)).foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: localizer.text(.chatWebConsentBody))
                        .font(.callout).foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("consent.webTasks")
                paragraph(localizer.text(.consentThirdParty(provider: prompt.providerName)), id: "consent.thirdParty")
                paragraph(localizer.text(declineText), id: "consent.decline.note")
                if prompt.purpose != .send {
                    paragraph(localizer.text(.consentAgain), id: "consent.again")
                }
                Link(destination: MikaPrivacyPolicy.url) {
                    Text(verbatim: localizer.text(.consentPrivacyPolicy)).font(.callout.weight(.medium))
                }
                .accessibilityIdentifier("consent.privacyPolicy")
            }
            .padding(20)
        }
        // The answer stays in reach on every screen size.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: agree) {
                    Text(verbatim: localizer.text(.consentAgree)).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("consent.agree")
                Button(action: decline) {
                    Text(verbatim: localizer.text(.consentDecline)).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("consent.decline")
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            .background(palette.surface)
        }
        .background(palette.surface)
        .interactiveDismissDisabled()
    }

    private func paragraph(_ text: String, id: String) -> some View {
        Text(verbatim: text)
            .font(.body).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }
}

// MARK: - Rows

/// Android RoleCard: a 40 point tile, 「名字 · 做什麼」, what is chosen
/// (model names in a monospaced face) and who provides it.
private struct ModelRoleCard: View {
    let icon: MikaSettingsIcon
    let label: String
    let title: String
    let subtitle: String?
    /// Android RoleLine.subtitleOk: the subtitle in the ok colour.
    var subtitleOk = false
    let isModel: Bool
    let unset: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 14) {
            MikaSettingsIconShape(icon: icon)
                .stroke(colors.ink, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 21, height: 21)
                .frame(width: 40, height: 40)
                .background(colors.tile, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: label).font(.system(size: 12.5)).foregroundStyle(colors.hint)
                Text(verbatim: title)
                    .font(.system(size: 16, weight: .semibold, design: isModel ? .monospaced : .default))
                    .foregroundStyle(unset ? colors.hint : colors.ink)
                    .lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(subtitleOk ? colors.ok : colors.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.hint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// Android ProviderRow: the name's first letter on a tile, the name, what it
/// does and, in the warning colour, what to look at.
private struct ModelProviderRow: View {
    let name: String
    let line: String
    let warning: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 14) {
            Text(verbatim: String(name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold)).foregroundStyle(colors.ink)
                .frame(width: 30, height: 30)
                .background(colors.tile, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.body).foregroundStyle(colors.ink).lineLimit(1)
                Text(verbatim: line).font(.caption).foregroundStyle(colors.hint)
                if let warning {
                    Text(verbatim: warning).font(.caption).foregroundStyle(colors.warn)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.hint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Android ListRow with a tinted tile: 新增服務商 and 刪除這個服務商.
private struct ModelActionRow: View {
    let icon: MikaSettingsIcon
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            MikaSettingsIconTile(icon: icon, tint: tint)
            Text(verbatim: title).font(.body).foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// A title and a read-only value.
private struct ModelValueRow: View {
    let title: String
    let value: String
    let tone: MikaSettingsTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 12) {
            Text(verbatim: title).font(.body).foregroundStyle(colors.ink)
            Spacer(minLength: 4)
            Text(verbatim: value).font(.subheadline).foregroundStyle(colors.color(for: tone))
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Android ModelRow: the model name (monospaced), 手填 and the role in use.
private struct ModelListRow: View {
    let model: String
    let typed: Bool
    /// Android ModelRow: the roles this model is used for.
    let roles: [String]
    let localizer: AppLocalizer
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: model)
                    .font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if typed { MikaSettingsPill(text: localizer.text(.capTyped), tone: .plain) }
                    ForEach(roles, id: \.self) { MikaSettingsPill(text: $0, tone: .ok) }
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.hint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Android FlowRow for the preset chips: as many per line as fit. Not lazy,
/// so every chip is in the accessibility tree.
private struct ModelChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
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
