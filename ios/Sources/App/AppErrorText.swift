import AssistantBrowser
import AssistantSkills
import Foundation

extension AppText {
    /// Typed errors from the shared modules, in the App language. Their own
    /// errorDescription stays Traditional Chinese for the model and the logs.
    static func known(_ error: Error) -> AppText? {
        if let error = error as? BrowserDownloadError { return downloadError(error) }
        if let error = error as? SkillExecutionError { return skillExecutionError(error) }
        if let error = error as? SkillAuthoringError { return skillAuthoringError(error) }
        if let error = error as? SkillCatalogError { return AppLocalizer.skillCatalogError(error) }
        if let error = error as? SkillToolError { return skillToolError(error) }
        if let error = error as? DocumentQueryError { return documentQueryError(error) }
        if let error = error as? TranscriptError { return transcriptError(error) }
        if let error = error as? SkillPDFAssemblyError { return pdfAssemblyError(error) }
        if let error = error as? MultiSourceResearchError { return multiSourceError(error) }
        if error is MultiSourceResearchContextError { return .multiResearchErrorContextTooLarge }
        if let error = error as? ResearchSourceDiscoveryError { return sourceDiscoveryError(error) }
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
