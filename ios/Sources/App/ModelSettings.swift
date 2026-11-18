import AssistantModels
import Foundation
import Security

struct SavedModelSettings: Codable {
    let baseURL: URL
    let model: String
    // This is a Keychain item identifier, never the key itself.
    let credentialAccount: String
    /// The user's "能看圖" answer for exactly this endpoint and model, as on
    /// Android; nil means not said, which never counts as support.
    var seesImages: Bool? = nil
    /// The provider of the main model. Nil in a single record: the script
    /// service's, and the v1 setting before its import.
    var providerID: UUID? = nil
    /// The header the main model's provider requires on every request
    /// (OpenCode Go: x-opencode-session); nil sends none.
    var sessionHeader: String? = nil
    /// The main model's provider kind; nil in a single record. An account
    /// sign-in's requests carry its account route instead of a key.
    var providerKind: ModelProviderKind? = nil

    // Exactly the v1 record's keys; the provider never enters that record.
    private enum CodingKeys: String, CodingKey { case baseURL, model, credentialAccount, seesImages }

    /// A provider saved without a key (only a custom OpenAI-compatible one)
    /// sends none; every other record needs its Keychain item.
    var requiresKey: Bool { providerID == nil || !credentialAccount.isEmpty }

    /// The request settings for one conversation, whose id gives the
    /// provider's session header its value; nil (work outside a conversation)
    /// takes a fresh value.
    func configuration(conversation: String?) -> ModelConfiguration {
        let header = sessionHeader.flatMap { name in
            conversation.map { ModelSessionHeader.conversation($0, name: name) } ?? ModelSessionHeader.fresh(name: name)
        }
        return ModelConfiguration(baseURL: baseURL, model: model,
                                  vision: seesImages.map { $0 ? .supported : .unsupported } ?? .unknown,
                                  requiresKey: requiresKey, sessionHeader: header, account: accountRoute)
    }

    /// The signed-in account the main model's requests use; nil for a key.
    var accountRoute: ModelAccountRoute? {
        guard let providerID, let account = providerKind?.account else { return nil }
        return ModelAccountRoute(kind: account, providerID: providerID)
    }

    var configuration: ModelConfiguration { configuration(conversation: nil) }

    /// Provider, model and Keychain item, compared instead of the key. A
    /// record without a provider counts its account as one, as the import does.
    var accessIdentity: ModelAccessIdentity? {
        guard let provider = providerID ?? UUID(uuidString: credentialAccount) else { return nil }
        return ModelAccessIdentity(target: ModelRef(providerID: provider, model: model),
                                   credentialAccount: UUID(uuidString: credentialAccount))
    }
}

enum ModelSettingsError: Error, LocalizedError {
    case invalidURL, missingModel, missingKey, changedOrigin, invalidKey, unavailableKeychain
    case keychainStatus(OSStatus)
    /// The provider document already holds as many providers as it can.
    case tooManyProviders
    /// The main model would change to a provider the user has not agreed to send content to.
    case consentRequired

    var errorDescription: String? {
        switch self {
        case .tooManyProviders:
            return "服務商已達上限，請先刪除不用的服務商。"
        case .consentRequired:
            return "還沒有同意把內容傳給這家服務商，設定未變更。"
        case .invalidURL:
            return "請輸入完整的 HTTPS Base URL，不可包含帳密、查詢參數或片段。"
        case .missingModel:
            return "請填寫服務供應商提供的模型名稱。"
        case .missingKey:
            return "請輸入 API Key。已有儲存的金鑰時，同一服務可留空沿用。"
        case .changedOrigin:
            return "服務主機或連接埠已變更，請重新輸入該服務的 API Key；不會自動沿用舊金鑰。"
        case .invalidKey:
            return "API Key 不可包含空白或控制字元。"
        case .unavailableKeychain:
            return "無法存取 Keychain，設定未變更。請解鎖裝置後再試。"
        case .keychainStatus(let status):
            return "Keychain 存取失敗（系統代碼 \(status)），設定未變更。"
        }
    }
}

/// What saving the add-provider form did.
struct ModelProviderSaved {
    /// The main model afterwards; nil while none is chosen.
    let main: SavedModelSettings?
    let providerID: UUID
    let providerName: String
    /// The typed model became the main model.
    let becameMain: Bool
    /// Deleting a replaced key failed; the sweep retries it.
    let cleanupFailed: Bool
}

protocol ModelCredentialStoring {
    func read(account: String) throws -> String?
    func insert(_ key: String, account: String) throws
    func remove(account: String) throws
    func removeAll() throws
    /// Every account of this service, to find keys no provider uses. Nil
    /// when this store cannot list them; nothing is swept then.
    func allAccounts() throws -> Set<String>?
    /// Rewrites one item in place, for an account sign-in whose tokens were
    /// refreshed or cleared: the item keeps its account, so work using the
    /// provider goes on.
    func replace(_ key: String, account: String) throws
}

