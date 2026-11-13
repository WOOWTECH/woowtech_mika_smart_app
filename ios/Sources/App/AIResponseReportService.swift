import Foundation

/// This device's report store and the relay, made once (Android builds both
/// from the application Context). Reports live in Application Support, outside
/// the conversation archive, and leave the device only through the relay.
enum AIResponseReportService {
    static let shared = make(arguments: ProcessInfo.processInfo.arguments)

    static func make(arguments: [String],
                     supportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
        -> AIResponseReportDelivery {
        var folder = "personal"
        var transport: any AIResponseReportTransport = AIResponseReportURLSessionTransport()
        #if DEBUG
        // UI tests keep their reports in their own namespace and never reach the relay.
        if let scope = testScope(arguments) {
            folder = scope
            transport = AIResponseReportFixtureTransport()
        }
        #endif
        let directory = supportDirectory.appendingPathComponent("AIResponseReports", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        #if DEBUG
        if folder != "personal" && arguments.contains("-UITestResetStorage") { try? FileManager.default.removeItem(at: directory) }
        #endif
        return AIResponseReportDelivery(queue: AIResponseReportQueue(directory: directory),
                                        sender: AIResponseReportSender(endpoint: AIResponseReportSender.relayEndpoint, transport: transport))
    }

    #if DEBUG
    /// "test-<namespace>" under either UI test mode, like the conversation archive.
    static func testScope(_ arguments: [String]) -> String? {
        let modes = [("-UITestMode", "-UITestNamespace"), ("-LiveModelUITest", "-LiveModelUITestNamespace")]
        guard let (_, flag) = modes.first(where: { arguments.contains($0.0) }) else { return nil }
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let namespace = UUID(uuidString: arguments[index + 1]) else { return "test-unscoped" }
        return "test-" + namespace.uuidString
    }
    #endif
}

#if DEBUG
/// UI tests: answers as the relay does, from memory, and never opens a connection.
struct AIResponseReportFixtureTransport: AIResponseReportTransport {
    func exchange(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        switch request.httpMethod {
        case "POST":
            guard let body = request.httpBody, let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                  let id = fields["id"] as? String else { return (400, Data()) }
            return (201, try JSONSerialization.data(withJSONObject: ["id": id, "accepted": true,
                                                                     "deletion_receipt": "fixture-deletion-receipt"]))
        case "DELETE":
            return (200, try JSONSerialization.data(withJSONObject: ["id": request.url?.lastPathComponent ?? "", "deleted": true]))
        default:
            return (405, Data())
        }
    }
}
#endif
