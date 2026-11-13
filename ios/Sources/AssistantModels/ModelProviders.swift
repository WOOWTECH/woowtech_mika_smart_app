import Foundation

/// How iOS talks to a provider. Phase 1 speaks only OpenAI-compatible
/// chat/completions; Anthropic, Gemini and Responses come with their adapters.
public enum ModelProviderKind: String, Codable, Sendable {
    case openAICompatible
}

/// One entry of a provider's model list, keeping only the parsed fields
/// (OpenRouter lists hundreds). Nil means the list did not say.
public struct ListedModel: Codable, Equatable, Sendable {
    public let id: String
    public let contextTokens: Int?
    public let vision: Bool?
    public let tools: Bool?

    public init(id: String, contextTokens: Int? = nil, vision: Bool? = nil, tools: Bool? = nil) {
        self.id = id; self.contextTokens = contextTokens; self.vision = vision; self.tools = tools
    }
}

/// One connected provider, as on Android (settings/ProviderStore.kt Provider).
/// Its key lives in the Keychain under `credentialAccount`, never here.
public struct ModelProvider: Codable, Equatable, Identifiable, Sendable {
    /// Stable. The provider imported from the single v1 setting takes that
    /// setting's Keychain account UUID, so its saved conversations still match.
    public let id: UUID
    public var name: String
    public let kind: ModelProviderKind
    /// Fixed once created: the key is only ever sent to this address.
    public let baseURL: URL
    /// The Keychain account holding the key; a replaced key gets a new one.
    /// Nil: no key, which only a custom OpenAI-compatible service may have.
    public var credentialAccount: UUID?
    /// The last model list: nil before listing, empty when the provider has none.
    public var models: [ListedModel]?
    /// A header this provider requires on every request (OpenCode Go:
    /// x-opencode-session); nil sends none.
    public var sessionHeader: String?
    /// Models a test call answered.
    public var verifiedModels: Set<String>
    /// Model names the user typed rather than picked from a list.
    public var typedModels: Set<String>
    /// Saved without listing models or a test call.
    public var savedUntested: Bool
    /// The user's "能看圖" answer per model name; it outranks the list.
    public var visionOverrides: [String: Bool]

    public init(id: UUID = UUID(), name: String, kind: ModelProviderKind = .openAICompatible, baseURL: URL,
                credentialAccount: UUID?, models: [ListedModel]? = nil, sessionHeader: String? = nil,
                verifiedModels: Set<String> = [], typedModels: Set<String> = [], savedUntested: Bool = false,
                visionOverrides: [String: Bool] = [:]) {
        self.id = id; self.name = name; self.kind = kind; self.baseURL = baseURL
        self.credentialAccount = credentialAccount; self.models = models; self.sessionHeader = sessionHeader
        self.verifiedModels = verifiedModels; self.typedModels = typedModels
        self.savedUntested = savedUntested; self.visionOverrides = visionOverrides
    }

    /// scheme://host[:port]: where content and the key go.
    public var origin: String { ModelProviderAddress.origin(of: baseURL) }

