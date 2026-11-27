#if WOOWTECHBOT
import AssistantPersistence
import Foundation
import SwiftUI

enum BotWorkspaceScript {
    private static let template: String? = {
        guard let url = Bundle.main.url(forResource: "workspace-controls", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    static func source(dark: Bool, localizer: AppLocalizer) -> String? {
        let english = localizer.language == .english
        let config = ["skin": dark ? "midnight" : "daylight", "services": english ? "Services" : "服務", "notifications": english ? "Notifications" : "通知"]
        guard let template, let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "__WOOW_CONFIGURATION__", with: json)
    }
}
#endif
