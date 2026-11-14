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

    // Exactly the v1 record's keys; the provider never enters that record.
    private enum CodingKeys: String, CodingKey { case baseURL, model, credentialAccount, seesImages }

    var configuration: ModelConfiguration {
        ModelConfiguration(baseURL: baseURL, model: model,
                           vision: seesImages.map { $0 ? .supported : .unsupported } ?? .unknown)
    }

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

    var errorDescription: String? {
        switch self {
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

protocol ModelCredentialStoring {
    func read(account: String) throws -> String?
    func insert(_ key: String, account: String) throws
    func remove(account: String) throws
    func removeAll() throws
    /// Every account of this service, to find keys no provider uses. Nil
    /// when this store cannot list them; nothing is swept then.
    func allAccounts() throws -> Set<String>?
}

extension ModelCredentialStoring {
    func allAccounts() throws -> Set<String>? { nil }
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
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              validRawPort(in: address),
              let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else { throw ModelSettingsError.invalidURL }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ModelSettingsError.missingModel
        }
        return ModelConfiguration(baseURL: url, model: model)
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
        guard UUID(uuidString: record.credentialAccount) != nil,
              let key = try credentials.read(account: record.credentialAccount), !key.isEmpty else {
            throw ModelSettingsError.missingKey
        }
        return key
    }

    // Every successful in-process write advances this value, including an
    // edit followed by a return to the original values. It contains no key.
    var revision: String { defaults.string(forKey: Self.revisionKey) ?? "legacy" }

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
            let account = try document.removeProvider(id: id)
            try publish(document.encoded(), insertedAccount: nil)
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

    /// Whether saving the form for this address needs the AI-sharing consent
    /// (App Review 5.1.2(i)) first: the first save ever, or a provider other
    /// than the one last agreed to. The screen that asks comes later.
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
        return SavedModelSettings(baseURL: provider.baseURL, model: main.model,
                                  credentialAccount: provider.credentialAccount?.uuidString ?? "",
                                  seesImages: provider.visionOverrides[main.model], providerID: provider.id)
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