    func validate() throws {
        let named = verifiedModels.union(typedModels).union(visionOverrides.keys)
        guard ModelProviderAddress.isValid(baseURL),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 256, name.utf8.count <= 1024,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains),
              sessionHeader.map(ModelProviderAddress.isHeaderName) ?? true,
              (models?.count ?? 0) <= ModelProvidersDocument.maximumListedModels,
              models?.allSatisfy({ ModelProviderAddress.isModelName($0.id) && ($0.contextTokens ?? 1) > 0 }) ?? true,
              [verifiedModels.count, typedModels.count, visionOverrides.count]
                  .allSatisfy({ $0 <= ModelProvidersDocument.maximumNamedModels }),
              named.allSatisfy(ModelProviderAddress.isModelName)
        else { throw ModelProvidersError.invalidDocument }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, credentialAccount, models, sessionHeader
        case verifiedModels, typedModels, savedUntested, visionOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  kind: try c.decode(ModelProviderKind.self, forKey: .kind),
                  baseURL: try c.decode(URL.self, forKey: .baseURL),
                  credentialAccount: try c.decodeIfPresent(UUID.self, forKey: .credentialAccount),
                  models: try c.decodeIfPresent([ListedModel].self, forKey: .models),
                  sessionHeader: try c.decodeIfPresent(String.self, forKey: .sessionHeader),
                  verifiedModels: Set(try c.decodeIfPresent([String].self, forKey: .verifiedModels) ?? []),
                  typedModels: Set(try c.decodeIfPresent([String].self, forKey: .typedModels) ?? []),
                  savedUntested: try c.decodeIfPresent(Bool.self, forKey: .savedUntested) ?? false,
                  visionOverrides: try c.decodeIfPresent([String: Bool].self, forKey: .visionOverrides) ?? [:])
    }

    /// Sets are written sorted and empty fields left out, so the same
    /// provider always encodes to the same bytes.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind); try c.encode(baseURL, forKey: .baseURL)
        try c.encodeIfPresent(credentialAccount, forKey: .credentialAccount)
        try c.encodeIfPresent(models, forKey: .models)
        try c.encodeIfPresent(sessionHeader, forKey: .sessionHeader)
        if !verifiedModels.isEmpty { try c.encode(verifiedModels.sorted(), forKey: .verifiedModels) }
        if !typedModels.isEmpty { try c.encode(typedModels.sorted(), forKey: .typedModels) }
        if savedUntested { try c.encode(true, forKey: .savedUntested) }
        if !visionOverrides.isEmpty { try c.encode(visionOverrides, forKey: .visionOverrides) }
    }
}

/// A model at one provider: what a role, and a conversation, points at.
public struct ModelRef: Codable, Hashable, Sendable {
    public let providerID: UUID
    public let model: String

    public init(providerID: UUID, model: String) {
        self.providerID = providerID; self.model = model
    }
}

/// What a role other than the main one uses (Android RoleChoice).
public enum ModelRoleChoice: Codable, Equatable, Sendable {
    case model(ModelRef)
    case sameAsMain
    case off

    private enum CodingKeys: String, CodingKey { case use, providerID, model }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .use) {
        case "model":
            self = .model(ModelRef(providerID: try c.decode(UUID.self, forKey: .providerID),
                                   model: try c.decode(String.self, forKey: .model)))
        case "sameAsMain": self = .sameAsMain
        case "off": self = .off
        default: throw ModelProvidersError.invalidDocument
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .model(let ref):
            try c.encode("model", forKey: .use)
            try c.encode(ref.providerID, forKey: .providerID); try c.encode(ref.model, forKey: .model)
        case .sameAsMain: try c.encode("sameAsMain", forKey: .use)
        case .off: try c.encode("off", forKey: .use)
        }
    }
}

/// Which model each role uses (Android RoleChoices): the main model is a
/// concrete model or not chosen yet; vision is off until chosen; the light
/// model follows the main one and can never be off.
public struct ModelRoles: Codable, Equatable, Sendable {
    public var main: ModelRef?
    public var vision: ModelRoleChoice
    public var light: ModelRoleChoice

    public init(main: ModelRef? = nil, vision: ModelRoleChoice = .off, light: ModelRoleChoice = .sameAsMain) {
        self.main = main; self.vision = vision; self.light = light
    }

    private enum CodingKeys: String, CodingKey { case main, vision, light }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(main: try c.decodeIfPresent(ModelRef.self, forKey: .main),
                  vision: try c.decodeIfPresent(ModelRoleChoice.self, forKey: .vision) ?? .off,
                  light: try c.decodeIfPresent(ModelRoleChoice.self, forKey: .light) ?? .sameAsMain)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(main, forKey: .main)
        try c.encode(vision, forKey: .vision); try c.encode(light, forKey: .light)
    }
}