extension ModelCredentialStoring {
    func allAccounts() throws -> Set<String>? { nil }

    func replace(_ key: String, account: String) throws {
        try remove(account: account)
        try insert(key, account: account)
    }
}

struct KeychainModelCredentials: ModelCredentialStoring {
    let service: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrSynchronizable as String: false]
    }

    func read(account: String) throws -> String? {
        var query = query
        query[kSecAttrAccount as String] = account
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ModelSettingsError.keychainStatus(status) }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw ModelSettingsError.unavailableKeychain
        }
        return key
    }

    func insert(_ key: String, account: String) throws {
        var query = query
        query[kSecAttrAccount as String] = account
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ModelSettingsError.keychainStatus(status) }
    }

    func remove(account: String) throws {
        var query = query
        query[kSecAttrAccount as String] = account
        try delete(query)
    }

    func replace(_ key: String, account: String) throws {
        var query = query
        query[kSecAttrAccount as String] = account
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        if status == errSecItemNotFound { return try insert(key, account: account) }
        guard status == errSecSuccess else { throw ModelSettingsError.keychainStatus(status) }
    }

    func removeAll() throws {
        // Always service-scoped: never clear the system Keychain or another app's items.
        try delete(query)
    }

    /// Account names only; no key is read.
    func allAccounts() throws -> Set<String>? {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = items as? [[String: Any]] else {
            throw ModelSettingsError.keychainStatus(status)
        }
        return Set(rows.compactMap { $0[kSecAttrAccount as String] as? String })
    }

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ModelSettingsError.keychainStatus(status)
        }
    }
}

/// Where the provider document lives. No key is ever written here.
protocol ModelProvidersStoring {
    /// Nil only when there is no document; any other failure throws, so an
    /// unreadable document is never mistaken for none and replaced.
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

/// Application Support/ModelProviders/<scope>/providers.json, replaced
/// atomically and readable from the first unlock after a restart. It is
/// backed up but the keys (ThisDeviceOnly) are not: a restored device has its
/// providers and asks for their keys again.
struct ModelProvidersFile: ModelProvidersStoring {
    let url: URL

    /// "personal", or one isolated UI test namespace.
    static func live(scope: String = "personal") -> ModelProvidersFile {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModelProvidersFile(url: support.appendingPathComponent("ModelProviders/" + scope, isDirectory: true)
            .appendingPathComponent("providers.json"))
    }

    func read() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where Self.missing(error) { return nil }
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func remove() throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where Self.missing(error) {}
    }

    private static func missing(_ error: CocoaError) -> Bool {
        error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }
}

/// The document in one key of the repository's own defaults: for isolated
/// test suites, which remove their whole domain when they end.
struct ModelProvidersInDefaults: ModelProvidersStoring {
    let defaults: UserDefaults

    func read() throws -> Data? { defaults.data(forKey: ModelSettingsRepository.providersKey) }
    func write(_ data: Data) throws { defaults.set(data, forKey: ModelSettingsRepository.providersKey) }
    func remove() throws { defaults.removeObject(forKey: ModelSettingsRepository.providersKey) }
}

final class ModelSettingsRepository {
    static let configurationKey = "model.configuration.v1"
    /// Set once the v1 record has become the provider document. The record
    /// itself stays for one version, so an older build still finds it.
    static let migratedKey = "model.configuration.v1.migrated"
    /// The document's key when a test suite keeps it in its own defaults.
    static let providersKey = "model.providers.v2"
    private static let revisionKey = "model.configuration.revision.v1"
    // Shared across repository instances in this process. Dispatch of a
    // speech request and every repository mutation use the same boundary.
    static func withSpeechDispatchLock<T>(_ body: () throws -> T) rethrows -> T {
        try SpeechChoiceStore.withCoordination(body)
    }
    private let defaults: UserDefaults
    private let credentials: any ModelCredentialStoring
    /// The main model's provider document; nil keeps one v1 record instead.
    private let providers: (any ModelProvidersStoring)?
    /// One token gate per signed-in provider, shared by every caller of this
    /// repository, so there is only ever one refresh at a time.
    let accountGates = ModelAccountGateRegistry()

    /// Providers with their document in `defaults` itself, for an isolated
    /// test suite. The App passes its file.
    convenience init(defaults: UserDefaults, credentials: any ModelCredentialStoring) {
        self.init(defaults: defaults, credentials: credentials, providers: ModelProvidersInDefaults(defaults: defaults))
    }

    init(defaults: UserDefaults, credentials: any ModelCredentialStoring, providers: (any ModelProvidersStoring)?) {
        self.defaults = defaults
        self.credentials = credentials
        self.providers = providers
    }

