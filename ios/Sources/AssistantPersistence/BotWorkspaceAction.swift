import Foundation

/// Presentation only. Neither action accepts a URL, credential or native command.
public enum BotWorkspaceAction: String, Equatable {
    case services, notifications
    public static func parse(_ address: String, service: BotServiceRecord, source: URL?, current: URL?,
                             mainFrame: Bool, linkActivated: Bool) -> Self? {
        guard service.enabled, mainFrame, linkActivated, let source, let current,
              service.policy.allows(source), service.policy.allows(current) else { return nil }
        switch address {
        case "woowtech-ui://services": return .services
        case "woowtech-ui://notifications": return .notifications
        default: return nil
        }
    }
}
