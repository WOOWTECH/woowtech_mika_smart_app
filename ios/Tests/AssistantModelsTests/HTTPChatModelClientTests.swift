import XCTest
@testable import AssistantModels

final class HTTPChatModelClientTests: XCTestCase {
    func testRequestContractAndValidation() throws {
        XCTAssertGreaterThan(try ModelClientChecks.requestContract(), 0)
    }

    func testKeylessCustomProviderAndSessionHeader() throws {
        XCTAssertGreaterThan(try ModelClientChecks.providerHeadersContract(), 0)
    }

    func testStrictIncrementalSSEParserAndBounds() throws {
        XCTAssertGreaterThan(try ModelClientChecks.parserContract(), 0)
    }

    func testCompletionTransportAndSanitizedErrorsWithoutRetries() async throws {
        let checks = try await ModelClientChecks.completionTransport()
        XCTAssertGreaterThan(checks, 0)
    }

    func testStreamingTransportAndTruncation() async throws {
        let checks = try await ModelClientChecks.streamingTransport()
        XCTAssertGreaterThan(checks, 0)
    }

    func testBoundedStreamingProducerLifecycle() async throws {
        let checks = try await ModelClientChecks.boundedStreamLifecycle()
        XCTAssertGreaterThan(checks, 0)
    }

    func testTotalDeadlineAndCancellation() async throws {
        let checks = try await ModelClientChecks.deadlinesAndCancellation()
        XCTAssertGreaterThan(checks, 0)
    }

    func testBoundedPendingOutputAndRedirectRejection() async throws {
        let checks = try await ModelClientChecks.slowConsumerAndRedirectPolicy()
        XCTAssertGreaterThan(checks, 0)
    }

    func testHeldResponseReleaseSynchronization() throws {
        XCTAssertGreaterThan(try ModelClientChecks.heldResponseReleaseSynchronization(), 0)
    }
}
