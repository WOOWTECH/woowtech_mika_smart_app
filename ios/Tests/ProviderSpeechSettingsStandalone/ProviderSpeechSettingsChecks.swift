import AssistantModels
import Foundation

private final class Credentials: ModelCredentialStoring {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values.removeAll() }
}

@main enum ProviderSpeechSettingsChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1
        }
        let invalid = ["https://site.invalid:/v1", "https://site.invalid:999999999999999999999999/v1",
                       "https://[::1]:/v1", "https://[::1]:999999999999999999999999/v1",
                       "https://site.invalid:0/v1", "https://site.invalid:65536/v1"]
        for raw in invalid {
            do { _ = try ModelSettingsRepository.validate(baseURL: raw, model: "fixture"); fatalError("invalid raw accepted") }
            catch ModelSettingsError.invalidURL { count += 1 }
        }
        let legal = ["https://site.invalid/v1", "https://site.invalid:443/v1", "https://site.invalid:000443/v1",
                     "https://site.invalid:1/v1", "https://site.invalid:65535/v1", "https://[::1]/v1",
                     "https://[2001:db8::1]:443/v1", "https://[::1]:000443/v1"]
        for raw in legal {
            let configuration = try ModelSettingsRepository.validate(baseURL: raw, model: "fixture")
            check(configuration.model == "fixture", "legal model address must remain usable")
        }
        let suite = "speech-settings-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = Credentials(), repository = ModelSettingsRepository(defaults: defaults, credentials: credentials)
        let first = try repository.save(baseURL: "https://site.invalid:000443/v1", model: "fixture", newKey: "synthetic")
        let storedKey = try repository.key(for: first.record)
        check(storedKey == "synthetic", "legal legacy-style setting stores credential")
        let updated = try repository.save(baseURL: "https://site.invalid:443/v1", model: "fixture", newKey: "")
        check(updated.record.credentialAccount == first.record.credentialAccount, "same-origin credential still works")
        let beforeRejectedSave = defaults.data(forKey: ModelSettingsRepository.configurationKey)
        for raw in invalid {
            do { _ = try repository.save(baseURL: raw, model: "fixture", newKey: "replacement"); fatalError("invalid save accepted") }
            catch ModelSettingsError.invalidURL { count += 1 }
            check(defaults.data(forKey: ModelSettingsRepository.configurationKey) == beforeRejectedSave,
                  "invalid save must not change existing settings")
            check(credentials.values == [first.record.credentialAccount: "synthetic"],
                  "invalid save must not alter credentials")
        }
        for raw in ["https://site.invalid:/v1", "https://site.invalid:999999999999999999999999/v1"] {
            // Simulate the exact legacy URLComponents normalization before the fix.
            guard let legacy = URLComponents(string: raw)?.url else { fatalError("fixture no longer reproduces Foundation behavior") }
            let saved = SavedModelSettings(baseURL: legacy, model: "fixture", credentialAccount: first.record.credentialAccount)
            defaults.set(try JSONEncoder().encode(saved), forKey: ModelSettingsRepository.configurationKey)
            guard let loaded = try repository.load() else { fatalError("legacy record rejected") }
            check(loaded.baseURL.absoluteString == "https://site.invalid/v1", "legacy model remains available")
            do {
                _ = try SpeechProviderEndpoint.reviewSaved(providerID: "fixture", kind: .openAICompatible,
                    rawBaseURL: raw, savedBaseURL: loaded.baseURL)
                fatalError("malformed original raw address accepted")
            } catch SpeechProviderError.invalidConfiguration { count += 1 }
            let approved = try SpeechProviderEndpoint.reviewSaved(providerID: "fixture", kind: .openAICompatible,
                rawBaseURL: "https://site.invalid/v1", savedBaseURL: loaded.baseURL)
            check(approved.baseURL.absoluteString == loaded.baseURL.absoluteString, "re-entered exact legacy destination")
        }
        print("PASS provider speech settings boundary: \(count) checks; isolated settings and synthetic credentials")
    }
}
