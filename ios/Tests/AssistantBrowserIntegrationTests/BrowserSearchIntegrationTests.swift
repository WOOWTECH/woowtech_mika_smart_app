#if os(iOS) && canImport(XCTest)
import XCTest

final class BrowserSearchIntegrationTests: XCTestCase {
    @MainActor func testManualSearchEncryptionAndRealWebKit() async throws {
        let result = try await BrowserSearchAppChecks.run()
        XCTAssertGreaterThan(result["assertions"] as? Int ?? 0, 115)
        XCTAssertEqual(result["actual_default_and_selected_search_actions"] as? Int, 2)
        XCTAssertEqual(result["engine_change_navigations"] as? Int, 0)
    }

    @MainActor func testRealHashKVOAfterFailedNavigationAndClosedTabCannotReviveHandoff() async throws {
        let result = try await BrowserSearchAppChecks.runSPAHash()
        XCTAssertGreaterThanOrEqual(result["assertions"] as? Int ?? 0, 17)
        XCTAssertEqual(result["failed_navigation_policy_rejected"] as? Bool, true)
        XCTAssertEqual(result["late_failure_url_kvo"] as? Bool, true)
        XCTAssertEqual(result["late_closed_tab_url_kvo"] as? Bool, true)
    }
}
#endif