    /// One record and one key, as before providers: the script service, which
    /// is neither imported nor given providers.
    static func singleRecord(defaults: UserDefaults, credentials: any ModelCredentialStoring) -> ModelSettingsRepository {
        ModelSettingsRepository(defaults: defaults, credentials: credentials, providers: nil)
    }

    static func validate(baseURL: String, model: String) throws -> ModelConfiguration {
        let url = try validatedAddress(baseURL)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ModelSettingsError.missingModel
        }
        return ModelConfiguration(baseURL: url, model: model)
    }

    /// A typed address as a provider can hold it: HTTPS with a host and a valid
    /// port, nothing a key could leak through (no user, password, query or
    /// fragment), and no spaces or control characters.
    static func validatedAddress(_ raw: String) throws -> URL {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              validRawPort(in: address),
              let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url, ModelProviderAddress.isValid(url) else { throw ModelSettingsError.invalidURL }
        return url
    }

    /// Inspect the original authority before Foundation can discard an empty
    /// or overflowing port. Leading-zero numeric ports remain valid for chat;
    /// speech has its own stricter reviewed-destination rules.
    private static func validRawPort(in address: String) -> Bool {
        guard let separator = address.range(of: "://") else { return false }
        let rest = address[separator.upperBound...]
        let authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let suffix: Substring
        if authority.first == "[" {
            guard let closing = authority.firstIndex(of: "]") else { return false }
            suffix = authority[authority.index(after: closing)...]
        } else if let colon = authority.firstIndex(of: ":") {
            suffix = authority[colon...]
        } else { return true }
        if suffix.isEmpty { return true }
        guard suffix.first == ":" else { return false }
        let digits = suffix.dropFirst()
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(digits), (1...65535).contains(port) else { return false }
        return true
    }

    /// The main model: its provider's address and key, the model and the
    /// "能看圖" answer. The first call after an update imports the v1 setting.
    func load() throws -> SavedModelSettings? {
        guard providers != nil else { return try loadRecord() }
        return try Self.withSpeechDispatchLock { Self.main(in: try documentLocked()) }
    }

    /// The whole provider document, importing the v1 setting first if needed.
    func document() throws -> ModelProvidersDocument? {
        try Self.withSpeechDispatchLock { try documentLocked() }
    }

    func key(for record: SavedModelSettings) throws -> String {
        // A provider saved without a key sends none.
        if !record.requiresKey { return "" }
        guard UUID(uuidString: record.credentialAccount) != nil,
              let key = try credentials.read(account: record.credentialAccount), !key.isEmpty else {
            throw ModelSettingsError.missingKey
        }
        // An account's item holds its whole sign-in. It never leaves as a key:
        // requests take a token from the account's gate (ModelAccountTokens),
        // and a signed-out account says so when it is used.
        if record.providerKind?.account != nil { return "" }
        return key
    }

    // Every successful in-process write advances this value, including an
    // edit followed by a return to the original values. It contains no key.
    var revision: String { defaults.string(forKey: Self.revisionKey) ?? "legacy" }

    /// The single form's save: the script service's one record, or the main
    /// provider (phase 1a). Records no consent; Settings › 模型 saves through
    /// addProvider and chooseMain, after its consent screen.
    func save(baseURL: String, model: String, newKey: String) throws -> (record: SavedModelSettings, cleanupFailed: Bool) {
        try Self.withSpeechDispatchLock {
            providers == nil ? try saveRecordLocked(baseURL: baseURL, model: model, newKey: newKey)
                : try saveMainLocked(baseURL: baseURL, model: model, newKey: newKey)
        }
    }

    /// The form edits the main role's provider and model (phase 1a; see
    /// ModelProvidersDocument.replacingMain).
    private func saveMainLocked(baseURL: String, model: String, newKey: String) throws -> (record: SavedModelSettings, cleanupFailed: Bool) {
        let configuration = try Self.validate(baseURL: baseURL, model: model)
        let document = try documentLocked() ?? ModelProvidersDocument()
        let newKey = try Self.checkedKey(newKey)
        let change: ModelMainChange
        do {
            change = try document.replacingMain(baseURL: configuration.baseURL, model: configuration.model,
                                                keyReplaced: !newKey.isEmpty)
        } catch ModelProvidersError.missingKey { throw ModelSettingsError.missingKey }
        catch ModelProvidersError.changedOrigin { throw ModelSettingsError.changedOrigin }
        if let kept = change.keptAccount { _ = try storedKey(account: kept) }
        let data = try change.document.encoded()
        guard let record = Self.main(in: change.document) else { throw ModelProvidersError.invalidDocument }
        if let account = change.newAccount { try credentials.insert(newKey, account: account.uuidString) }
        // Publish only after the new item exists and delete the old one last:
        // an interruption leaves at worst an unused item for the sweep, never a
        // document whose key is gone.
        try publish(data, insertedAccount: change.newAccount)
        return (record, retire(change.retiredAccounts))
    }

    /// Records whether the saved model can see images. Same boundary and
    /// revision bump as every other mutation, so in-flight work notices.
    func setSeesImages(_ value: Bool?) throws -> SavedModelSettings {
        try Self.withSpeechDispatchLock {
            guard providers != nil else { return try setRecordSeesImagesLocked(value) }
            guard var document = try documentLocked() else { throw ModelSettingsError.missingModel }
            do { try document.setMainVision(value) } catch { throw ModelSettingsError.missingModel }
            guard let record = Self.main(in: document) else { throw ModelSettingsError.missingModel }
            try publish(document.encoded(), insertedAccount: nil)
            return record
        }
    }

    func remove() throws {
        try Self.withSpeechDispatchLock {
            // Even a failing Keychain operation may have partially mutated
            // credentials. Invalidate staged uploads before attempting it.
            defaults.set(UUID().uuidString, forKey: Self.revisionKey)
            try credentials.removeAll()
            try providers?.remove()
            defaults.removeObject(forKey: Self.configurationKey)
            defaults.removeObject(forKey: Self.migratedKey)
        }
    }

    /// Removes one provider and only its key, deleted after the document
    /// without it is published; roles that used it fall back as on Android.
    /// Returns whether deleting the key failed (the sweep retries it).
    @discardableResult func removeProvider(id: UUID) throws -> Bool {
        try Self.withSpeechDispatchLock {
            guard var document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            let kind = document.provider(id: id)?.kind
            let account = try document.removeProvider(id: id)
            try publish(document.encoded(), insertedAccount: nil)
            // Android removeProvider: a deleted ChatGPT provider forgets its
            // registered client id; this device's host id stays.
            if kind == .chatGPTAccount { forgetChatGPTClientLocked() }
            return retire(account.map { [$0] } ?? [])
        }
    }

    /// Deletes this service's Keychain items that no provider uses. Does
    /// nothing when the Keychain cannot list them (for example while locked)
    /// or the document cannot be read. Returns how many were deleted.
    @discardableResult func sweepOrphanedCredentials() throws -> Int {
        guard providers != nil else { return 0 }
        return try Self.withSpeechDispatchLock {
            let document = try documentLocked() ?? ModelProvidersDocument()
            guard let accounts = try credentials.allAccounts() else { return 0 }
            let orphans = document.orphanedAccounts(among: accounts)
            for account in orphans.sorted() { try credentials.remove(account: account) }
            return orphans.count
        }
    }

    /// Whether saving the single form for this address needs the AI-sharing
    /// consent (App Review 5.1.2(i)) first: the first save ever, or a provider
    /// other than the one last agreed to. Settings › 模型 asks on its consent
    /// screen (ModelConsentSheet) through addProvider and chooseMain.
    func consentRequirement(forSaving baseURL: URL) throws -> ModelConsentRequirement {
        try Self.withSpeechDispatchLock {
            let document = try documentLocked() ?? ModelProvidersDocument()
            return document.consentRequirement(forProvider: document.mainProviderID(at: baseURL))
        }
    }

    /// The user agreed to send their content to this provider.
    func recordConsent(forProvider id: UUID, at date: Date = Date()) throws {
        try Self.withSpeechDispatchLock {
            guard var document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            try document.recordConsent(forProvider: id, at: date)
            try publish(document.encoded(), insertedAccount: nil)
        }
    }

    /// Saves the add-provider form (Android ModelSetupViewModel.testAndSave and
    /// saveWithoutTest through ProviderStore.connect). A typed key goes in
    /// under a new account first, then the document is published, and a
    /// replaced key's item is deleted last. The typed model becomes the main
    /// model only while none is chosen, and only with the user's consent
    /// (`consentedAt`), which is recorded in the same document.
    func addProvider(name: String, baseURL: String, sessionHeader: String?, keyRequired: Bool, key: String,
                     model: String?, tested: Bool, consentedAt: Date?) throws -> ModelProviderSaved {
        try Self.withSpeechDispatchLock {
            guard providers != nil else { throw ModelSettingsError.missingModel }
            let url = try Self.validatedAddress(baseURL)
            let model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let model, model.isEmpty || model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                throw ModelSettingsError.missingModel
            }
            let key = try Self.checkedKey(key)
            // Android providerName: a blank custom name is the host (or the preset at this address).
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? ModelProviderPresets.displayName(for: url) : trimmedName
            let draft = ModelProviderDraft(name: name, baseURL: url, sessionHeader: sessionHeader, keyRequired: keyRequired,
                                           hasNewKey: !key.isEmpty, model: model, tested: tested)
            let document = try documentLocked() ?? ModelProvidersDocument()
            let addition: ModelProviderAddition
            do { addition = try document.addingProvider(draft, consentedAt: consentedAt) }
            catch let error as ModelProvidersError { throw Self.settingsError(error) }
            let data = try addition.document.encoded()
            if let account = addition.newAccount { try credentials.insert(key, account: account.uuidString) }
            // Published only after the new item exists; the old item goes last.
            try publish(data, insertedAccount: addition.newAccount)
            return ModelProviderSaved(main: Self.main(in: addition.document), providerID: addition.provider.id,
                                      providerName: addition.provider.name, becameMain: addition.becameMain,
                                      cleanupFailed: retire(addition.retiredAccounts))
        }
    }

    /// Android ProviderStore.use(Main): makes a model of a provider the main
    /// model. A provider other than the one last agreed to needs the user's
    /// consent (`consentedAt`); without it nothing changes.
    func chooseMain(_ ref: ModelRef, typed: Bool, verified: Bool, consentedAt: Date?) throws -> SavedModelSettings {
        try Self.withSpeechDispatchLock {
            guard let document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            let next: ModelProvidersDocument
            do { next = try document.choosingMain(ref, typed: typed, verified: verified, consentedAt: consentedAt) }
            catch let error as ModelProvidersError { throw Self.settingsError(error) }
            guard let record = Self.main(in: next) else { throw ModelSettingsError.missingModel }
            try publish(next.encoded(), insertedAccount: nil)
            return record
        }
    }

    /// A model of this provider answered a test call ("重新測試").
    func markVerified(providerID: UUID, model: String) throws {
        try Self.withSpeechDispatchLock {
            guard let document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            try publish(document.markingVerified(providerID: providerID, model: model).encoded(), insertedAccount: nil)
        }
    }

    /// Android updateProviderKey: the new key under a new account, the
    /// document, then the old item. Returns the main model afterwards and
    /// whether deleting the old item failed (the sweep retries it).
    func changeKey(providerID: UUID, newKey: String) throws -> (main: SavedModelSettings?, cleanupFailed: Bool) {
        try Self.withSpeechDispatchLock {
            let key = try Self.checkedKey(newKey)
            guard !key.isEmpty else { throw ModelSettingsError.missingKey }
            guard let document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            let change = try document.changingKey(providerID: providerID)
            let data = try change.document.encoded()
            try credentials.insert(key, account: change.newAccount.uuidString)
            try publish(data, insertedAccount: change.newAccount)
            return (Self.main(in: change.document), retire(change.retiredAccount.map { [$0] } ?? []))
        }
    }

    /// The user's "能看圖" answer for one model of one provider. Returns the
    /// main model afterwards, whose answer may be this one.
    func setVision(_ sees: Bool?, providerID: UUID, model: String) throws -> SavedModelSettings? {
        try Self.withSpeechDispatchLock {
            guard var document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            try document.setVision(sees, providerID: providerID, model: model)
            try publish(document.encoded(), insertedAccount: nil)
            return Self.main(in: document)
        }
    }

    /// The user agreed, before a send, to share their content with the main
    /// model's provider: an update from before the consent existed.
    func recordConsentForMain(at date: Date = Date()) throws {
        try Self.withSpeechDispatchLock {
            guard var document = try documentLocked() else { throw ModelProvidersError.unknownProvider }
            try document.recordConsentForMain(at: date)
            try publish(document.encoded(), insertedAccount: nil)
        }
    }

    /// A provider's key for a test call; empty for a provider saved without
    /// one, and for an account sign-in, whose calls take its token instead.
    func storedKey(forProvider id: UUID) throws -> String {
        try Self.withSpeechDispatchLock {
            guard let provider = try documentLocked()?.provider(id: id) else { throw ModelProvidersError.unknownProvider }
            guard let account = provider.credentialAccount else { return "" }
            let key = try storedKey(account: account)
            return provider.kind.account == nil ? key : ""
        }
    }

    /// Providers whose Keychain item exists, read from the account names only
    /// (no key is read). Nil when the Keychain cannot list them.
    func providersWithKeys(in document: ModelProvidersDocument) -> Set<UUID>? {
        guard let accounts = (try? credentials.allAccounts()) ?? nil else { return nil }
        let stored = Set(accounts.compactMap(UUID.init(uuidString:)))
        return Set(document.providers.compactMap { provider in
            provider.credentialAccount.flatMap { stored.contains($0) ? provider.id : nil }
        })
    }

    private static func settingsError(_ error: ModelProvidersError) -> Error {
        switch error {
        case .missingKey: return ModelSettingsError.missingKey
        case .changedOrigin: return ModelSettingsError.changedOrigin
        case .tooManyProviders: return ModelSettingsError.tooManyProviders
        case .consentRequired: return ModelSettingsError.consentRequired
        case .invalidDocument, .unsupportedVersion, .tooLarge, .unknownProvider: return error
        }
    }

    /// The provider document, made from the v1 record the first time it is
    /// needed. Inside the lock. Nothing is written when there is nothing to
    /// import, and a document that cannot be read is never replaced.
    private func documentLocked() throws -> ModelProvidersDocument? {
        guard let providers else { return nil }
        if let data = try providers.read() { return try ModelProvidersDocument.decoded(from: data) }
        guard !defaults.bool(forKey: Self.migratedKey), defaults.data(forKey: Self.configurationKey) != nil else { return nil }
        let legacy: ModelLegacyRecord
        if let record = try? loadRecord(), let account = UUID(uuidString: record.credentialAccount) {
            legacy = .valid(baseURL: record.baseURL, model: record.model, credentialAccount: account,
                            seesImages: record.seesImages)
        } else { legacy = .unreadable }
        let document = ModelProvidersDocument.importing(legacy)
        try publish(document.encoded(), insertedAccount: nil)
        // Marked only once the document exists. The record stays for an older build.
        defaults.set(true, forKey: Self.migratedKey)
        return document
    }

    private static func main(in document: ModelProvidersDocument?) -> SavedModelSettings? {
        guard let document, let main = document.roles.main, let provider = document.provider(id: main.providerID) else {
            return nil
        }
        // An account's own model list says which models see images; the user's answer outranks it.
        let listed = provider.kind.account == nil ? nil : provider.models?.first { $0.id == main.model }?.vision
        return SavedModelSettings(baseURL: provider.baseURL, model: main.model,
                                  credentialAccount: provider.credentialAccount?.uuidString ?? "",
                                  seesImages: provider.visionOverrides[main.model] ?? listed, providerID: provider.id,
                                  sessionHeader: provider.sessionHeader, providerKind: provider.kind)
    }

    /// Advances the revision, then replaces the document. A key written for
    /// it is taken back when the document cannot be written.
    private func publish(_ data: Data, insertedAccount: UUID?) throws {
        guard let providers else { return }
        defaults.set(UUID().uuidString, forKey: Self.revisionKey)
        do { try providers.write(data) }
        catch {
            if let insertedAccount { try? credentials.remove(account: insertedAccount.uuidString) }
            throw error
        }
    }

    /// Deletes keys no longer used; returns whether any deletion failed.
    private func retire(_ accounts: [UUID]) -> Bool {
        var failed = false
        for account in accounts {
            do { try credentials.remove(account: account.uuidString) } catch { failed = true }
        }
        return failed
    }

    private func storedKey(account: UUID) throws -> String {
        guard let key = try credentials.read(account: account.uuidString), !key.isEmpty else {
            throw ModelSettingsError.missingKey
        }
        return key
    }

    private static func checkedKey(_ key: String) throws -> String {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw ModelSettingsError.invalidKey
        }
        return key
    }

    // The single v1 record: the script service, and the main model's setting
    // until its import.

    private func loadRecord() throws -> SavedModelSettings? {
        guard let data = defaults.data(forKey: Self.configurationKey) else { return nil }
        let record = try JSONDecoder().decode(SavedModelSettings.self, from: data)
        _ = try Self.validate(baseURL: record.baseURL.absoluteString, model: record.model)
        guard UUID(uuidString: record.credentialAccount) != nil else { throw ModelSettingsError.missingKey }
        return record
    }

    private func saveRecordLocked(baseURL: String, model: String, newKey: String) throws -> (record: SavedModelSettings, cleanupFailed: Bool) {
        let configuration = try Self.validate(baseURL: baseURL, model: model)
        let previous = try loadRecord()
        let newKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account: String
        if newKey.isEmpty {
            guard let previous else { throw ModelSettingsError.missingKey }
            guard ModelProviderAddress.sameOrigin(previous.baseURL, configuration.baseURL) else { throw ModelSettingsError.changedOrigin }
            _ = try key(for: previous)
            account = previous.credentialAccount
        } else {
            _ = try Self.checkedKey(newKey)
            account = UUID().uuidString
        }
        var record = SavedModelSettings(baseURL: configuration.baseURL, model: configuration.model, credentialAccount: account)
        // The image answer belongs to one endpoint and model; a new key for the same model keeps it.
        if let previous, previous.baseURL == record.baseURL, previous.model == record.model {
            record.seesImages = previous.seesImages
        }
        let data = try JSONEncoder().encode(record)
        if !newKey.isEmpty { try credentials.insert(newKey, account: account) }
        // Publish the nonsecret record only after Keychain succeeds. A new item avoids
        // associating a replacement key with the old host if interrupted during save.
        defaults.set(UUID().uuidString, forKey: Self.revisionKey)
        defaults.set(data, forKey: Self.configurationKey)
        var cleanupFailed = false
        if let previous, previous.credentialAccount != account {
            do { try credentials.remove(account: previous.credentialAccount) }
            catch { cleanupFailed = true }
        }
        return (record, cleanupFailed)
    }

    private func setRecordSeesImagesLocked(_ value: Bool?) throws -> SavedModelSettings {
        guard var record = try loadRecord() else { throw ModelSettingsError.missingModel }
        record.seesImages = value
        let data = try JSONEncoder().encode(record)
        defaults.set(UUID().uuidString, forKey: Self.revisionKey)
        defaults.set(data, forKey: Self.configurationKey)
        return record
    }
}

