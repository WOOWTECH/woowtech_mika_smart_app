#if DEBUG
import Foundation

/// Synthetic files and fake transport require a simulator and isolated test stores.
enum ChatAttachmentComposerUITestFixture {
    static let flag = "-UITestAttachmentComposer"
    static func valid(arguments: [String], simulator: Bool) -> Bool {
        let allowed = [flag, "-UITestMode", "-UITestNamespace", "-UITestResetStorage"]
        guard simulator, arguments.filter({ $0 == flag }).count == 1,
              arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
              arguments.filter({ $0 == "-UITestResetStorage" }).count <= 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              !arguments.contains(where: { $0.hasPrefix("-UITest") && !allowed.contains($0) }),
              let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
              let namespace = UUID(uuidString: arguments[index + 1]),
              namespace.uuidString.lowercased() == arguments[index + 1].lowercased() else { return false }
        return true
    }
    static func selected(arguments: [String] = ProcessInfo.processInfo.arguments) -> UUID? {
        guard arguments.contains(where: { $0.hasPrefix(flag) }) else { return nil }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        precondition(valid(arguments: arguments, simulator: simulator), "Invalid isolated attachment UI fixture")
        let index = arguments.firstIndex(of: "-UITestNamespace")!
        return UUID(uuidString: arguments[index + 1])!
    }
}
#endif
