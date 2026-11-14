import Foundation

/// iOS keeps an App's Keychain items after the App is deleted, so a reinstall
/// would find the previous MCP endpoint and keys. The first launch of a fresh
/// install removes them; an upgrade keeps them, because its encrypted
/// conversation, learning and browser files cannot be read without their keys.
/// When in doubt, nothing is removed.
struct FreshInstallKeychainReset {
    static let markerKey = "install.keychain-checked.v1"

    enum Outcome: Equatable {
        /// An earlier launch of this install already decided; nothing is probed.
        case alreadyChecked
        /// Defaults or files of an earlier install, or a probe that failed.
        case keptExisting
        /// Nothing of an earlier install: the items were removed, then marked.
        case cleared
        /// Removal failed (for example while locked) and nothing is marked. The
        /// next launch decides again from what is there then.
        case retryNextLaunch
    }

    let hasMarker: () -> Bool
    let hasDefaults: () -> Bool
    let hasFiles: () throws -> Bool
    let removeKeychainItems: () throws -> Void
    let setMarker: () -> Void

    @discardableResult func run() -> Outcome {
        if hasMarker() { return .alreadyChecked }
        let existing: Bool
        do { existing = try hasDefaults() || hasFiles() } catch { existing = true }
        if !existing {
            // Remove before marking: an interrupted launch is decided again.
            do { try removeKeychainItems() } catch { return .retryNextLaunch }
        }
        setMarker()
        return existing ? .keptExisting : .cleared
    }

    /// A defaults domain counts when it holds anything but the marker.
    static func holdsData(_ domain: [String: Any]?) -> Bool {
        domain?.keys.contains { $0 != markerKey } ?? false
    }

    /// Only a confirmed "no such file" is absence. Any other error is thrown,
    /// so an unreadable location counts as an earlier install's.
    static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let failure as NSError where failure.domain == NSCocoaErrorDomain
            && (failure.code == NSFileNoSuchFileError || failure.code == NSFileReadNoSuchFileError) { return false }
    }

    static func hasEntries(_ url: URL) throws -> Bool {
        try exists(url) && !FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
    }

    /// UI tests (DEBUG only) keep to their own namespaced defaults suites, files
    /// and Keychain services, and -UITestResetStorage resets only those. They
    /// never probe, mark or remove the user's storage or another namespace's.
    static func isUITestLaunch(_ arguments: [String]) -> Bool {
        #if DEBUG
        return arguments.contains { $0.hasPrefix("-UITest") || $0.hasPrefix("-Live") }
        #else
        return false
        #endif
    }
}

// iOS only: the macOS check compiles the decision and probes above, never this.
#if os(iOS)
extension FreshInstallKeychainReset {
    /// Every production Keychain item: generic passwords in this App's default
    /// access group (it has no shared group), never synchronized. Removal stays
    /// service-scoped, like every other Keychain call here. A new service belongs here.
    static let services = [
        "io.woowtech.assistant.model-credentials.v1",      // model API key (ChatSession)
        "io.woowtech.assistant.mcp-endpoint.v1",           // MCP URL, access token, tool choice (MCPSettingsStore)
        "io.woowtech.assistant.skillworker.v1",            // script service key (SkillWorkerSettings)
        "io.woowtech.assistant.learning.v1.personal",      // file key (LearningStore)
        "io.woowtech.assistant.conversations.v1.personal", // file key (ConversationArchiveStore)
        "io.woowtech.assistant.browser.library.personal"]  // file key (BrowserWorkspace)
    /// The App's defaults suites besides its own domain.
    static let suites = [AppLanguagePreferences.productionSuite, VoiceChoiceStore.productionSuite,
                         "io.woowtech.assistant.appearance.v1", "io.woowtech.assistant.notifications.v1",
                         "io.woowtech.assistant.skillworker.v1"]

    /// Nil for a UI test launch. Run it before anything opens the Keychain.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard !isUITestLaunch(arguments) else { return nil }
        let defaults = UserDefaults.standard
        return Self(
            hasMarker: { defaults.bool(forKey: markerKey) },
            hasDefaults: {
                guard let app = Bundle.main.bundleIdentifier else { return true }
                return ([app] + suites).contains { holdsData(defaults.persistentDomain(forName: $0)) }
            },
            hasFiles: {
                // Every launch creates Application Support for the conversation,
                // learning and browser stores (with their vault lock files); a fresh
                // install has none. Documents is shared with Files: anything there is the user's.
                let manager = FileManager.default
                guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                      let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return true }
                return try exists(support) || hasEntries(documents)
            },
            removeKeychainItems: {
                for service in services { try KeychainModelCredentials(service: service).removeAll() }
            },
            setMarker: { defaults.set(true, forKey: markerKey) })
    }
}
#endif
