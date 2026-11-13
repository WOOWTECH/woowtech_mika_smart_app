import AssistantModels
import Foundation

/// The provider document, the one-time v1 import, the order of Keychain
/// writes and the consent bookkeeping, through the actual
/// ModelSettingsRepository. Isolated defaults suites, a temporary folder and
/// an in-memory Keychain only: no network, no personal settings or Keychain.
private struct Failure: Error, CustomStringConvertible { let description: String }

/// Every Keychain write in order, and the main provider's account in the
/// published document at that moment.
private final class FakeKeychain: ModelCredentialStoring {
    enum Call: Hashable { case insert(String), remove(String), removeAll }
    var values: [String: String] = [:]
    var calls: [Call] = []
    var listable = true
    var failRemoval = false
    var published: () -> UUID? = { nil }
    var seen: [(call: Call, published: UUID?)] = []
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { note(.insert(account)); values[account] = key }
    func remove(account: String) throws {
        note(.remove(account))
        if failRemoval { throw Failure(description: "fixture removal failure") }
        values.removeValue(forKey: account)
    }
    func removeAll() throws { note(.removeAll); values = [:] }
    func allAccounts() throws -> Set<String>? { listable ? Set(values.keys) : nil }
    private func note(_ call: Call) { calls.append(call); seen.append((call, published())) }
}

/// A document store that can refuse reads (a locked device) or writes (a full disk).
private final class FixtureStorage: ModelProvidersStoring {
    var data: Data?
    var failReads = false, failWrites = false
    func read() throws -> Data? {
        if failReads { throw Failure(description: "fixture protected file") }
        return data
    }
    func write(_ data: Data) throws {
        if failWrites { throw Failure(description: "fixture full disk") }
        self.data = data
    }
    func remove() throws { data = nil }
}

