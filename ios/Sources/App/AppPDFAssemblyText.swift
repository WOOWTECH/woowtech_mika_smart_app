import AssistantSkills

extension AppText {
    static let pdfAssemblyErrors: [SkillPDFAssemblyError] = [
        .invalidSources, .protectedPDF, .unsupportedDocument, .serialization, .verification, .outputTooLarge,
    ]

    static func pdfAssemblyError(_ error: SkillPDFAssemblyError) -> AppText {
        switch error {
        case .invalidSources: return .pdfAssemblyErrorInvalidSources
        case .protectedPDF: return .pdfAssemblyErrorProtectedPDF
        case .unsupportedDocument: return .pdfAssemblyErrorUnsupportedDocument
        case .serialization: return .pdfAssemblyErrorSerialization
        case .verification: return .pdfAssemblyErrorVerification
        case .outputTooLarge: return .pdfAssemblyErrorOutputTooLarge
        }
    }
}
