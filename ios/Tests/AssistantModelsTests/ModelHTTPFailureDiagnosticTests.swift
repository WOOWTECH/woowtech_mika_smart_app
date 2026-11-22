import XCTest
@testable import AssistantModels

final class ModelHTTPFailureDiagnosticTests: XCTestCase {
    func testClosedClassificationAndSafeRetryAfter() throws {
        try ModelHTTPFailureDiagnosticChecks.classification()
    }
    func testSyntheticTransportWithoutRetries() async throws {
        try await ModelHTTPFailureDiagnosticChecks.transport()
    }
    func testExistingAccountSemanticsAndActualHTTPStatus() async throws {
        try await ModelHTTPFailureDiagnosticChecks.accountSemantics()
    }
}