/// The last AI-sharing consent (App Review 5.1.2(i)): which provider the
/// user agreed to send their content to, and when.
public struct ModelConsentRecord: Codable, Equatable, Sendable {
    public let providerID: UUID
    /// scheme://host[:port] of that provider, kept after it is removed.
    public let origin: String
    public let consentedAt: Date

    public init(providerID: UUID, origin: String, consentedAt: Date) {
        self.providerID = providerID; self.origin = origin; self.consentedAt = consentedAt
    }
}

/// Whether saving or switching to a provider needs the consent first.
public enum ModelConsentRequirement: Equatable, Sendable {
    /// Nothing was ever agreed to: the first model-settings save.
    case firstTime
    /// Agreed to before, but for another provider.
    case differentProvider
    /// This provider is the one last agreed to.
    case alreadyGiven
}

/// What became of the single v1 setting.
public enum ModelLegacySettings: String, Codable, Sendable {
    /// It became the first provider.
    case imported
    /// It could not be read. Nothing was imported; the settings page can say
    /// so and ask for a provider.
    case unreadable
}

/// The single v1 setting, as the App read it for the one-time import.
public enum ModelLegacyRecord: Equatable, Sendable {
    case valid(baseURL: URL, model: String, credentialAccount: UUID, seesImages: Bool?)
    case unreadable
}

public enum ModelProvidersError: Error, Equatable, Sendable {
    case invalidDocument, unsupportedVersion, tooLarge, unknownProvider
    /// A blank key, and no saved key to keep.
    case missingKey
    /// A blank key for another host or port: a key never follows its address.
    case changedOrigin
}

/// What the settings page's one form does while it is the only way to edit
/// providers (phase 1a): it edits the main role's provider and model.
public struct ModelMainChange: Equatable, Sendable {
    public let document: ModelProvidersDocument
    public let provider: ModelProvider
    /// Write the new key under this account before publishing `document`.
    public let newAccount: UUID?
    /// The key was left blank: this account must still hold one.
    public let keptAccount: UUID?
    /// Delete these accounts only after `document` is published.
    public let retiredAccounts: [UUID]
}

/// Providers, their models and the roles that use them: Android's
/// providers.json, minus the parts iOS phase 1 does not have yet.
public struct ModelProvidersDocument: Codable, Equatable, Sendable {
    public static let version = 2
    public static let maximumProviders = 32
    public static let maximumListedModels = 5000
    public static let maximumNamedModels = 500
    public static let maximumEncodedBytes = 4 * 1024 * 1024

    public var providers: [ModelProvider]
    public var roles: ModelRoles
    public var consent: ModelConsentRecord?
    public var legacySettings: ModelLegacySettings?

    public init(providers: [ModelProvider] = [], roles: ModelRoles = ModelRoles(),
                consent: ModelConsentRecord? = nil, legacySettings: ModelLegacySettings? = nil) {
        self.providers = providers; self.roles = roles; self.consent = consent; self.legacySettings = legacySettings
    }

    public func provider(id: UUID) -> ModelProvider? { providers.first { $0.id == id } }

    public var mainProvider: ModelProvider? { roles.main.flatMap { provider(id: $0.providerID) } }

