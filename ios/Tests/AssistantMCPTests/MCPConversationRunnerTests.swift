#if !MCP_SMOKE
import XCTest

final class MCPConversationRunnerTests: XCTestCase {
    func testSelectedCatalogRunsWithoutPerCallApproval() async throws {
        let count = try await MCPConversationChecks.executionWithoutApprovalAndCatalog()
        XCTAssertGreaterThan(count, 0)
    }
    func testSelectionIsTheLimitAndChangedArgumentsRunOnce() async throws {
        let count = try await MCPConversationChecks.selectionLimitsAndChangedArguments()
        XCTAssertGreaterThan(count, 0)
    }
    func testStrictCommandsUnknownToolsAndSelectedResources() async throws {
        let count = try await MCPConversationChecks.strictCommandsAndSelection()
        XCTAssertGreaterThan(count, 0)
    }
    func testToolErrorsTransportFailuresAndSizeBounds() async throws {
        let count = try await MCPConversationChecks.errorsAndBounds()
        XCTAssertGreaterThan(count, 0)
    }
    func testCallBudgetsAndRepeatedOperationsStopWithoutRetry() async throws {
        let count = try await MCPConversationChecks.budgetsAndRepeatedCalls()
        XCTAssertGreaterThan(count, 0)
    }
    func testFixedModelFailureClassificationWithoutRetryOrLostEvents() async throws {
        let count = try await MCPConversationChecks.modelFailureClassification()
        XCTAssertGreaterThan(count, 0)
    }
    func testSingleBoundedCommandCorrectionPreservesSelectionAndResults() async throws {
        let count = try await MCPConversationChecks.commandCorrection()
        XCTAssertGreaterThan(count, 0)
    }
    func testCommandCorrectionCancellationAndOriginalDeadline() async throws {
        let count = try await MCPConversationChecks.correctionCancellationAndDeadline()
        XCTAssertGreaterThan(count, 0)
    }
    func testCancellationAndDeadlineFenceLateCallbacksAndResults() async throws {
        let count = try await MCPConversationChecks.cancellationAndDeadline()
        XCTAssertGreaterThan(count, 0)
    }
    func testAuthorizedSingleCallTransportAndReadOnlyCompatibility() async throws {
        let count = try await MCPConversationChecks.singleCallTransportAPI()
        XCTAssertGreaterThan(count, 0)
    }
}
#endif
