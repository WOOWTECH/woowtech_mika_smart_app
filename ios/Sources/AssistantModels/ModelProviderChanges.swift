import Foundation

/// What the add-provider form saves (Android AddForm with
/// ProviderStore.connect). Phase 1 lists no models, so the model is the one
/// the user typed.
public struct ModelProviderDraft: Equatable, Sendable {
    /// The preset's name, or the custom name (the host when left blank).
    public let name: String
    public let baseURL: URL
    /// The preset's session header, or the one of a preset at this address.
    public let sessionHeader: String?
    /// False only for a custom OpenAI-compatible service (Android
    /// AddForm.keyRequired): it may be saved without a key.
    public let keyRequired: Bool
    /// A key was typed. Without one, the same provider keeps its key and a new
    /// one has none.
    public let hasNewKey: Bool
    /// The typed model; nil saves only the provider.
    public let model: String?
    /// The model answered the connection test ("測試並儲存").
    public let tested: Bool

    public init(name: String, baseURL: URL, sessionHeader: String?, keyRequired: Bool, hasNewKey: Bool,
                model: String?, tested: Bool) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL; self.sessionHeader = sessionHeader
        self.keyRequired = keyRequired; self.hasNewKey = hasNewKey; self.model = model; self.tested = tested
    }
}

/// The save of a draft as planned, before any Keychain item or file changes.
public struct ModelProviderAddition: Equatable, Sendable {
    public let document: ModelProvidersDocument
    public let provider: ModelProvider
    /// Write the new key under this account before publishing `document`.
    public let newAccount: UUID?
    /// Delete these accounts only after `document` is published.
    public let retiredAccounts: [UUID]
    /// The typed model became the main model (nothing was main yet).
    public let becameMain: Bool
    /// A provider with the same kind, address and name was updated.
    public let updatedExisting: Bool
}

/// A replaced key, as planned: the new account goes in first, the old one
/// goes only after the document is published.
public struct ModelKeyChange: Equatable, Sendable {
    public let document: ModelProvidersDocument
    public let newAccount: UUID
    public let retiredAccount: UUID?
}

extension ModelProvidersDocument {
    /// Android's same provider (ModelOptions.sameProvider): the same kind,
    /// address and name. One address under two names is two providers, for
    /// example two keys for one relay.
    public func sameProvider(name: String, baseURL: URL) -> ModelProvider? {
        let address = ModelProviderAddress.normalized(baseURL)
        return providers.first { $0.kind == .openAICompatible && $0.name == name
            && address != nil && ModelProviderAddress.normalized($0.baseURL) == address }
    }

    /// Saving `draft` makes its model the main model only while none is
    /// chosen, as Android's testAndSave.
    public func additionBecomesMain(_ draft: ModelProviderDraft) -> Bool {
        roles.main == nil && draft.model != nil
    }

    /// The AI-sharing consent (App Review 5.1.2(i)) this save needs first; nil
    /// when it needs none: its model will not be the main one, or its provider
    /// is the one last agreed to.
    public func consentRequirement(forAdding draft: ModelProviderDraft) -> ModelConsentRequirement? {
        guard additionBecomesMain(draft) else { return nil }
        let requirement = consentRequirement(forProvider: sameProvider(name: draft.name, baseURL: draft.baseURL)?.id)
        return requirement == .alreadyGiven ? nil : requirement
    }

    /// The consent switching the main model to `ref` needs; nil when its
    /// provider is the one last agreed to.
    public func consentRequirement(forMain ref: ModelRef) -> ModelConsentRequirement? {
        let requirement = consentRequirement(forProvider: ref.providerID)
        return requirement == .alreadyGiven ? nil : requirement
    }

    /// A main model exists but its provider was never agreed to: a document
    /// from before the consent existed, or anything else that skipped it.
    /// Nothing may be sent to the main model until it is.
    public var mainNeedsConsent: Bool {
        guard let main = roles.main else { return false }
        return consent?.providerID != main.providerID
    }

