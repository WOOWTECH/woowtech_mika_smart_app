import XCTest
@testable import AssistantModels

final class ModelHTTPFailureDiagnosticTests: XCTestCase {
    func test100msCompleteDeadlinePreservesKnown429() async throws {
        try await ModelHTTPFailureDiagnosticChecks.deadlinePreserves429(streamed: false)
    }
    func test100msStreamDeadlinePreservesKnown429() async throws {
        try await ModelHTTPFailureDiagnosticChecks.deadlinePreserves429(streamed: true)
    }
    func testUnrelatedDeadlinesAndCallerCancellationStayUnchanged() async throws {
        try await ModelHTTPFailureDiagnosticChecks.deadlineAndCancellationScope()
    }
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