// MARK: - Account sign-ins (ChatGPT, xAI / Grok)

extension ModelSettingsRepository {
    /// Not secrets: this device's id at OpenAI and the client id ChatGPT
    /// registered for it (Android chatgpt-host.json). Kept in these defaults.
    static let chatGPTRegistrationKey = "model.chatgpt.registration.v1"

    private struct ChatGPTRegistration: Codable {
        var hostID: String
        var clientID: String?
    }

    /// This device's host id, made the first time and then kept, and the
    /// client id registered so far (nil until the first sign-in registers).
    func chatGPTRegistration() -> (hostID: String, clientID: String?) {
        Self.withSpeechDispatchLock {
            if let data = defaults.data(forKey: Self.chatGPTRegistrationKey),
               let saved = try? JSONDecoder().decode(ChatGPTRegistration.self, from: data), !saved.hostID.isEmpty {
                return (saved.hostID, saved.clientID.flatMap { $0.isEmpty ? nil : $0 })
            }
            let fresh = ChatGPTRegistration(hostID: ChatGPTSignIn.newHostID(), clientID: nil)
            defaults.set(try? JSONEncoder().encode(fresh), forKey: Self.chatGPTRegistrationKey)
            return (fresh.hostID, nil)
        }
    }

    /// Kept before the code is exchanged, so a failed exchange need not register again.
    func rememberChatGPTClient(_ clientID: String) {
        Self.withSpeechDispatchLock {
            let host = chatGPTRegistration().hostID
            defaults.set(try? JSONEncoder().encode(ChatGPTRegistration(hostID: host, clientID: clientID)),
                         forKey: Self.chatGPTRegistrationKey)
        }
    }