    /// Android ProviderStore.connect: the same provider is updated (a typed
    /// key replaces its key, a blank one keeps it); otherwise a new provider is
    /// added. The typed model is remembered as typed, and as verified when it
    /// answered the test; it becomes the main model only while none is
    /// chosen, and then only with the user's consent (`consentedAt`).
    public func addingProvider(_ draft: ModelProviderDraft, consentedAt: Date?,
                               newProviderID: UUID = UUID(), newAccount: UUID = UUID()) throws -> ModelProviderAddition {
        if let model = draft.model, !ModelProviderAddress.isModelName(model) { throw ModelProvidersError.invalidDocument }
        guard ModelProviderAddress.isValid(draft.baseURL) else { throw ModelProvidersError.invalidDocument }
        var next = self
        let found = sameProvider(name: draft.name, baseURL: draft.baseURL)
        var provider = found ?? ModelProvider(id: newProviderID, name: draft.name, baseURL: draft.baseURL, credentialAccount: nil)
        if found == nil, providers.count >= Self.maximumProviders { throw ModelProvidersError.tooManyProviders }
        var retired: [UUID] = []
        if draft.hasNewKey {
            if let old = provider.credentialAccount { retired.append(old) }
            provider.credentialAccount = newAccount
        } else if draft.keyRequired && provider.credentialAccount == nil {
            throw ModelProvidersError.missingKey
        }
        provider.sessionHeader = draft.sessionHeader
        if let model = draft.model {
            provider.typedModels.insert(model)
            if draft.tested { provider.verifiedModels.insert(model) }
        }
        // Not tested, and nothing about it was ever known: Android's savedUntested.
        provider.savedUntested = !draft.tested && provider.verifiedModels.isEmpty && (provider.models ?? []).isEmpty
        if let index = next.providers.firstIndex(where: { $0.id == provider.id }) { next.providers[index] = provider }
        else { next.providers.append(provider) }
        let becameMain = additionBecomesMain(draft)
        if becameMain, let model = draft.model {
            try next.adoptMain(ModelRef(providerID: provider.id, model: model), consentedAt: consentedAt)
        }
        try next.validate()
        return ModelProviderAddition(document: next, provider: provider, newAccount: draft.hasNewKey ? newAccount : nil,
                                     retiredAccounts: retired, becameMain: becameMain, updatedExisting: found != nil)
    }

    /// Android ProviderStore.use(Main): a model of a provider becomes the
    /// main model. A typed name is remembered as typed, a model that answered
    /// a test call as verified. Another provider than the one last agreed to
    /// needs the user's consent (`consentedAt`).
    public func choosingMain(_ ref: ModelRef, typed: Bool, verified: Bool, consentedAt: Date?) throws -> ModelProvidersDocument {
        guard let index = providers.firstIndex(where: { $0.id == ref.providerID }) else { throw ModelProvidersError.unknownProvider }
        guard ModelProviderAddress.isModelName(ref.model) else { throw ModelProvidersError.invalidDocument }
        var next = self
        if typed { next.providers[index].typedModels.insert(ref.model) }
        if verified { next.providers[index].verifiedModels.insert(ref.model); next.providers[index].savedUntested = false }
        try next.adoptMain(ref, consentedAt: consentedAt)
        try next.validate()
        return next
    }

    /// Android markVerified: the model answered a test call, so the provider
    /// is no longer "saved without a test".
    public func markingVerified(providerID: UUID, model: String) throws -> ModelProvidersDocument {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { throw ModelProvidersError.unknownProvider }
        guard ModelProviderAddress.isModelName(model) else { throw ModelProvidersError.invalidDocument }
        var next = self
        next.providers[index].verifiedModels.insert(model)
        next.providers[index].savedUntested = false
        try next.validate()
        return next
    }

    /// Android updateProviderKey: one provider's key, under a new account.
    public func changingKey(providerID: UUID, newAccount: UUID = UUID()) throws -> ModelKeyChange {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { throw ModelProvidersError.unknownProvider }
        var next = self
        let old = next.providers[index].credentialAccount
        next.providers[index].credentialAccount = newAccount
        try next.validate()
        return ModelKeyChange(document: next, newAccount: newAccount, retiredAccount: old)
    }

    /// The user's "能看圖" answer for one model of one provider; nil forgets it.
    public mutating func setVision(_ sees: Bool?, providerID: UUID, model: String) throws {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { throw ModelProvidersError.unknownProvider }
        guard ModelProviderAddress.isModelName(model) else { throw ModelProvidersError.invalidDocument }
        providers[index].visionOverrides[model] = sees
    }

    /// The user agreed to send their content to the main model's provider.
    public mutating func recordConsentForMain(at date: Date) throws {
        guard let main = roles.main else { throw ModelProvidersError.unknownProvider }
        try recordConsent(forProvider: main.providerID, at: date)
    }

    /// The models a provider's page and the main-model picker offer, Android
    /// sortedOptions: the main model first, then what the user typed or a test
    /// call confirmed, then the rest of the list in its own order.
    public func knownModels(of providerID: UUID) -> [String] {
        guard let provider = provider(id: providerID) else { return [] }
        var seen = Set<String>(), ordered: [String] = []
        func add(_ model: String) { if seen.insert(model).inserted { ordered.append(model) } }
        if let main = roles.main, main.providerID == providerID { add(main.model) }
        provider.typedModels.union(provider.verifiedModels)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }.forEach(add)
        provider.models?.forEach { add($0.id) }
        return ordered
    }

    /// Makes `ref` the main model, recording the consent when its provider
    /// is not the one last agreed to; without one, nothing changes.
    private mutating func adoptMain(_ ref: ModelRef, consentedAt: Date?) throws {
        if consent?.providerID != ref.providerID {
            guard let consentedAt else { throw ModelProvidersError.consentRequired }
            try recordConsent(forProvider: ref.providerID, at: consentedAt)
        }
        roles.main = ref
    }
}