private final class Environment {
    let suite = "woow.model-providers.check." + UUID().uuidString
    let defaults: UserDefaults
    let root: URL
    let file: ModelProvidersFile
    let keychain = FakeKeychain()
    init() throws {
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(description: "isolated defaults") }
        self.defaults = defaults
        root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-model-providers-" + UUID().uuidString)
        file = ModelProvidersFile(url: root.appendingPathComponent("ModelProviders/check/providers.json"))
        let file = self.file
        keychain.published = { (try? file.read()).flatMap { try? ModelProvidersDocument.decoded(from: $0) }?.mainProvider?.credentialAccount }
    }
    func repository(_ storage: (any ModelProvidersStoring)? = nil) -> ModelSettingsRepository {
        ModelSettingsRepository(defaults: defaults, credentials: keychain, providers: storage ?? file)
    }
    /// The single setting exactly as the v1 build stored it.
    func writeV1(_ baseURL: String, model: String, account: UUID, key: String?, seesImages: Bool? = nil) throws {
        var record = SavedModelSettings(baseURL: URL(string: baseURL)!, model: model, credentialAccount: account.uuidString)
        record.seesImages = seesImages
        defaults.set(try JSONEncoder().encode(record), forKey: ModelSettingsRepository.configurationKey)
        if let key { keychain.values[account.uuidString] = key }
    }
    var revision: String? { defaults.string(forKey: "model.configuration.revision.v1") }
    func close() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@main enum CheckModelProviders {
    static var count = 0

    static func check(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try value() else { throw Failure(description: label) }
        count += 1
    }

    static func rejects(_ label: String, _ expected: (Error) -> Bool = { _ in true }, _ body: () throws -> Void) throws {
        do { try body() } catch { try check(expected(error), label + " (wrong error: \(error))"); return }
        throw Failure(description: label + " was accepted")
    }

    fileprivate static func scenario(_ body: (Environment) throws -> Void) throws {
        let environment = try Environment()
        defer { environment.close() }
        try body(environment)
    }

    static func main() {
        do {
            try documentRoundTripAndValidation()
            try presetsAndImportDecisions()
            try mainChangePlan()
            try removalAndOrphans()
            try consentDecisions()
            try migration()
            try keychainOrder()
            try removalAndSweep()
            try identity()
            try consent()
            try providerAdditions()
            try mainModelChanges()
            try repositoryProviders()
            try consentOnSend()
            try formInput()
            print("PASS model providers: \(count) checks; isolated defaults, temporary files and an in-memory Keychain")
        } catch {
            print("FAIL model providers after \(count) checks: \(error)")
            exit(1)
        }
    }

    static func draft(_ name: String, _ url: String, key: Bool = true, keyRequired: Bool = true, model: String? = "m",
                      tested: Bool = false, header: String? = nil) -> ModelProviderDraft {
        ModelProviderDraft(name: name, baseURL: URL(string: url)!, sessionHeader: header, keyRequired: keyRequired,
                           hasNewKey: key, model: model, tested: tested)
    }

    /// The add-provider form's save (Android ProviderStore.connect) as planned.
    static func providerAdditions() throws {
        let at = Date(timeIntervalSince1970: 1_800_000_500)
        let empty = ModelProvidersDocument()
        let first = draft("OpenRouter", "https://openrouter.ai/api/v1", model: "vendor/a", tested: true)
        try check(empty.consentRequirement(forAdding: first) == .firstTime, "the first save asks first")
        try rejects("the first main model without consent", { $0 as? ModelProvidersError == .consentRequired }) {
            _ = try empty.addingProvider(first, consentedAt: nil)
        }
        let id = UUID(), account = UUID()
        let added = try empty.addingProvider(first, consentedAt: at, newProviderID: id, newAccount: account)
        try check(added.becameMain && !added.updatedExisting && added.newAccount == account && added.retiredAccounts.isEmpty
                  && added.provider.id == id && added.provider.credentialAccount == account, "first save: a new provider with its key")
        try check(added.document.roles.main == ModelRef(providerID: id, model: "vendor/a")
                  && added.document.consent == ModelConsentRecord(providerID: id, origin: "https://openrouter.ai", consentedAt: at),
                  "first save: the main model and the consent in one document")
        try check(added.provider.typedModels == ["vendor/a"] && added.provider.verifiedModels == ["vendor/a"] && !added.provider.savedUntested,
                  "tested: typed and verified, not untested")
        var document = added.document
        let go = draft("OpenCode Go", "https://opencode.ai/zen/go/v1", model: "kimi", header: "x-opencode-session")
        try check(document.consentRequirement(forAdding: go) == nil && !document.additionBecomesMain(go),
                  "another provider while a main model exists: not main, no consent")
        let second = try document.addingProvider(go, consentedAt: nil)
        try check(!second.becameMain && second.document.roles.main == document.roles.main && second.document.consent == document.consent
                  && second.provider.sessionHeader == "x-opencode-session" && second.provider.savedUntested
                  && second.provider.verifiedModels.isEmpty, "untested second provider: saved, header kept, main unchanged")
        document = second.document
        let rekeyAccount = UUID()
        let rekeyed = try document.addingProvider(draft("OpenRouter", "https://openrouter.ai/api/v1/", model: "vendor/b"),
                                                  consentedAt: nil, newAccount: rekeyAccount)
        try check(rekeyed.updatedExisting && rekeyed.provider.id == id && rekeyed.retiredAccounts == [account]
                  && rekeyed.provider.credentialAccount == rekeyAccount && rekeyed.document.providers.count == 2,
                  "same kind, address and name: the same provider, a new key retires the old item")
        try check(rekeyed.provider.typedModels == ["vendor/a", "vendor/b"] && !rekeyed.provider.savedUntested,
                  "an untested save never marks a provider that passed a test as untested")
        let kept = try document.addingProvider(draft("OpenRouter", "https://openrouter.ai/api/v1", key: false, model: nil), consentedAt: nil)
        try check(kept.updatedExisting && kept.newAccount == nil && kept.retiredAccounts.isEmpty && kept.provider.credentialAccount == account,
                  "a blank key keeps the same provider's key")
        let renamed = try document.addingProvider(draft("Relay B", "https://openrouter.ai/api/v1"), consentedAt: nil)
        try check(!renamed.updatedExisting && renamed.document.providers.count == 3, "one address under another name is another provider")
        try rejects("a preset without a key", { $0 as? ModelProvidersError == .missingKey }) {
            _ = try document.addingProvider(draft("Groq", "https://api.groq.com/openai/v1", key: false), consentedAt: nil)
        }
        let keyless = try document.addingProvider(draft("llm.example.invalid", "https://llm.example.invalid/v1", key: false, keyRequired: false),
                                                  consentedAt: nil)
        try check(keyless.provider.credentialAccount == nil && keyless.newAccount == nil, "a custom service may be saved without a key")
        try rejects("plain HTTP", { $0 as? ModelProvidersError == .invalidDocument }) {
            _ = try document.addingProvider(draft("x", "http://llm.example.invalid/v1"), consentedAt: nil)
        }
        try rejects("a model name with a line break", { $0 as? ModelProvidersError == .invalidDocument }) {
            _ = try document.addingProvider(draft("x", "https://x.example.invalid/v1", model: "a\nb"), consentedAt: nil)
        }
        try rejects("an empty name", { $0 as? ModelProvidersError == .invalidDocument }) {
            _ = try document.addingProvider(draft("  ", "https://x.example.invalid/v1"), consentedAt: nil)
        }
        var full = ModelProvidersDocument()
        full.providers = (0..<ModelProvidersDocument.maximumProviders).map { index in
            ModelProvider(name: "p\(index)", baseURL: URL(string: "https://p\(index).example.invalid/v1")!, credentialAccount: nil)
        }
        try rejects("one provider too many", { $0 as? ModelProvidersError == .tooManyProviders }) {
            _ = try full.addingProvider(draft("one more", "https://more.example.invalid/v1", model: nil), consentedAt: nil)
        }
        try check(try full.addingProvider(draft("p0", "https://p0.example.invalid/v1", model: nil), consentedAt: nil).updatedExisting,
                  "a full document still updates a provider it has")
        var withoutMain = document
        withoutMain.roles.main = nil
        let untested = draft("Groq", "https://api.groq.com/openai/v1", model: "llama")
        try check(withoutMain.consentRequirement(forAdding: untested) == .differentProvider, "a new main provider after another: asked again")
        let viaUntested = try withoutMain.addingProvider(untested, consentedAt: at)
        try check(viaUntested.becameMain && viaUntested.provider.savedUntested && viaUntested.document.consent?.providerID == viaUntested.provider.id,
                  "iOS 1b: an untested save with a typed model becomes the first main model too, after consent")
        try check(withoutMain.consentRequirement(forAdding: draft("OpenRouter", "https://openrouter.ai/api/v1", model: "x")) == nil,
                  "the provider last agreed to needs no new consent")
        try check(withoutMain.consentRequirement(forAdding: draft("Groq", "https://api.groq.com/openai/v1", model: nil)) == nil,
                  "a provider saved without a model is never main, so no consent")
        try check(ModelProviderPresets.preset(forHost: URL(string: "https://OPENROUTER.ai/other")!)?.name == "OpenRouter"
                  && ModelProviderPresets.preset(forHost: URL(string: "https://example.invalid/v1")!) == nil, "a preset on the same host")
        var reserved = document
        reserved.providers[1].sessionHeader = "Authorization"
        try rejects("a session header named like the request's own", { $0 as? ModelProvidersError == .invalidDocument }) {
            _ = try reserved.encoded()
        }
    }

    /// The main-model picker and a model's 用作 sheet.
    static func mainModelChanges() throws {
        let at = Date(timeIntervalSince1970: 1_800_001_000)
        var document = sample()
        let main = document.providers[0], go = document.providers[1]
        try check(document.consentRequirement(forMain: ModelRef(providerID: main.id, model: "typed-a")) == nil
                  && document.consentRequirement(forMain: ModelRef(providerID: go.id, model: "kimi")) == .differentProvider,
                  "the same provider needs no new consent, another one does")
        try rejects("another provider without consent", { $0 as? ModelProvidersError == .consentRequired }) {
            _ = try document.choosingMain(ModelRef(providerID: go.id, model: "kimi"), typed: true, verified: true, consentedAt: nil)
        }
        let same = try document.choosingMain(ModelRef(providerID: main.id, model: "typed-a"), typed: false, verified: false, consentedAt: nil)
        try check(same.roles.main == ModelRef(providerID: main.id, model: "typed-a") && same.consent == document.consent,
                  "another model of the same provider: no consent asked, the record kept")
        let switched = try document.choosingMain(ModelRef(providerID: go.id, model: "kimi"), typed: true, verified: true, consentedAt: at)
        let goAfter = switched.provider(id: go.id)
        try check(switched.roles.main == ModelRef(providerID: go.id, model: "kimi")
                  && switched.consent == ModelConsentRecord(providerID: go.id, origin: "https://opencode.ai", consentedAt: at)
                  && goAfter?.typedModels == ["kimi"] && goAfter?.verifiedModels == ["kimi"] && goAfter?.savedUntested == false,
                  "a typed model that passed: main, typed, verified, consent recorded")
        try rejects("a model of an unknown provider", { $0 as? ModelProvidersError == .unknownProvider }) {
            _ = try document.choosingMain(ModelRef(providerID: UUID(), model: "m"), typed: false, verified: false, consentedAt: at)
        }
        let verified = try document.markingVerified(providerID: go.id, model: "any-model")
        try check(verified.provider(id: go.id)?.savedUntested == false && verified.provider(id: go.id)?.verifiedModels == ["any-model"],
                  "a test that passed clears 'saved without a test'")
        let newAccount = UUID()
        let change = try document.changingKey(providerID: main.id, newAccount: newAccount)
        try check(change.newAccount == newAccount && change.retiredAccount == main.credentialAccount
                  && change.document.provider(id: main.id)?.credentialAccount == newAccount
                  && change.document.roles == document.roles, "a new key: a new item, the old one retired, roles unchanged")
        let keyed = try document.changingKey(providerID: go.id)
        try check(keyed.retiredAccount == nil && keyed.document.provider(id: go.id)?.credentialAccount == keyed.newAccount,
                  "a provider without a key can get one")
        try document.setVision(true, providerID: go.id, model: "kimi")
        try document.setVision(nil, providerID: main.id, model: "typed-a")
        try check(document.provider(id: go.id)?.visionOverrides == ["kimi": true]
                  && document.provider(id: main.id)?.visionOverrides == ["vendor/model-b": false], "能看圖 per model, nil forgets")
        try check(document.knownModels(of: main.id) == ["vendor/model-a", "typed-a", "typed-z", "vendor/model-b"],
                  "known models: the main one, then typed or verified, then the list")
        try check(document.knownModels(of: UUID()).isEmpty, "an unknown provider has no models")
        try check(!document.mainNeedsConsent, "the main provider was agreed to")
        document.consent = nil
        try check(document.mainNeedsConsent, "a main model never agreed to needs consent before anything is sent")
        try document.recordConsentForMain(at: at)
        try check(!document.mainNeedsConsent && document.consent?.providerID == main.id, "agreeing before a send records the main provider")
        document.roles.main = nil
        try check(!document.mainNeedsConsent, "no main model: nothing to agree to")
        try rejects("consent for a main model that does not exist", { $0 as? ModelProvidersError == .unknownProvider }) {
            try document.recordConsentForMain(at: at)
        }
    }

    /// The screens' saves through the actual repository: Keychain order,
    /// consent in the same document, and refusals that change nothing.
    static func repositoryProviders() throws {
        try scenario { env in
            let repository = env.repository()
            try rejects("the first main model without consent", { ($0 as? ModelSettingsError).map { if case .consentRequired = $0 { return true }; return false } ?? false }) {
                _ = try repository.addProvider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", sessionHeader: nil,
                                               keyRequired: true, key: "k", model: "vendor/a", tested: true, consentedAt: nil)
            }
            try check(env.keychain.calls.isEmpty && (try env.file.read()) == nil, "refused: no key written, no document")
            let at = Date(timeIntervalSince1970: 1_800_002_000)
            let saved = try repository.addProvider(name: "OpenRouter", baseURL: " https://openrouter.ai/api/v1 ", sessionHeader: nil,
                                                   keyRequired: true, key: " first-key ", model: " vendor/a ", tested: true, consentedAt: at)
            let document = try repository.document()
            let account = document?.provider(id: saved.providerID)?.credentialAccount
            try check(saved.becameMain && saved.main?.model == "vendor/a" && saved.main?.providerID == saved.providerID
                      && saved.providerName == "OpenRouter" && !saved.cleanupFailed, "saved and main")
            try check(env.keychain.calls == [.insert(account!.uuidString)] && env.keychain.seen.first?.published == nil
                      && env.keychain.values == [account!.uuidString: "first-key"], "the key is written before the document")
            try check(document?.consent?.providerID == saved.providerID && document?.consent?.consentedAt == at,
                      "the consent is in the published document")
            try check(try repository.load()?.model == "vendor/a" && (try repository.key(for: repository.load()!)) == "first-key",
                      "the main model loads with its key")
            env.keychain.calls = []
            let go = try repository.addProvider(name: "OpenCode Go", baseURL: "https://opencode.ai/zen/go/v1",
                                                sessionHeader: "x-opencode-session", keyRequired: true, key: "go-key",
                                                model: "kimi", tested: false, consentedAt: nil)
            try check(!go.becameMain && go.main?.providerID == saved.providerID, "a second provider leaves the main model")
            try rejects("switching without consent", { ($0 as? ModelSettingsError).map { if case .consentRequired = $0 { return true }; return false } ?? false }) {
                _ = try repository.chooseMain(ModelRef(providerID: go.providerID, model: "kimi"), typed: false, verified: false, consentedAt: nil)
            }
            let switched = try repository.chooseMain(ModelRef(providerID: go.providerID, model: "kimi"), typed: false, verified: false, consentedAt: at)
            try check(switched.providerID == go.providerID && switched.sessionHeader == "x-opencode-session" && switched.requiresKey,
                      "switched to OpenCode Go after consent, with its session header")
            let conversation = switched.configuration(conversation: "conversation-1")
            try check(conversation.sessionHeader?.value == "660158ec-f423-30d0-b080-4642634c1842"
                      && conversation.sessionHeader?.name == "x-opencode-session"
                      && switched.configuration(conversation: nil).sessionHeader?.value != conversation.sessionHeader?.value,
                      "a conversation's requests carry its session value; other work a fresh one")
            try check(saved.main?.configuration(conversation: "conversation-1").sessionHeader == nil, "other providers send none")
            try check(try repository.storedKey(forProvider: go.providerID) == "go-key", "the provider's key for a test call")
            env.keychain.calls = []; env.keychain.seen = []
            let goAccount = try repository.document()?.provider(id: go.providerID)?.credentialAccount
            let changed = try repository.changeKey(providerID: go.providerID, newKey: "go-key-2")
            let newAccount = try repository.document()?.provider(id: go.providerID)?.credentialAccount
            try check(env.keychain.calls == [.insert(newAccount!.uuidString), .remove(goAccount!.uuidString)] && !changed.cleanupFailed
                      && changed.main?.providerID == go.providerID && changed.main?.credentialAccount == newAccount?.uuidString,
                      "change key: the new item first, the old one last; the main model keeps its provider")
            try rejects("a blank new key") { _ = try repository.changeKey(providerID: go.providerID, newKey: "  ") }
            let vision = try repository.setVision(true, providerID: go.providerID, model: "kimi")
            try check(vision?.seesImages == true && vision?.configuration.vision == .supported, "能看圖 for the main model")
            try repository.markVerified(providerID: go.providerID, model: "kimi")
            try check(try repository.document()?.provider(id: go.providerID)?.savedUntested == false, "a passed retest is remembered")
            env.keychain.calls = []
            let keyless = try repository.addProvider(name: "", baseURL: "https://llm.example.invalid/v1", sessionHeader: nil,
                                                     keyRequired: false, key: "", model: "local", tested: false, consentedAt: nil)
            try check(keyless.providerName == "llm.example.invalid", "a blank custom name is the host")
            try check(env.keychain.calls.isEmpty && (try repository.storedKey(forProvider: keyless.providerID)) == "",
                      "a custom service without a key writes and reads no key")
            try check(repository.providersWithKeys(in: try repository.document()!) == [saved.providerID, go.providerID],
                      "which providers have their key item")
            env.keychain.listable = false
            try check(repository.providersWithKeys(in: try repository.document()!) == nil, "a Keychain that cannot list says so")
            env.keychain.listable = true
            let switchedKeyless = try repository.chooseMain(ModelRef(providerID: keyless.providerID, model: "local"), typed: false,
                                                            verified: false, consentedAt: at)
            try check(!switchedKeyless.requiresKey && (try repository.key(for: switchedKeyless)) == ""
                      && !switchedKeyless.configuration.requiresKey, "a keyless main model sends no key")
            try rejects("an address that is not HTTPS", { ($0 as? ModelSettingsError).map { if case .invalidURL = $0 { return true }; return false } ?? false }) {
                _ = try repository.addProvider(name: "x", baseURL: "http://llm.example.invalid/v1", sessionHeader: nil,
                                               keyRequired: false, key: "", model: nil, tested: false, consentedAt: nil)
            }
            try rejects("a key with a space", { ($0 as? ModelSettingsError).map { if case .invalidKey = $0 { return true }; return false } ?? false }) {
                _ = try repository.addProvider(name: "Groq", baseURL: "https://api.groq.com/openai/v1", sessionHeader: nil,
                                               keyRequired: true, key: "two words", model: nil, tested: false, consentedAt: nil)
            }
            try rejects("a preset without a key", { ($0 as? ModelSettingsError).map { if case .missingKey = $0 { return true }; return false } ?? false }) {
                _ = try repository.addProvider(name: "Groq", baseURL: "https://api.groq.com/openai/v1", sessionHeader: nil,
                                               keyRequired: true, key: "", model: nil, tested: false, consentedAt: nil)
            }
        }
        try scenario { env in
            let storage = FixtureStorage()
            let repository = env.repository(storage)
            storage.failWrites = true
            try rejects("a document that cannot be written") {
                _ = try repository.addProvider(name: "Groq", baseURL: "https://api.groq.com/openai/v1", sessionHeader: nil,
                                               keyRequired: true, key: "k", model: "llama", tested: true, consentedAt: Date())
            }
            guard case .insert(let taken)? = env.keychain.calls.first else { throw Failure(description: "no insert before the failed write") }
            try check(env.keychain.calls == [.insert(taken), .remove(taken)] && env.keychain.values.isEmpty,
                      "failed write: the new provider's key is taken back")
        }
    }

    /// An update from before the consent: the main model exists, and nothing
    /// may be sent to it until the user agrees.
    static func consentOnSend() throws {
        try scenario { env in
            let account = UUID()
            try env.writeV1("https://api.x.ai/v1", model: "grok-4", account: account, key: "k")
            let repository = env.repository()
            let imported = try repository.document()
            try check(imported?.mainNeedsConsent == true && imported?.consent == nil, "an imported setting was never agreed to")
            let at = Date(timeIntervalSince1970: 1_800_003_000)
            try repository.recordConsentForMain(at: at)
            let agreed = try repository.document()
            try check(agreed?.mainNeedsConsent == false
                      && agreed?.consent == ModelConsentRecord(providerID: account, origin: "https://api.x.ai", consentedAt: at),
                      "agreeing before the first send records the imported provider")
        }
    }

    /// The add form's rules (Android AddForm), before anything is saved.
    static func formInput() throws {
        var form = ModelProviderFormInput()
        try check(form.preset == "OpenRouter" && !form.isCustom && form.keyRequired && form.address?.absoluteString == "https://openrouter.ai/api/v1",
                  "Android's first chip is chosen")
        try check(!form.canSaveUntested && !form.canTest, "a preset needs a key")
        form.key = " sk-or "; form.model = "vendor/a"
        try check(form.canSaveUntested && form.canTest && form.providerName == "OpenRouter" && form.sessionHeader == nil
                  && form.trimmedKey == "sk-or", "a key and a model: test and save")
        let configuration = form.testConfiguration
        try check(configuration?.requiresKey == true && configuration?.model == "vendor/a" && configuration?.sessionHeader == nil,
                  "the test's request")
        form.key = "two words"
        try check(form.keyProblem == .modelSettingsInvalidKey && !form.canSaveUntested, "a key with a space is refused")
        form = ModelProviderFormInput(preset: "OpenCode Go", key: "k")
        form.model = "kimi"
        try check(form.sessionHeader == "x-opencode-session" && form.testConfiguration?.sessionHeader?.name == "x-opencode-session",
                  "OpenCode Go's test carries its session header")
        form = ModelProviderFormInput(preset: "xAI")
        try check(form.modelExample == .modelExampleGrok && ModelProviderFormInput().modelExample == .modelExampleCompat, "model examples")
        form = ModelProviderFormInput(preset: nil)
        try check(form.isCustom && !form.keyRequired && form.urlProblem == nil && form.address == nil && !form.canSaveUntested,
                  "自訂 starts without an address and without a hint")
        form.baseURL = "http://model.example.invalid/v1"
        try check(form.urlProblem == .modelURLHTTPS && !form.canSaveUntested, "HTTP is refused with the HTTPS hint")
        form.baseURL = "ftp://x"
        try check(form.urlProblem == .modelURLHTTPS, "another scheme too")
        form.baseURL = "https://me@model.example.invalid/v1"
        try check(form.urlProblem == .modelSettingsInvalidURL && form.address == nil, "a user in the address")
        form.baseURL = "https://model.example.invalid/v1?key=1"
        try check(form.urlProblem == .modelSettingsInvalidURL, "a query in the address")
        form.baseURL = " https://model.example.invalid/v1 "
        try check(form.urlProblem == nil && form.canSaveUntested && !form.canTest && form.providerName == "model.example.invalid"
                  && form.testConfiguration == nil, "a custom service: no key needed; testing needs a model; named by host")
        form.model = "local"
        try check(form.canTest && form.testConfiguration?.requiresKey == false, "a custom test without a key sends none")
        form.key = "k"
        try check(form.testConfiguration?.requiresKey == true, "with a key, the key is sent")
        form.name = String(repeating: "名", count: 40)
        try check(form.providerName.count == ModelProviderFormInput.maximumNameLength, "a custom name keeps 32 characters")
        form.name = ""
        form.baseURL = "https://opencode.ai/zen/go/v1"
        try check(form.sessionHeader == "x-opencode-session" && form.providerName == "OpenCode Go"
                  && form.suggestedPreset?.name == "OpenCode Go", "a preset's address typed by hand: its header, name and suggestion")
        form.baseURL = "https://api.x.ai/other"
        try check(form.suggestedPreset?.name == "xAI" && form.sessionHeader == nil && form.modelExample == .modelExampleGrok,
                  "another path on a preset's host: suggestion only")
        let draft = form.draft(tested: true)
        try check(draft?.name == "api.x.ai" && draft?.keyRequired == false && draft?.hasNewKey == true && draft?.model == "local"
                  && draft?.tested == true, "the draft the form saves")
        try check(ModelProviderFormInput(preset: "Groq").draft(tested: false)?.hasNewKey == false, "no key typed: none to write")
    }

    static func sample() -> ModelProvidersDocument {
        let first = UUID(), second = UUID()
        return ModelProvidersDocument(providers: [
            ModelProvider(id: first, name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                          credentialAccount: UUID(), models: [ListedModel(id: "vendor/model-a", contextTokens: 64_000, vision: true, tools: true),
                                                             ListedModel(id: "vendor/model-b")],
                          verifiedModels: ["vendor/model-a"], typedModels: ["typed-z", "typed-a"],
                          visionOverrides: ["vendor/model-b": false, "typed-a": true]),
            ModelProvider(id: second, name: "OpenCode Go", baseURL: URL(string: "https://opencode.ai/zen/go/v1")!,
                          credentialAccount: nil, models: [], sessionHeader: "x-opencode-session", savedUntested: true),
        ], roles: ModelRoles(main: ModelRef(providerID: first, model: "vendor/model-a"),
                             vision: .model(ModelRef(providerID: second, model: "any-model")), light: .sameAsMain),
           consent: ModelConsentRecord(providerID: first, origin: "https://openrouter.ai", consentedAt: Date(timeIntervalSince1970: 1_800_000_000.25)),
           legacySettings: .imported)
    }

    static func documentRoundTripAndValidation() throws {
        let document = sample()
        let data = try document.encoded()
        try check(try ModelProvidersDocument.decoded(from: data) == document, "document round trip")
        try check(try document.encoded() == data && (try ModelProvidersDocument.decoded(from: data).encoded()) == data,
                  "the same document always encodes to the same bytes")
        let text = String(decoding: data, as: UTF8.self)
        try check(text.contains(#""typedModels":["typed-a","typed-z"]"#) && text.contains(#""version":2"#), "sorted sets and version 2")
        try check(!text.contains("credentialAccount\":null") && !text.contains("savedUntested\":false"), "empty fields left out")
        try check(try ModelProvidersDocument.decoded(from: try ModelProvidersDocument().encoded()) == ModelProvidersDocument(),
                  "empty document round trip")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var copy = json; change(&copy); return try JSONSerialization.data(withJSONObject: copy)
        }
        try rejects("a later document version", { $0 as? ModelProvidersError == .unsupportedVersion }) {
            _ = try ModelProvidersDocument.decoded(from: try mutated { $0["version"] = 3 })
        }
        try rejects("garbage", { $0 as? ModelProvidersError == .invalidDocument }) {
            _ = try ModelProvidersDocument.decoded(from: Data("{\"version\":2,\"providers\":7}".utf8))
        }
        try rejects("oversized data", { $0 as? ModelProvidersError == .tooLarge }) {
            _ = try ModelProvidersDocument.decoded(from: Data(count: ModelProvidersDocument.maximumEncodedBytes + 1))
        }
        let base = sample()
        let invalid: [(String, (inout ModelProvidersDocument) -> Void)] = [
            ("plain HTTP", { $0.providers[0] = provider($0.providers[0], url: "http://openrouter.ai/api/v1") }),
            ("a query in the address", { $0.providers[0] = provider($0.providers[0], url: "https://openrouter.ai/api/v1?key=1") }),
            ("a user in the address", { $0.providers[0] = provider($0.providers[0], url: "https://me@openrouter.ai/api/v1") }),
            ("duplicate provider ids", { $0.providers[1] = ModelProvider(id: $0.providers[0].id, name: "x", baseURL: $0.providers[1].baseURL, credentialAccount: nil) }),
            ("one Keychain account for two providers", { $0.providers[1].credentialAccount = $0.providers[0].credentialAccount }),
            ("a role at a missing provider", { $0.roles.main = ModelRef(providerID: UUID(), model: "m") }),
            ("light model off", { $0.roles.light = .off }),
            ("a header that is not a token", { $0.providers[1].sessionHeader = "x-session\r\nX-Other: 1" }),
            ("a header with a space", { $0.providers[1].sessionHeader = "x session" }),
            ("a model name with a newline", { $0.providers[0].typedModels.insert("line\nbreak") }),
            ("an untrimmed model name", { $0.roles.main = ModelRef(providerID: $0.providers[0].id, model: " vendor/model-a") }),
            ("an empty provider name", { $0.providers[0].name = "  " }),
            ("a non-positive context", { $0.providers[0].models = [ListedModel(id: "m", contextTokens: 0)] }),
            ("too many providers", { document in
                document.providers += (0..<ModelProvidersDocument.maximumProviders).map { _ in
                    ModelProvider(name: "n", baseURL: URL(string: "https://example.invalid/v1")!, credentialAccount: nil)
                }
            }),
        ]
        for (label, change) in invalid {
            var copy = base; change(&copy)
            try rejects(label, { $0 as? ModelProvidersError == .invalidDocument }) { _ = try copy.encoded() }
            let raw = try JSONEncoder().encode(copy)
            try rejects(label + " on read", { $0 as? ModelProvidersError == .invalidDocument }) { _ = try ModelProvidersDocument.decoded(from: raw) }
        }
    }

    static func provider(_ old: ModelProvider, url: String) -> ModelProvider {
        ModelProvider(id: old.id, name: old.name, baseURL: URL(string: url)!, credentialAccount: old.credentialAccount)
    }

    static func presetsAndImportDecisions() throws {
        let go = ModelProviderPresets.preset(at: URL(string: "https://OpenCode.ai:443/zen/go/v1/")!)
        try check(go?.name == "OpenCode Go" && go?.sessionHeader == "x-opencode-session", "OpenCode Go preset carries its session header")
        try check(ModelProviderPresets.all.map(\.name) == ["OpenRouter", "Requesty", "OpenCode Go", "xAI", "Mistral", "Groq"],
                  "phase 1 presets")
        try check(ModelProviderPresets.all.allSatisfy { $0.name == "OpenCode Go" || $0.sessionHeader == nil }, "only OpenCode Go sends a session header")
        try check(ModelProviderPresets.displayName(for: URL(string: "https://api.anthropic.com/v1")!) == "Anthropic"
                  && ModelProviderPresets.preset(at: URL(string: "https://api.anthropic.com/v1")!) == nil, "named but not yet a chip")
        try check(ModelProviderPresets.displayName(for: URL(string: "https://llm.example.invalid:8443/v1")!) == "llm.example.invalid",
                  "unknown address is named by host")
        let account = UUID()
        let imported = ModelProvidersDocument.importing(.valid(baseURL: URL(string: "https://opencode.ai/zen/go/v1")!,
                                                                model: "kimi-k2", credentialAccount: account, seesImages: true))
        let provider = imported.providers.first
        try check(imported.providers.count == 1 && provider?.id == account && provider?.credentialAccount == account,
                  "import: provider id and Keychain account are the old account")
        try check(imported.roles == ModelRoles(main: ModelRef(providerID: account, model: "kimi-k2")) && imported.legacySettings == .imported,
                  "import: the old model is the main model")
        try check(provider?.name == "OpenCode Go" && provider?.sessionHeader == "x-opencode-session" && provider?.typedModels == ["kimi-k2"]
                  && provider?.savedUntested == true && provider?.visionOverrides == ["kimi-k2": true] && provider?.models == nil,
                  "import: preset name, typed model, untested and the vision answer")
        let blank = ModelProvidersDocument.importing(.unreadable)
        try check(blank.providers.isEmpty && blank.roles.main == nil && blank.legacySettings == .unreadable, "unreadable: no provider, flagged")
        let tooLong = ModelProvidersDocument.importing(.valid(baseURL: URL(string: "https://example.invalid/v1")!,
            model: String(repeating: "m", count: 1025), credentialAccount: UUID(), seesImages: nil))
        try check(tooLong.providers.isEmpty && tooLong.legacySettings == .unreadable, "a setting no provider can hold counts as unreadable")
    }

    /// The settings form's save as planned, before any Keychain item or file changes.
    static func mainChangePlan() throws {
        let openRouter = URL(string: "https://openrouter.ai/api/v1")!
        let firstID = UUID(), firstAccount = UUID()
        let first = try ModelProvidersDocument().replacingMain(baseURL: openRouter, model: "vendor/a", keyReplaced: true,
                                                                newProviderID: firstID, newAccount: firstAccount)
        try check(first.newAccount == firstAccount && first.keptAccount == nil && first.retiredAccounts.isEmpty
                  && first.provider.id == firstID && first.document.roles.main == ModelRef(providerID: firstID, model: "vendor/a"),
                  "first save: a new provider with a new item")
        try rejects("a first save without a key", { $0 as? ModelProvidersError == .missingKey }) {
            _ = try ModelProvidersDocument().replacingMain(baseURL: openRouter, model: "m", keyReplaced: false)
        }
        var saved = first.document
        try saved.setMainVision(true)
        let rekeyed = try saved.replacingMain(baseURL: openRouter, model: "vendor/a", keyReplaced: true)
        try check(rekeyed.provider.id == firstID && rekeyed.retiredAccounts == [firstAccount]
                  && rekeyed.provider.visionOverrides == ["vendor/a": true], "new key: same provider, old item retired, answer kept")
        let model = try saved.replacingMain(baseURL: openRouter, model: "vendor/b", keyReplaced: false)
        try check(model.keptAccount == firstAccount && model.newAccount == nil && model.provider.typedModels == ["vendor/b"]
                  && model.provider.visionOverrides.isEmpty, "blank key, new model: item kept, answer dropped")
        let movedID = UUID()
        let moved = try saved.replacingMain(baseURL: URL(string: "https://openrouter.ai/api/v2")!, model: "vendor/a",
                                            keyReplaced: false, newProviderID: movedID)
        try check(moved.provider.id == movedID && moved.provider.credentialAccount == firstAccount && moved.keptAccount == firstAccount
                  && moved.retiredAccounts.isEmpty && moved.document.providers.map(\.id) == [movedID],
                  "new path at the same origin: a new provider takes the item and the old one's place")
        try rejects("a blank key for another port", { $0 as? ModelProvidersError == .changedOrigin }) {
            _ = try saved.replacingMain(baseURL: URL(string: "https://openrouter.ai:8443/api/v1")!, model: "m", keyReplaced: false)
        }
        let go = try saved.replacingMain(baseURL: URL(string: "https://opencode.ai/zen/go/v1")!, model: "kimi", keyReplaced: true)
        try check(go.retiredAccounts == [firstAccount] && go.provider.name == "OpenCode Go"
                  && go.provider.sessionHeader == "x-opencode-session" && go.document.providers.count == 1,
                  "another provider with a new key retires the old item")
    }

    static func removalAndOrphans() throws {
        var document = sample()
        let main = document.providers[0], other = document.providers[1]
        let removed = try document.removeProvider(id: other.id)
        try check(removed == nil && document.roles.vision == .off && document.roles.main?.providerID == main.id,
                  "removing a provider: its role falls back, the main model stays")
        let used = main.credentialAccount!.uuidString, stray = UUID().uuidString
        try check(document.orphanedAccounts(among: [used, stray, "not-a-uuid", used.lowercased()]) == [stray, "not-a-uuid"],
                  "orphans: unused items and junk, never a used item in either letter case")
        let last = try document.removeProvider(id: main.id)
        try check(last == main.credentialAccount && document.roles.main == nil && document.roles.light == .sameAsMain,
                  "removing the main provider: no main model, its item to delete")
        try rejects("removing an unknown provider", { $0 as? ModelProvidersError == .unknownProvider }) {
            _ = try document.removeProvider(id: UUID())
        }
    }

    static func migration() throws {
        try scenario { env in
            let repository = env.repository()
            try check(try repository.load() == nil && (try env.file.read()) == nil && env.revision == nil
                      && env.keychain.calls.isEmpty && !env.defaults.bool(forKey: ModelSettingsRepository.migratedKey),
                      "no v1 setting: nothing imported or written")
        }
        try scenario { env in
            let account = UUID()
            try env.writeV1("https://site.invalid:000443/v1/", model: "fixture-model", account: account, key: "legacy-key", seesImages: true)
            let v1 = env.defaults.data(forKey: ModelSettingsRepository.configurationKey)
            let loaded = try env.repository().load()
            try check(loaded?.providerID == account && loaded?.credentialAccount == account.uuidString, "valid v1: provider id equals the old account")
            try check(loaded?.baseURL.absoluteString == "https://site.invalid:000443/v1/" && loaded?.model == "fixture-model",
                      "valid v1: address kept byte for byte, so saved conversations match")
            try check(loaded?.seesImages == true && loaded?.configuration.vision == .supported, "valid v1: vision answer carried")
            try check(try loaded.map { try env.repository().key(for: $0) } == "legacy-key", "valid v1: same Keychain item")
            try check(env.keychain.calls.isEmpty, "the import neither reads nor writes the Keychain")
            try check(env.defaults.data(forKey: ModelSettingsRepository.configurationKey) == v1
                      && env.defaults.bool(forKey: ModelSettingsRepository.migratedKey), "v1 record kept for one version, marked")
            let bytes = try env.file.read(), revision = env.revision
            try check(bytes != nil && revision != nil, "imported document published with a new revision")
            let again = try env.repository().load()
            try check(again?.providerID == account && (try env.file.read()) == bytes && env.revision == revision, "rerun is a no-op")
            try check(try env.repository().document()?.legacySettings == .imported, "imported flag")
        }
        for (label, raw) in [("garbage", Data("{not json".utf8)),
                             ("plain HTTP", try JSONEncoder().encode(SavedModelSettings(baseURL: URL(string: "http://site.invalid/v1")!,
                                                                                        model: "m", credentialAccount: UUID().uuidString))),
                             ("no account UUID", try JSONEncoder().encode(SavedModelSettings(baseURL: URL(string: "https://site.invalid/v1")!,
                                                                                             model: "m", credentialAccount: "not-a-uuid")))] {
            try scenario { env in
                env.defaults.set(raw, forKey: ModelSettingsRepository.configurationKey)
                let stray = UUID().uuidString; env.keychain.values[stray] = "old-key"
                let repository = env.repository()
                try check(try repository.load() == nil, "unreadable v1 (\(label)): no provider")
                let document = try repository.document()
                try check(document?.providers.isEmpty == true && document?.legacySettings == .unreadable, "unreadable v1 (\(label)): flagged for the UI")
                try check(env.defaults.data(forKey: ModelSettingsRepository.configurationKey) == raw
                          && env.defaults.bool(forKey: ModelSettingsRepository.migratedKey), "unreadable v1 (\(label)): record kept, marked")
                try check(try repository.sweepOrphanedCredentials() == 1 && env.keychain.values.isEmpty,
                          "unreadable v1 (\(label)): its old key is swept")
            }
        }
        try scenario { env in
            try env.writeV1("https://site.invalid/v1", model: "m", account: UUID(), key: "k")
            env.defaults.set(true, forKey: ModelSettingsRepository.migratedKey)
            try check(try env.repository().load() == nil && (try env.file.read()) == nil, "an imported v1 record is never imported again")
        }
        try scenario { env in
            let account = UUID()
            try env.writeV1("https://site.invalid/v1", model: "m", account: account, key: "k")
            let locked = FixtureStorage(); locked.failReads = true
            let repository = env.repository(locked)
            try rejects("a document that cannot be read") { _ = try repository.load() }
            try rejects("sweeping without a readable document") { _ = try repository.sweepOrphanedCredentials() }
            try check(locked.data == nil && !env.defaults.bool(forKey: ModelSettingsRepository.migratedKey)
                      && env.keychain.values[account.uuidString] == "k" && env.revision == nil,
                      "locked: nothing imported, marked, swept or replaced")
        }
        try scenario { env in
            let storage = ModelProvidersInDefaults(defaults: env.defaults)
            try env.writeV1("https://openrouter.ai/api/v1", model: "m", account: UUID(), key: "k")
            try check(try env.repository(storage).load()?.model == "m" && env.defaults.data(forKey: ModelSettingsRepository.providersKey) != nil,
                      "a test suite's document lives in its own defaults")
            let single = ModelSettingsRepository.singleRecord(defaults: env.defaults, credentials: env.keychain)
            env.defaults.removeObject(forKey: ModelSettingsRepository.providersKey)
            env.defaults.removeObject(forKey: ModelSettingsRepository.migratedKey)
            _ = try single.save(baseURL: "https://worker.invalid/v1", model: "mika-extract-pdf-v1", newKey: "worker-token")
            try check(try single.load()?.providerID == nil && env.defaults.data(forKey: ModelSettingsRepository.providersKey) == nil
                      && !env.defaults.bool(forKey: ModelSettingsRepository.migratedKey), "the script service keeps one record")
        }
    }

    static func keychainOrder() throws {
        try scenario { env in
            let repository = env.repository()
            try rejects("a first save without a key", { ($0 as? ModelSettingsError).map { if case .missingKey = $0 { return true }; return false } ?? false }) {
                _ = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "m", newKey: "")
            }
            let first = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "vendor/a", newKey: " first-key ")
            let firstAccount = first.record.credentialAccount
            try check(env.keychain.calls == [.insert(firstAccount)] && env.keychain.values == [firstAccount: "first-key"]
                      && env.keychain.seen.first?.published == nil, "first save: the key is written before any document")
            let provider = try repository.document()?.mainProvider
            try check(provider?.name == "OpenRouter" && provider?.typedModels == ["vendor/a"] && provider?.savedUntested == true
                      && provider?.id == first.record.providerID, "first save creates the main provider")
            _ = try repository.setSeesImages(true)
            env.keychain.calls = []; env.keychain.seen = []
            let revision = env.revision
            let replaced = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "vendor/a", newKey: "second-key")
            let second = replaced.record.credentialAccount
            try check(env.keychain.calls == [.insert(second), .remove(firstAccount)] && second != firstAccount,
                      "replace: write the new item, then delete the old one")
            try check(env.keychain.seen.map(\.published) == [UUID(uuidString: firstAccount), UUID(uuidString: second)],
                      "replace: the document still names the old item while the new one is written, the new one when the old goes")
            try check(replaced.record.providerID == first.record.providerID && replaced.record.seesImages == true
                      && env.keychain.values == [second: "second-key"] && !replaced.cleanupFailed && env.revision != revision,
                      "replace: same provider and vision answer, one key left, new revision")
            env.keychain.calls = []
            let model = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "vendor/b", newKey: "")
            try check(env.keychain.calls.isEmpty && model.record.credentialAccount == second && model.record.seesImages == nil
                      && model.record.providerID == first.record.providerID, "blank key, new model: same item, vision answer dropped")
            try check(try repository.document()?.mainProvider?.typedModels == ["vendor/b"], "the form keeps one typed model")
            let path = try repository.save(baseURL: "https://openrouter.ai/api/v2", model: "vendor/b", newKey: "")
            let document = try repository.document()
            try check(env.keychain.calls.isEmpty && path.record.credentialAccount == second && path.record.providerID != first.record.providerID
                      && document?.providers.count == 1 && document?.mainProvider?.id == path.record.providerID,
                      "blank key, new path at the same origin: a new provider takes the key and the old one's place")
            let before = try env.file.read()
            try rejects("a blank key for another host", { ($0 as? ModelSettingsError).map { if case .changedOrigin = $0 { return true }; return false } ?? false }) {
                _ = try repository.save(baseURL: "https://router.requesty.ai/v1", model: "vendor/b", newKey: "")
            }
            try rejects("a key with a space", { ($0 as? ModelSettingsError).map { if case .invalidKey = $0 { return true }; return false } ?? false }) {
                _ = try repository.save(baseURL: "https://router.requesty.ai/v1", model: "vendor/b", newKey: "two words")
            }
            try check(try env.file.read() == before && env.keychain.calls.isEmpty, "rejected saves change nothing")
            env.keychain.values[second] = nil
            try rejects("a blank key whose item is gone") { _ = try repository.save(baseURL: "https://openrouter.ai/api/v2", model: "c", newKey: "") }
        }
        try scenario { env in
            let storage = FixtureStorage()
            let repository = env.repository(storage)
            let saved = try repository.save(baseURL: "https://api.x.ai/v1", model: "grok", newKey: "first")
            storage.failWrites = true
            env.keychain.calls = []
            try rejects("a document that cannot be written") { _ = try repository.save(baseURL: "https://api.x.ai/v1", model: "grok", newKey: "next") }
            guard case .insert(let taken)? = env.keychain.calls.first else { throw Failure(description: "no insert before the failed write") }
            try check(env.keychain.calls == [.insert(taken), .remove(taken)] && env.keychain.values == [saved.record.credentialAccount: "first"],
                      "failed write: the new item is taken back and the old key stays")
            storage.failWrites = false
            env.keychain.failRemoval = true
            let next = try repository.save(baseURL: "https://api.x.ai/v1", model: "grok", newKey: "next")
            try check(next.cleanupFailed && env.keychain.values.count == 2, "failed cleanup is reported and the old item remains")
            env.keychain.failRemoval = false
            try check(try repository.sweepOrphanedCredentials() == 1 && env.keychain.values == [next.record.credentialAccount: "next"],
                      "the sweep removes what the cleanup could not")
        }
    }

    static func removalAndSweep() throws {
        try scenario { env in
            let repository = env.repository()
            let main = try repository.save(baseURL: "https://api.mistral.ai/v1", model: "mistral-large", newKey: "main-key")
            // A second provider as phase 1b will add them; the form never does.
            var document = try repository.document()!
            let otherAccount = UUID(), other = ModelProvider(name: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                                            credentialAccount: otherAccount, typedModels: ["llama"])
            document.providers.append(other)
            document.roles.vision = .model(ModelRef(providerID: other.id, model: "llama"))
            try env.file.write(document.encoded())
            env.keychain.values[otherAccount.uuidString] = "other-key"
            env.keychain.calls = []
            let revision = env.revision
            try check(try !repository.removeProvider(id: other.id), "remove one provider")
            let after = try repository.document()
            try check(env.keychain.calls == [.remove(otherAccount.uuidString)] && env.keychain.values == [main.record.credentialAccount: "main-key"],
                      "removing a provider deletes only its key")
            try check(after?.roles.vision == .off && after?.roles.main?.providerID == main.record.providerID && env.revision != revision,
                      "a role on the removed provider falls back; the main model stays")
            try rejects("removing an unknown provider", { $0 as? ModelProvidersError == .unknownProvider }) { try repository.removeProvider(id: UUID()) }
            let unused = UUID().uuidString
            env.keychain.values[unused] = "stray"; env.keychain.values["not-a-uuid"] = "junk"
            env.keychain.listable = false
            try check(try repository.sweepOrphanedCredentials() == 0 && env.keychain.values.count == 3, "a Keychain that cannot list sweeps nothing")
            env.keychain.listable = true
            env.keychain.calls = []
            try check(try repository.sweepOrphanedCredentials() == 2 && env.keychain.values == [main.record.credentialAccount: "main-key"]
                      && Set(env.keychain.calls) == [.remove(unused), .remove("not-a-uuid")], "the sweep removes exactly the unused items")
            try check(try repository.sweepOrphanedCredentials() == 0, "a second sweep finds nothing")
            try check(try !repository.removeProvider(id: main.record.providerID!) && (try repository.load()) == nil
                      && env.keychain.values.isEmpty, "removing the main provider leaves no main model")
        }
        try scenario { env in
            let account = UUID()
            try env.writeV1("https://site.invalid/v1", model: "m", account: account, key: "k")
            let repository = env.repository()
            try check(try repository.sweepOrphanedCredentials() == 0 && env.keychain.values[account.uuidString] == "k",
                      "a sweep before any load imports first and keeps the imported key")
            try repository.remove()
            try check((try env.file.read()) == nil && env.keychain.values.isEmpty && env.keychain.calls.last == .removeAll
                      && env.defaults.data(forKey: ModelSettingsRepository.configurationKey) == nil
                      && !env.defaults.bool(forKey: ModelSettingsRepository.migratedKey) && (try repository.load()) == nil,
                      "removing all settings clears the document, the keys and the v1 record")
            try check((try ModelProvidersFile(url: env.root.appendingPathComponent("absent/providers.json")).read()) == nil,
                      "a missing file reads as no document")
            try ModelProvidersFile(url: env.root.appendingPathComponent("absent/providers.json")).remove()
            try check(true, "removing a missing file succeeds")
        }
    }

    static func identity() throws {
        try scenario { env in
            let account = UUID()
            try env.writeV1("https://openrouter.ai/api/v1", model: "vendor/a", account: account, key: "k")
            let legacy = SavedModelSettings(baseURL: URL(string: "https://openrouter.ai/api/v1")!, model: "vendor/a", credentialAccount: account.uuidString)
            let repository = env.repository()
            let imported = try repository.load()!
            try check(legacy.accessIdentity == imported.accessIdentity && imported.accessIdentity?.target.providerID == account,
                      "a v1 record and its import have the same identity")
            let rekeyed = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "vendor/a", newKey: "new-key").record
            try check(rekeyed.accessIdentity?.target == imported.accessIdentity?.target, "a new key keeps the provider and model")
            try check(rekeyed.accessIdentity != imported.accessIdentity
                      && rekeyed.accessIdentity?.credentialAccount == UUID(uuidString: rekeyed.credentialAccount),
                      "a new key is a new Keychain item, so running work still stops")
            let model = try repository.save(baseURL: "https://openrouter.ai/api/v1", model: "vendor/b", newKey: "").record
            try check(model.accessIdentity?.target != rekeyed.accessIdentity?.target
                      && model.accessIdentity?.target.providerID == account, "another model is another target at the same provider")
            let moved = try repository.save(baseURL: "https://openrouter.ai/api/v2", model: "vendor/b", newKey: "").record
            try check(moved.accessIdentity?.target.providerID != account && moved.accessIdentity?.target.model == "vendor/b",
                      "another address is another provider")
        }
    }

    static func consent() throws {
        try scenario { env in
            let repository = env.repository()
            let openRouter = URL(string: "https://openrouter.ai/api/v1")!, groq = URL(string: "https://api.groq.com/openai/v1")!
            try check(try repository.consentRequirement(forSaving: openRouter) == .firstTime, "nothing saved: first time")
            let first = try repository.save(baseURL: openRouter.absoluteString, model: "vendor/a", newKey: "k").record
            try check(try repository.consentRequirement(forSaving: openRouter) == .firstTime, "a save alone records no consent")
            let consentedAt = Date(timeIntervalSince1970: 1_800_000_123.5)
            try repository.recordConsent(forProvider: first.providerID!, at: consentedAt)
            try check(try repository.document()?.consent == ModelConsentRecord(providerID: first.providerID!, origin: "https://openrouter.ai",
                                                                              consentedAt: consentedAt), "consent stored with its provider and time")
            try check(try repository.consentRequirement(forSaving: openRouter) == .alreadyGiven, "same provider: given")
            try check(try repository.consentRequirement(forSaving: groq) == .differentProvider, "another address: a different provider")
            _ = try repository.save(baseURL: openRouter.absoluteString, model: "vendor/b", newKey: "k2")
            try check(try repository.consentRequirement(forSaving: openRouter) == .alreadyGiven, "a new key or model keeps the consent")
            let switched = try repository.save(baseURL: groq.absoluteString, model: "llama", newKey: "g").record
            try check(try repository.consentRequirement(forSaving: groq) == .differentProvider, "switched without consent: still owed")
            try rejects("consent for a provider that does not exist", { $0 as? ModelProvidersError == .unknownProvider }) {
                try repository.recordConsent(forProvider: first.providerID!)
            }
            try repository.recordConsent(forProvider: switched.providerID!)
            try check(try repository.consentRequirement(forSaving: groq) == .alreadyGiven
                      && (try repository.consentRequirement(forSaving: openRouter)) == .differentProvider, "consent follows the last provider")
            try repository.remove()
            try check(try repository.consentRequirement(forSaving: groq) == .firstTime, "removing all settings forgets the consent")
        }
    }

    static func consentDecisions() throws {
        var document = sample()
        let main = document.providers[0], other = document.providers[1].id
        try check(document.consentRequirement(forProvider: main.id) == .alreadyGiven
                  && document.consentRequirement(forProvider: other) == .differentProvider
                  && document.consentRequirement(forProvider: nil) == .differentProvider, "consent: same, other and new provider")
        try check(document.mainProviderID(at: main.baseURL) == main.id
                  && document.mainProviderID(at: URL(string: "https://openrouter.ai/api/v2")!) == nil, "the form's address names its provider")
        document.consent = nil
        try check(document.consentRequirement(forProvider: main.id) == .firstTime, "no record: first time")
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        try document.recordConsent(forProvider: other, at: at)
        try check(document.consent == ModelConsentRecord(providerID: other, origin: "https://opencode.ai", consentedAt: at)
                  && document.consentRequirement(forProvider: other) == .alreadyGiven, "recording consent")
        try rejects("consent for an unknown provider", { $0 as? ModelProvidersError == .unknownProvider }) {
            try document.recordConsent(forProvider: UUID(), at: at)
        }
    }
}
