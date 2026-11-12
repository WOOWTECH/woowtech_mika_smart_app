#if DEBUG
import Foundation

/// Test-only observations; never opens a URL or alters the handoff decision.
/// Only the fixed synthetic destination may be identified in diagnostic output.
struct BrowserExternalHandoffTrace {
    static let fixtureURL = "https://research.example.invalid/workspace-one#/docs/42"
    let enabled: Bool
    private(set) var taps = 0
    private(set) var active = false
    private(set) var workspaceAvailable = false
    private(set) var clearing = false
    private(set) var decision = "not_attempted"
    private(set) var destination = "none"
    private(set) var completion = "not_called"

    init(arguments: [String]) {
        let namespace = arguments.firstIndex(of: "-UITestNamespace")
        enabled = arguments.contains("-UITestMode")
            && arguments.contains("-UITestExternalOpenDiagnostics")
            && namespace.flatMap { arguments.indices.contains($0 + 1) ? UUID(uuidString: arguments[$0 + 1]) : nil } != nil
    }

    mutating func tapped(active: Bool, available: Bool, clearing: Bool) {
        guard enabled else { return }
        taps += 1
        self.active = active; workspaceAvailable = available; self.clearing = clearing
        decision = "pending"; destination = "none"; completion = "not_called"
    }

    mutating func rejectedByViewGuard() { if enabled { decision = "view_guard_rejected" } }
    mutating func rejectedBySessionGuard() { if enabled { decision = "session_guard_rejected" } }
    mutating func invoked(_ url: URL) {
        guard enabled else { return }
        decision = "open_url_invoked"
        destination = url.absoluteString == Self.fixtureURL ? "exact_fixture" : "other_redacted"
        completion = "pending"
    }
    mutating func completed(_ accepted: Bool) { if enabled { completion = accepted ? "accepted" : "rejected" } }

    var observation: String {
        "taps=\(taps);active=\(active ? 1 : 0);available=\(workspaceAvailable ? 1 : 0);clearing=\(clearing ? 1 : 0);decision=\(decision);destination=\(destination);completion=\(completion)"
    }
}
#endif
