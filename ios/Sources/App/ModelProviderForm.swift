import AssistantModels
import Foundation

/// Android AddForm for iOS phase 1: the six OpenAI-compatible presets and
/// 自訂 (OpenAI-compatible, HTTPS only). Phase 1 lists no models, so the typed
/// model is what "測試並儲存" tries and what is saved.
struct ModelProviderFormInput: Equatable {
    /// A preset's name; nil is 自訂.
    var preset: String? = ModelProviderPresets.all.first?.name
    /// 自訂 only.
    var baseURL = ""
    /// 自訂 only; blank uses the host.
    var name = ""
    var key = ""
    var model = ""

    /// Android setName: at most 32 characters.
    static let maximumNameLength = 32

    var isCustom: Bool { preset == nil }

    var presetEntry: ModelProviderPreset? {
        preset.flatMap { name in ModelProviderPresets.all.first { $0.name == name } }
    }

    /// The address to save: the preset's, or the typed one when it can hold a key.
    var address: URL? {
        if let presetEntry { return presetEntry.baseURL }
        return try? ModelSettingsRepository.validatedAddress(baseURL)
    }

    /// Shown under a typed address that cannot be saved.
    var urlProblem: AppText? {
        guard isCustom else { return nil }
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        guard raw.lowercased().hasPrefix("https://") else { return .modelURLHTTPS }
        return address == nil ? .modelSettingsInvalidURL : nil
    }

    /// Android AddForm.keyRequired: only 自訂 may go without a key.
    var keyRequired: Bool { !isCustom }

    var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var keyProblem: AppText? {
        let blocked = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        return trimmedKey.unicodeScalars.contains(where: blocked.contains) ? .modelSettingsInvalidKey : nil
    }

    var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var modelProblem: Bool {
        trimmedModel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// Android defaultName: the preset at this address, otherwise the host.
    var defaultName: String { address.map(ModelProviderPresets.displayName(for:)) ?? "" }

    /// Android providerName: the preset's name, or the typed name, or the host.
    var providerName: String {
        guard isCustom else { return preset ?? "" }
        let typed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        return typed.isEmpty ? defaultName : typed
    }

    /// Android AddForm.sessionHeader: the preset's, or that of a preset at this address.
    var sessionHeader: String? {
        presetEntry?.sessionHeader ?? address.flatMap(ModelProviderPresets.preset(at:))?.sessionHeader
    }

    /// Android suggestedPreset: 自訂 with an address on a preset's host.
    var suggestedPreset: ModelProviderPreset? {
        isCustom ? address.flatMap(ModelProviderPresets.preset(forHost:)) : nil
    }

    /// The model name example: xAI's own, otherwise Android's OpenAI-compatible one.
    var modelExample: AppText {
        (presetEntry ?? suggestedPreset)?.name == "xAI" ? .modelExampleGrok : .modelExampleCompat
    }

    /// Android canSaveUntested: a valid address, a key where one is needed.
    var canSaveUntested: Bool {
        address != nil && keyProblem == nil && (!keyRequired || !trimmedKey.isEmpty) && !modelProblem
            && !providerName.isEmpty
    }

    /// Android canTest: what saving needs, plus the model to try.
    var canTest: Bool { canSaveUntested && !trimmedModel.isEmpty }

    func draft(tested: Bool) -> ModelProviderDraft? {
        guard let address else { return nil }
        return ModelProviderDraft(name: providerName, baseURL: address, sessionHeader: sessionHeader,
                                  keyRequired: keyRequired, hasNewKey: !trimmedKey.isEmpty,
                                  model: trimmedModel.isEmpty ? nil : trimmedModel, tested: tested)
    }

    /// The connection test's request: the typed address, model and key, and a
    /// fresh session header value (it belongs to no conversation).
    var testConfiguration: ModelConfiguration? {
        guard canTest, let address else { return nil }
        return ModelConfiguration(baseURL: address, model: trimmedModel, requiresKey: keyRequired || !trimmedKey.isEmpty,
                                  sessionHeader: sessionHeader.flatMap(ModelSessionHeader.fresh(name:)))
    }
}

extension ModelConnectionCheck.Failure {
    /// Why a test call failed, said as Android's model_error and model_reason strings.
    var reason: AppText {
        switch self {
        case .credentials: return .modelReasonCredentials
        case .configuration: return .modelReasonConfiguration
        case .authentication: return .modelErrorAuth
        case .notFound: return .modelReasonNotFound
        case .rateLimited: return .modelErrorRateLimited
        case .server: return .modelReasonServer
        case .rejected: return .modelReasonRefused
        case .response: return .modelReasonUnreadable
        case .redirect: return .modelReasonRedirect
        case .timeout: return .modelReasonTimeout
        case .network: return .modelErrorNetwork
        }
    }
}

extension ModelProvider {
    /// A test call's request to one of this provider's models: its address,
    /// its key rule and a fresh session header value.
    func testConfiguration(model: String) -> ModelConfiguration {
        ModelConfiguration(baseURL: baseURL, model: model, requiresKey: credentialAccount != nil,
                           sessionHeader: sessionHeader.flatMap(ModelSessionHeader.fresh(name:)))
    }
}