    private func forgetChatGPTClientLocked() {
        guard let data = defaults.data(forKey: Self.chatGPTRegistrationKey),
              var saved = try? JSONDecoder().decode(ChatGPTRegistration.self, from: data) else { return }
        saved.clientID = nil
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.chatGPTRegistrationKey)
    }

    /// A signed-in provider's stored sign-in, as kept in its item. Nil when the
    /// provider is gone or is not an account, or this device has no item (a
    /// restored device, which then shows it signed out).
    func accountSessionText(providerID: UUID) throws -> String? {
        try Self.withSpeechDispatchLock {
            guard let provider = try documentLocked()?.provider(id: providerID), provider.kind.account != nil,
                  let account = provider.credentialAccount else { return nil }
            return try credentials.read(account: account.uuidString)
        }
    }

    /// The stored sign-in decoded; one that cannot be read counts as none.
    func accountSession<Session: Decodable>(_ type: Session.Type, providerID: UUID) throws -> Session? {
        guard let text = try accountSessionText(providerID: providerID) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(text.utf8))
    }

    /// Android connectChatGpt and connectAccount: saves the sign-in and the
    /// models just listed (nil keeps the previous list) to the one provider of
    /// this kind. A new provider's item goes in before the document; an
    /// existing one is rewritten in place. Chooses no main model.
    func connectAccount<Session: Encodable>(_ kind: ModelAccountKind, session: Session, models: [ListedModel]?) throws -> ModelProvider {
        let text = try Self.sessionText(session)
        return try Self.withSpeechDispatchLock {
            guard providers != nil else { throw ModelSettingsError.missingModel }
            let document = try documentLocked() ?? ModelProvidersDocument()
            let connection: ModelAccountConnection
            do { connection = try document.connectingAccount(kind, models: models) }
            catch let error as ModelProvidersError { throw Self.settingsError(error) }
            let data = try connection.document.encoded()
            if connection.isNew {
                try credentials.insert(text, account: connection.account.uuidString)
                try publish(data, insertedAccount: connection.account)
            } else {
                try credentials.replace(text, account: connection.account.uuidString)
                try publish(data, insertedAccount: nil)
            }
            return connection.provider
        }
    }

    /// A refreshed sign-in, written only while the stored one still holds the
    /// tokens the refresh started from (Android saveRefreshed): a sign-out or a
    /// new sign-in meanwhile is never overwritten.
    func saveRefreshedSession<Session: ModelAccountSessionValue & Codable>(_ after: Session, replacing before: Session,
                                                                          providerID: UUID) throws {
        let text = try Self.sessionText(after)
        try Self.withSpeechDispatchLock {
            guard let provider = try documentLocked()?.provider(id: providerID), provider.kind.account != nil,
                  let account = provider.credentialAccount,
                  let stored = try credentials.read(account: account.uuidString),
                  let current = try? JSONDecoder().decode(Session.self, from: Data(stored.utf8)),
                  current.accessToken == before.accessToken, current.refreshToken == before.refreshToken else { return }
            try credentials.replace(text, account: account.uuidString)
        }
    }

    /// Signing out clears the tokens on this device only (Android
    /// signOutChatGpt and signOutAccount): the provider, its models and the
    /// roles that use it stay, and so do the account name and the ChatGPT
    /// registration. Returns the sign-in as it was, for the ChatGPT revoke.
    func signOutAccount<Session: ModelAccountSessionValue & Codable>(_ type: Session.Type, providerID: UUID) throws -> Session? {
        try Self.withSpeechDispatchLock {
            guard let provider = try documentLocked()?.provider(id: providerID), provider.kind.account != nil,
                  let account = provider.credentialAccount,
                  let stored = try credentials.read(account: account.uuidString),
                  let session = try? JSONDecoder().decode(Session.self, from: Data(stored.utf8)) else { return nil }
            try credentials.replace(try Self.sessionText(session.signedOut()), account: account.uuidString)
            return session
        }
    }

    /// The models an account lists now; the sign-in is not touched.
    func updateAccountModels(providerID: UUID, models: [ListedModel]) throws {
        try Self.withSpeechDispatchLock {
            guard var document = try documentLocked(), let index = document.providers.firstIndex(where: { $0.id == providerID }),
                  document.providers[index].kind.account != nil else { throw ModelProvidersError.unknownProvider }
            document.providers[index].models = Array(models.prefix(ModelProvidersDocument.maximumListedModels))
            try publish(document.encoded(), insertedAccount: nil)
        }
    }

    private static func sessionText<Session: Encodable>(_ session: Session) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(session), as: UTF8.self)
    }
}