    /// One provider per id and per Keychain account, and every role pointing
    /// at a model of a provider that exists.
    public func validate() throws {
        let accounts = providers.compactMap(\.credentialAccount)
        guard providers.count <= Self.maximumProviders,
              Set(providers.map(\.id)).count == providers.count,
              Set(accounts).count == accounts.count else { throw ModelProvidersError.invalidDocument }
        for provider in providers { try provider.validate() }
        func exists(_ ref: ModelRef) -> Bool {
            provider(id: ref.providerID) != nil && ModelProviderAddress.isModelName(ref.model)
        }
        var choices = [roles.vision, roles.light]
        if let main = roles.main { choices.append(.model(main)) }
        guard roles.light != .off,
              choices.allSatisfy({ choice in
                  if case .model(let ref) = choice { return exists(ref) }
                  return true
              }),
              consent.map({ !$0.origin.isEmpty && $0.origin.utf8.count <= 4096 }) ?? true
        else { throw ModelProvidersError.invalidDocument }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw ModelProvidersError.tooLarge }
        return data
    }

    public static func decoded(from data: Data) throws -> ModelProvidersDocument {
        guard data.count <= maximumEncodedBytes else { throw ModelProvidersError.tooLarge }
        do { return try JSONDecoder().decode(ModelProvidersDocument.self, from: data) }
        catch let error as ModelProvidersError { throw error }
        catch { throw ModelProvidersError.invalidDocument }
    }

    private enum CodingKeys: String, CodingKey { case version, providers, roles, consent, legacySettings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .version) == Self.version else { throw ModelProvidersError.unsupportedVersion }
        self.init(providers: try c.decode([ModelProvider].self, forKey: .providers),
                  roles: try c.decodeIfPresent(ModelRoles.self, forKey: .roles) ?? ModelRoles(),
                  consent: try c.decodeIfPresent(ModelConsentRecord.self, forKey: .consent),
                  legacySettings: try c.decodeIfPresent(ModelLegacySettings.self, forKey: .legacySettings))
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(providers, forKey: .providers)
        try c.encode(roles, forKey: .roles)
        try c.encodeIfPresent(consent, forKey: .consent)
        try c.encodeIfPresent(legacySettings, forKey: .legacySettings)
    }
}

extension ModelProvidersDocument {
    /// The one-time import of the single v1 setting. Its Keychain account
    /// UUID becomes the provider id, so conversations saved under it still
    /// match, and stays the provider's account: nothing is read from the
    /// Keychain, so a locked device imports too.
    public static func importing(_ legacy: ModelLegacyRecord) -> ModelProvidersDocument {
        guard case .valid(let baseURL, let model, let account, let seesImages) = legacy else {
            return ModelProvidersDocument(legacySettings: .unreadable)
        }
        let provider = ModelProvider(id: account, name: ModelProviderPresets.displayName(for: baseURL),
                                     baseURL: baseURL, credentialAccount: account,
                                     sessionHeader: ModelProviderPresets.preset(at: baseURL)?.sessionHeader,
                                     typedModels: [model], savedUntested: true,
                                     visionOverrides: seesImages.map { [model: $0] } ?? [:])
        let document = ModelProvidersDocument(providers: [provider],
                                              roles: ModelRoles(main: ModelRef(providerID: account, model: model)),
                                              legacySettings: .imported)
        // A setting the v1 build accepted but a provider cannot hold counts as unreadable.
        guard (try? document.validate()) != nil else { return ModelProvidersDocument(legacySettings: .unreadable) }
        return document
    }

    /// Saving the settings form (phase 1a). The same address edits the main
    /// provider; another address is another provider, which takes the previous
    /// main provider's place as the single setting did. A blank key keeps the
    /// saved one only at the same scheme, host and port.
    public func replacingMain(baseURL: URL, model: String, keyReplaced: Bool,
                              newProviderID: UUID = UUID(), newAccount: UUID = UUID()) throws -> ModelMainChange {
        let previous = mainProvider
        var next = self
        var provider: ModelProvider
        if let previous, previous.baseURL == baseURL {
            provider = previous
        } else {
            provider = ModelProvider(id: newProviderID, name: ModelProviderPresets.displayName(for: baseURL),
                                     baseURL: baseURL, credentialAccount: nil,
                                     sessionHeader: ModelProviderPresets.preset(at: baseURL)?.sessionHeader,
                                     savedUntested: true)
            if let previous { next.providers.removeAll { $0.id == previous.id } }
        }
        var kept: UUID?
        var retired: [UUID] = []
        if keyReplaced {
            if let old = previous?.credentialAccount { retired.append(old) }
            provider.credentialAccount = newAccount
        } else {
            guard let previous, let account = previous.credentialAccount else { throw ModelProvidersError.missingKey }
            guard ModelProviderAddress.sameOrigin(previous.baseURL, baseURL) else { throw ModelProvidersError.changedOrigin }
            provider.credentialAccount = account
            kept = account
        }
        // The form keeps one typed model per provider; answers about other models go with them.
        provider.typedModels = [model]
        provider.visionOverrides = provider.visionOverrides.filter { $0.key == model }
        if let index = next.providers.firstIndex(where: { $0.id == provider.id }) { next.providers[index] = provider }
        else { next.providers.append(provider) }
        next.roles.main = ModelRef(providerID: provider.id, model: model)
        next.pruneRoles()
        try next.validate()
        return ModelMainChange(document: next, provider: provider, newAccount: keyReplaced ? newAccount : nil,
                               keptAccount: kept, retiredAccounts: retired)
    }

