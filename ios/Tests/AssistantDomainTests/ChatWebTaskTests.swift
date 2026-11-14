import XCTest

final class ChatWebTaskTests: XCTestCase {
    @MainActor func testPolicyCommandsPacingAndRunner() async throws {
        let checks = try await ChatWebTaskChecks.run()
        XCTAssertGreaterThan(checks, 100)
    }
}
