import Foundation

/// The fresh-install Keychain reset: every decision through injected probes,
/// then the real defaults and file probes on a scratch folder. Nothing here
/// reaches a Keychain, the user's defaults or an App container.
private struct Failure: Error { let message: String }
private struct Unreadable: Error {}

/// One simulated launch history: what the probes see, what the Keychain holds,
/// and the order in which the reset touched them.
private final class Install {
    var marker = false
    var defaults = false
    var files: Result<Bool, Error> = .success(false)
    var removalFails = false
    var keychain: Set<String> = ["model key", "MCP endpoint", "learning file key"]
    var events: [String] = []

    func launch() -> FreshInstallKeychainReset.Outcome {
        events = []
        return FreshInstallKeychainReset(
            hasMarker: { self.events.append("marker"); return self.marker },
            hasDefaults: { self.events.append("defaults"); return self.defaults },
            hasFiles: { self.events.append("files"); return try self.files.get() },
            removeKeychainItems: {
                self.events.append("remove")
                if self.removalFails { throw Unreadable() }
                self.keychain = []
            },
            setMarker: { self.events.append("mark"); self.marker = true }).run()
    }
}

@main enum CheckFreshInstallKeychainReset {
    typealias Reset = FreshInstallKeychainReset
    #if DEBUG
    static let config = "Debug"
    #else
    static let config = "Release"
    #endif
    static var checks = 0

    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw Failure(message: message) }
    }
    static func fails(_ operation: () throws -> Bool) -> Bool {
        do { _ = try operation(); return false } catch { return true }
    }

    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw Failure(message: "usage: <empty scratch folder>") }
            try decisions()
            try probes(in: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
            try uiTestLaunches()
            print("PASS fresh install Keychain reset (\(config)): \(checks) assertions; no Keychain or App container")
        } catch let failure as Failure {
            print("FAIL: \(failure.message)"); exit(1)
        } catch {
            print("FAIL: unexpected \(type(of: error))"); exit(1)
        }
    }

    static func decisions() throws {
        let fresh = Install()
        try check(fresh.launch() == .cleared, "a fresh install clears")
        try check(fresh.keychain.isEmpty && fresh.marker, "a fresh install removes the leftovers and marks")
        try check(fresh.events == ["marker", "defaults", "files", "remove", "mark"],
                  "a fresh install probes everything, then removes, and marks only after removing")
        fresh.keychain = ["new model key"]
        try check(fresh.launch() == .alreadyChecked, "the second launch after a reset is already checked")
        try check(fresh.events == ["marker"] && fresh.keychain == ["new model key"],
                  "the second launch probes and removes nothing; what the user saved stays")

        let defaultsOnly = Install()
        defaultsOnly.defaults = true
        try check(defaultsOnly.launch() == .keptExisting, "an upgrade with defaults only is kept")
        try check(defaultsOnly.keychain.count == 3 && defaultsOnly.marker && !defaultsOnly.events.contains("remove"),
                  "an upgrade with defaults only keeps every item and marks")

        let filesOnly = Install()
        filesOnly.files = .success(true)
        try check(filesOnly.launch() == .keptExisting, "an upgrade with data files only is kept")
        try check(filesOnly.keychain.count == 3 && filesOnly.marker && !filesOnly.events.contains("remove"),
                  "an upgrade with data files only keeps every item and marks")

        let marked = Install()
        marked.marker = true
        try check(marked.launch() == .alreadyChecked, "a marked install is already checked")
        try check(marked.events == ["marker"] && marked.keychain.count == 3,
                  "a marked install that looks empty probes and removes nothing")

        let unreadable = Install()
        unreadable.files = .failure(Unreadable())
        try check(unreadable.launch() == .keptExisting, "a file-probe error counts as an earlier install")
        try check(unreadable.keychain.count == 3 && unreadable.marker && !unreadable.events.contains("remove"),
                  "a file-probe error keeps every item")

        // A failed removal is not marked. The next launch decides from what is
        // there then: settings saved meanwhile make it an existing install.
        let locked = Install()
        locked.removalFails = true
        try check(locked.launch() == .retryNextLaunch && !locked.marker, "a failed removal leaves the marker unset")
        locked.removalFails = false
        locked.defaults = true
        try check(locked.launch() == .keptExisting && locked.keychain.count == 3 && locked.marker,
                  "after a failed removal, data saved meanwhile is never removed")
        let retried = Install()
        retried.removalFails = true
        _ = retried.launch()
        retried.removalFails = false
        try check(retried.launch() == .cleared && retried.keychain.isEmpty && retried.marker,
                  "a failed removal is retried while the install is still empty")
    }

    /// The real probes: only "no such file" is absence, and a folder that cannot
    /// be read throws, which keeps the Keychain just as an injected error does.
    static func probes(in scratch: URL) throws {
        try check(!Reset.holdsData(nil) && !Reset.holdsData([:]), "a missing or empty domain holds nothing")
        try check(!Reset.holdsData([Reset.markerKey: true]), "the marker alone is not data")
        try check(Reset.holdsData([Reset.markerKey: true, "model.configuration.v1": Data()]),
                  "a setting beside the marker is data")

        let manager = FileManager.default
        let missing = scratch.appendingPathComponent("Application Support", isDirectory: true)
        try check(!(try Reset.exists(missing)) && !(try Reset.hasEntries(missing)), "a missing folder is absent")
        let documents = scratch.appendingPathComponent("Documents", isDirectory: true)
        try manager.createDirectory(at: documents, withIntermediateDirectories: false)
        try check(try Reset.exists(documents) && !(try Reset.hasEntries(documents)), "an empty folder has no entries")
        try Data().write(to: documents.appendingPathComponent(".hidden"))
        try check(try Reset.hasEntries(documents), "a hidden file is an entry")

        guard getuid() != 0 else { return } // Permissions do not bind root.
        let locked = scratch.appendingPathComponent("Locked", isDirectory: true)
        try manager.createDirectory(at: locked.appendingPathComponent("Conversations"), withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        try check(fails { try Reset.exists(locked.appendingPathComponent("Conversations")) },
                  "a path under an unsearchable folder throws instead of reading as absent")
        try check(fails { try Reset.hasEntries(locked) }, "an unreadable folder throws instead of reading as empty")
        let install = Install()
        let outcome = FreshInstallKeychainReset(
            hasMarker: { install.marker }, hasDefaults: { false },
            hasFiles: { try Reset.exists(missing) || Reset.hasEntries(locked) },
            removeKeychainItems: { install.keychain = [] }, setMarker: { install.marker = true }).run()
        try check(outcome == .keptExisting && install.keychain.count == 3, "a real file-system error keeps every item")
    }

    /// UI tests use only their namespaces, so they never run the reset (Debug);
    /// Release has no UI-test switches, so the arguments change nothing.
    static func uiTestLaunches() throws {
        let namespace = UUID().uuidString
        let launches = [["-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage"],
                        ["-UITestNamespace", namespace], ["-UITestChatAccessibilitySize"],
                        ["-LiveModelUITest", "-LiveModelUITestNamespace", namespace, "-LiveModelUITestCleanup"],
                        ["-LiveMCPUITest"]]
        let debug = config == "Debug"
        try check(launches.allSatisfy { Reset.isUITestLaunch($0) == debug }, "UI-test launches skip the reset in Debug only")
        try check(!Reset.isUITestLaunch([]) && !Reset.isUITestLaunch(["-AppleLanguages", "(en)"]),
                  "an ordinary launch runs the reset")
    }
}
