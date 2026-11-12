import Foundation

@main enum CheckBrowserExternalHandoffTrace {
    static func main() {
        let id = UUID().uuidString
        let flags = ["-UITestMode", "-UITestNamespace", id, "-UITestExternalOpenDiagnostics"]
        for args in [[], ["-UITestMode", "-UITestExternalOpenDiagnostics"],
                     ["-UITestMode", "-UITestNamespace", "invalid", "-UITestExternalOpenDiagnostics"],
                     ["-UITestMode", "-UITestNamespace", id]] {
            var trace = BrowserExternalHandoffTrace(arguments: args)
            precondition(!trace.enabled)
            let before = trace.observation
            trace.tapped(active: true, available: true, clearing: false)
            trace.invoked(URL(string: BrowserExternalHandoffTrace.fixtureURL)!)
            trace.completed(true)
            precondition(trace.observation == before)
        }
        var trace = BrowserExternalHandoffTrace(arguments: flags)
        precondition(trace.enabled && trace.observation.contains("taps=0"))
        trace.tapped(active: false, available: true, clearing: false)
        trace.rejectedByViewGuard()
        precondition(trace.observation.contains("active=0") && trace.observation.contains("decision=view_guard_rejected"))
        trace.tapped(active: true, available: true, clearing: false)
        trace.rejectedBySessionGuard()
        precondition(trace.observation.contains("taps=2") && trace.observation.contains("decision=session_guard_rejected"))
        trace.tapped(active: true, available: true, clearing: false)
        trace.invoked(URL(string: BrowserExternalHandoffTrace.fixtureURL)!)
        precondition(trace.observation.contains("destination=exact_fixture") && trace.observation.contains("completion=pending"))
        trace.completed(true)
        precondition(trace.observation.contains("completion=accepted"))
        trace.tapped(active: true, available: true, clearing: false)
        trace.invoked(URL(string: "https://private.example.invalid/secret?token=synthetic")!)
        trace.completed(false)
        precondition(trace.observation.contains("destination=other_redacted") && trace.observation.contains("completion=rejected"))
        precondition(!trace.observation.contains("private") && !trace.observation.contains("synthetic"))
        print("External handoff trace: gate, both guards, exact fixture, completion and redaction passed")
    }
}