    /// The user's "能看圖" answer for the main model; nil forgets it.
    public mutating func setMainVision(_ sees: Bool?) throws {
        guard let main = roles.main, let index = providers.firstIndex(where: { $0.id == main.providerID }) else {
            throw ModelProvidersError.unknownProvider
        }
        providers[index].visionOverrides[main.model] = sees
    }

    /// Removes one provider and returns its Keychain account, to delete only
    /// after the document without it is published.
    public mutating func removeProvider(id: UUID) throws -> UUID? {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { throw ModelProvidersError.unknownProvider }
        let removed = providers.remove(at: index)
        pruneRoles()
        return removed.credentialAccount
    }

    /// Roles pointing at a provider that is gone fall back as on Android
    /// (RoleChoices.keepOnly): main not chosen, vision off, light same as main.
    mutating func pruneRoles() {
        let ids = Set(providers.map(\.id))
        if let main = roles.main, !ids.contains(main.providerID) { roles.main = nil }
        if case .model(let ref) = roles.vision, !ids.contains(ref.providerID) { roles.vision = .off }
        if case .model(let ref) = roles.light, !ids.contains(ref.providerID) { roles.light = .sameAsMain }
    }

    /// Keychain accounts of this service that no provider uses: an interrupted
    /// save, a removed provider whose key could not be deleted, or the v1
    /// setting that could not be read.
    public func orphanedAccounts(among accounts: Set<String>) -> Set<String> {
        let used = Set(providers.compactMap(\.credentialAccount))
        return accounts.filter { account in UUID(uuidString: account).map { !used.contains($0) } ?? true }
    }

    /// The provider the form would save to at this address: the main one when
    /// the address is unchanged; nil means a new provider.
    public func mainProviderID(at baseURL: URL) -> UUID? {
        mainProvider.flatMap { $0.baseURL == baseURL ? $0.id : nil }
    }

    /// Asked on the first save ever and again for any provider other than the
    /// last one agreed to; nil stands for a provider not created yet.
    public func consentRequirement(forProvider id: UUID?) -> ModelConsentRequirement {
        guard let consent else { return .firstTime }
        return id == consent.providerID ? .alreadyGiven : .differentProvider
    }

    public mutating func recordConsent(forProvider id: UUID, at date: Date) throws {
        guard let provider = provider(id: id) else { throw ModelProvidersError.unknownProvider }
        consent = ModelConsentRecord(providerID: id, origin: provider.origin, consentedAt: date)
    }
}

/// Who a model request goes to and with which stored key, compared in place
/// of the key itself. A new key for the same provider keeps `target`, so its
/// conversations continue; the new account still stops work already running.
public struct ModelAccessIdentity: Hashable, Sendable {
    public let target: ModelRef
    public let credentialAccount: UUID?

    public init(target: ModelRef, credentialAccount: UUID?) {
        self.target = target; self.credentialAccount = credentialAccount
    }
}

/// One provider chip (Android settings/ProviderPresets.kt at 964d7bec).
public struct ModelProviderPreset: Equatable, Sendable {
    public let name: String
    public let baseURL: URL
    public let sessionHeader: String?
}

