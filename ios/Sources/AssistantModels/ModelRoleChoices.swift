import Foundation

/// The roles besides the main one (Android ModelRole.Vision and Light).
public enum ModelSideRole: String, CaseIterable, Sendable {
    /// Looks at the pictures attached in chat.
    case vision
    /// Small jobs: judging whether a task was done, organizing memory.
    case light
}

extension ModelProvidersDocument {
    /// Whether the user agreed to send their content to this provider: as the
    /// main model's provider, or when a vision or light model of it was chosen.
    public func hasConsent(forProvider id: UUID) -> Bool {
        consent?.providerID == id || roleConsents.contains { $0.providerID == id }
    }

    public func choice(for role: ModelSideRole) -> ModelRoleChoice {
        switch role {
        case .vision: return roles.vision
        case .light: return roles.light
        }
    }

    /// Android fixedChoices: vision offers 用主模型 and 不用, light only 用主模型.
    public static func fixedChoices(for role: ModelSideRole) -> [ModelRoleChoice] {
        switch role {
        case .vision: return [.sameAsMain, .off]
        case .light: return [.sameAsMain]
        }
    }

    /// The consent choosing `choice` needs first (App Review 5.1.2(i)); nil
    /// when it sends nothing to a provider the user has not agreed to.
    public func consentRequirement(for choice: ModelRoleChoice) -> ModelConsentRequirement? {
        guard case .model(let ref) = choice, !hasConsent(forProvider: ref.providerID) else { return nil }
        return consent == nil ? .firstTime : .differentProvider
    }

    /// Android ProviderStore.setRole for vision and light. A model of a
    /// provider not agreed to yet needs `consentedAt`, which is recorded for
    /// that provider; light can never be off. A typed name is remembered as
    /// typed (Android markTyped), and as verified when a test call answered.
    public mutating func chooseRole(_ role: ModelSideRole, _ choice: ModelRoleChoice, typed: Bool = false,
                                    verified: Bool = false, consentedAt: Date?) throws {
        if role == .light, choice == .off { throw ModelProvidersError.invalidDocument }
        if case .model(let ref) = choice {
            guard let index = providers.firstIndex(where: { $0.id == ref.providerID }) else {
                throw ModelProvidersError.unknownProvider
            }
            let provider = providers[index]
            guard ModelProviderAddress.isModelName(ref.model) else { throw ModelProvidersError.invalidDocument }
            if typed, provider.models?.contains(where: { $0.id == ref.model }) != true {
                guard providers[index].typedModels.count < Self.maximumNamedModels else { throw ModelProvidersError.invalidDocument }
                providers[index].typedModels.insert(ref.model)
            }
            if verified { providers[index].verifiedModels.insert(ref.model) }
            if !hasConsent(forProvider: ref.providerID) {
                guard let consentedAt else { throw ModelProvidersError.consentRequired }
                roleConsents.append(ModelConsentRecord(providerID: ref.providerID, origin: provider.origin,
                                                       consentedAt: consentedAt))
            }
        }
        switch role {
        case .vision: roles.vision = choice
        case .light: roles.light = choice
        }
    }

    /// The model a role's calls go to (Android RoleChoices.resolve). A chosen
    /// model whose provider is gone or was never agreed to is not used: light
    /// falls back to the main model, vision to none.
    public func resolvedModel(for role: ModelSideRole) -> ModelRef? {
        switch choice(for: role) {
        case .off: return nil
        case .sameAsMain: return roles.main
        case .model(let ref):
            guard provider(id: ref.providerID) != nil, hasConsent(forProvider: ref.providerID) else {
                return role == .light ? roles.main : nil
            }
            return ref
        }
    }

    /// The roles a provider's models are used for, in Android's order
    /// (providerLine: 主模型、看圖模型、輕量模型在用).
    public func rolesUsing(providerID: UUID) -> (main: Bool, vision: Bool, light: Bool) {
        (roles.main?.providerID == providerID,
         resolvedModel(for: .vision)?.providerID == providerID,
         resolvedModel(for: .light)?.providerID == providerID)
    }

    /// Whether a vision or light role names a model of this provider.
    func sideRolesUse(_ providerID: UUID) -> Bool {
        [roles.vision, roles.light].contains { choice in
            if case .model(let ref) = choice { return ref.providerID == providerID }
            return false
        }
    }

    /// Android ProviderStore.configFor and ModelOptions.seesImages: the
    /// person's switch for the model; else a model the vision role also uses
    /// (用主模型, or the same one chosen) sees images; else the model list,
    /// then the preset. Nil when nothing says.
    public func seesImages(_ ref: ModelRef) -> Bool? {
        guard let provider = provider(id: ref.providerID) else { return nil }
        if let said = provider.visionOverrides[ref.model] { return said }
        if resolvedModel(for: .vision) == ref { return true }
        return ModelProviderPresets.seesImages(provider: provider, model: ref.model)
    }

    /// Android ProviderStore.configFor: the main model counts as seeing images
    /// when the person never said otherwise for it and the vision role uses it
    /// too (用主模型, or the same model chosen), so pictures go straight to it.
    public var visionRoleUsesMain: Bool {
        guard let main = roles.main else { return false }
        return resolvedModel(for: .vision) == main
    }
}
