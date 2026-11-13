import XCTest

final class ChatWebTaskTests: XCTestCase {
    @MainActor func testPolicyCommandsPacingAndRunner() async throws {
        XCTAssertGreaterThan(try await ChatWebTaskChecks.run(), 100)
    }
}
