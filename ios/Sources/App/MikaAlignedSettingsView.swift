#if os(iOS)
import SwiftUI

/// Settings root and its model destination share the existing stores. The
/// model form remains iOS's single configured service, with a real back path.
@MainActor
struct MikaAlignedSettingsView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var preferences: SelfConfigurationStore
    @ObservedObject var notifications: TaskNotificationStore
    @ObservedObject var languages: AppLanguageStore
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var configuredModelName: String {
        session.hasStoredKey ? (session.savedSettings?.model ?? localizer.text(.settingsModelNotSet))
                             : localizer.text(.settingsModelNotSet)
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
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.settingsHomeTitle))
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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var editingField: Field?

    private enum Field: Hashable { case baseURL, model, key }
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var configuredModelName: String {
        session.hasStoredKey ? (session.savedSettings?.model ?? localizer.text(.settingsModelNotSet))
                             : localizer.text(.settingsModelNotSet)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaModelStatusCard(session: session, localizer: localizer, palette: palette)
                    .padding(.top, 12)
                MikaSettingsGroupLabel(title: localizer.text(.settingsModelRoles))
                MikaSettingsCard {
                    MikaSettingsRow(icon: .spark, title: localizer.text(.settingsModelMain),
                                    subtitle: localizer.text(.settingsModelMainDetail),
                                    value: configuredModelName, accessory: .none)
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
        .onDisappear { session.keyDraft = "" }
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
                            session.saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("settings.save")
                        Button(localizer.text(.settingsModelRemove), role: .destructive) {
                            editingField = nil
                            session.removeSettings()
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("settings.remove")
                    }
                    if let error = session.settingsError {
                        Text(verbatim: localizer.modelSettingsDisplayMessage(error))
                            .foregroundStyle(.red).accessibilityIdentifier("settings.error")
                    }
                    if let notice = session.settingsNotice {
                        Text(verbatim: localizer.modelSettingsDisplayMessage(notice))
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
}
#endif