public enum ModelProviderPresets {
    /// Phase 1's chips: Android's OpenAI-compatible presets. Ollama and LM
    /// Studio use loopback HTTP, which iOS never saves.
    public static let all: [ModelProviderPreset] = [
        preset("OpenRouter", "https://openrouter.ai/api/v1"),
        preset("Requesty", "https://router.requesty.ai/v1"),
        // Rejects a request without its conversation's session (HTTP 400).
        preset("OpenCode Go", "https://opencode.ai/zen/go/v1", sessionHeader: "x-opencode-session"),
        preset("xAI", "https://api.x.ai/v1"),
        preset("Mistral", "https://api.mistral.ai/v1"),
        preset("Groq", "https://api.groq.com/openai/v1"),
    ]

    /// Services whose chips come with their own adapters, named already
    /// because iOS can save their addresses today. iOS calls chat/completions
    /// only: the OpenAI-compatible addresses of the Anthropic and Gemini
    /// presets name the same providers.
    private static let otherNames: [(name: String, baseURL: String)] = [
        ("Anthropic", "https://api.anthropic.com"),
        ("Gemini", "https://generativelanguage.googleapis.com"),
        ("OpenAI", "https://api.openai.com/v1"),
        ("Anthropic", "https://api.anthropic.com/v1"),
        ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai"),
    ]

    private static func preset(_ name: String, _ address: String, sessionHeader: String? = nil) -> ModelProviderPreset {
        ModelProviderPreset(name: name, baseURL: URL(string: address)!, sessionHeader: sessionHeader)
    }

    public static func preset(at url: URL) -> ModelProviderPreset? {
        guard let address = ModelProviderAddress.normalized(url) else { return nil }
        return all.first { ModelProviderAddress.normalized($0.baseURL) == address }
    }

    /// Android ProviderConnection.nameForUrl: the preset at this address,
    /// otherwise the host.
    public static func displayName(for url: URL) -> String {
        let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
        guard let address = ModelProviderAddress.normalized(url) else { return host ?? url.absoluteString }
        return preset(at: url)?.name
            ?? otherNames.first { URL(string: $0.baseURL).flatMap(ModelProviderAddress.normalized) == address }?.name
            ?? host ?? url.absoluteString
    }
}

/// Address, header and model-name rules shared by providers and their keys.
public enum ModelProviderAddress {
    /// HTTPS with a host and nothing a key could leak through: no user,
    /// password, query or fragment. The same bounds as a saved conversation's
    /// destination, so every provider can own conversations.
    public static func isValid(_ url: URL) -> Bool {
        let raw = url.absoluteString
        guard raw.utf8.count <= 4096,
              !raw.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains),
              let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.url != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        return true
    }

    /// A key typed for one scheme, host and port is never sent to another.
    public static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? 443) == (rhs.port ?? 443)
    }

    public static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "", host = url.host?.lowercased() ?? ""
        let port = url.port.map { scheme == "https" && $0 == 443 ? "" : ":\($0)" } ?? ""
        return scheme + "://" + (host.contains(":") ? "[" + host + "]" : host) + port
    }

    /// Android compares addresses without trailing slashes; host letter case
    /// and an explicit default port do not make a different address either.
    static func normalized(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        let port = parts.port.map { scheme == "https" && $0 == 443 ? "" : ":\($0)" } ?? ""
        return scheme + "://" + host + port + path
    }

    /// An HTTP token (RFC 9110), so a header name cannot inject another header.
    static func isHeaderName(_ name: String) -> Bool {
        let extra = Set("!#$%&'*+-.^_`|~".utf8)
        return (1...64).contains(name.utf8.count) && name.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || extra.contains(byte)
        }
    }

    /// As the form saves it: trimmed, one line, bounded like a conversation's model.
    static func isModelName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 1024 && name.trimmingCharacters(in: .whitespacesAndNewlines) == name
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains)
    }
}
