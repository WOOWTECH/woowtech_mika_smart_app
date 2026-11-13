import AssistantModels
import Foundation

/// The provider document: encoding, validation, the v1 import decision, the
/// settings form's save plan, removal and the consent bookkeeping. Pure
/// values only; no Keychain, file, defaults or network.
private struct Failure: Error, CustomStringConvertible { let description: String }

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

    static func main() {
        do {
            try documentRoundTripAndValidation()
            try presetsAndImportDecisions()
            try mainChangePlan()
            try removalAndOrphans()
            try consentDecisions()
            print("PASS model providers: \(count) checks; document logic only, no Keychain or files")
        } catch {
            print("FAIL model providers after \(count) checks: \(error)")
            exit(1)
        }
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
