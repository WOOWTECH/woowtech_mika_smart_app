import AssistantBrowser
import AssistantSkills
import Foundation

extension AppText {
    /// Typed errors from the shared modules, in the App language. Their own
    /// errorDescription stays Traditional Chinese for the model and the logs.
    static func known(_ error: Error) -> AppText? {
        if let error = error as? SkillAuthoringError { return skillAuthoringError(error) }
        if let error = error as? SkillToolError { return skillToolError(error) }
        return nil
    }
}

extension AppLocalizer {
    /// A known error in the App language; otherwise the error's own text, then the fallback.
    func error(_ error: Error, fallback: AppText) -> String {
        if let known = AppText.known(error) { return text(known) }
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty { return description }
        return text(fallback)
    }
}