/// The token gates of one repository's signed-in providers, made on first use.
final class ModelAccountGateRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [UUID: AnyObject] = [:]

    func gate<Gate: AnyObject>(for providerID: UUID, make: () -> Gate) -> Gate {
        lock.lock(); defer { lock.unlock() }
        if let existing = gates[providerID] as? Gate { return existing }
        let made = make()
        gates[providerID] = made
        return made
    }
}

/// The access tokens of this repository's account sign-ins, for
/// ModelProviderClient: read from the provider's Keychain item, refreshed five
/// minutes before they expire or after a 401, one refresh at a time per
/// provider, and the rotated pair written back in place. A sign-in that is gone
/// throws ModelAccountError.signInExpired; tokens never reach a log or a file.
final class ModelAccountTokens: ModelAccountTokenProviding, @unchecked Sendable {
    private let repository: ModelSettingsRepository
    private let chatGPT: ChatGPTAuthClient
    private let xai: XAIAuthClient

    init(repository: ModelSettingsRepository, chatGPT: ChatGPTAuthClient = ChatGPTAuthClient(), xai: XAIAuthClient = XAIAuthClient()) {
        self.repository = repository; self.chatGPT = chatGPT; self.xai = xai
    }

    func accessToken(for route: ModelAccountRoute, rejected: String?) async throws -> String {
        do {
            switch route.kind {
            case .chatGPT: return try await chatGPTGate(route.providerID).accessToken(rejected: rejected)
            case .xai: return try await xaiGate(route.providerID).accessToken(rejected: rejected)
            }
        } catch let error as ModelSettingsError {
            // A locked Keychain is not a signed-out account: say nothing about the sign-in.
            _ = error
            throw HTTPChatModelError.invalidConfiguration
        }
    }

    private func chatGPTGate(_ id: UUID) -> ModelAccountTokenGate<ChatGPTSession> {
        repository.accountGates.gate(for: id) {
            ChatGPTSignIn.tokenGate(auth: chatGPT,
                                    load: { [self] in try repository.accountSession(ChatGPTSession.self, providerID: id) },
                                    save: { [self] before, after in try repository.saveRefreshedSession(after, replacing: before, providerID: id) })
        }
    }

    private func xaiGate(_ id: UUID) -> ModelAccountTokenGate<XAISession> {
        repository.accountGates.gate(for: id) {
            xai.tokenGate(load: { [self] in try repository.accountSession(XAISession.self, providerID: id) },
                          save: { [self] before, after in try repository.saveRefreshedSession(after, replacing: before, providerID: id) })
        }
    }
}
