#if !MCP_SMOKE
import XCTest

final class MCPServerCatalogTests: XCTestCase {
    func testAndroidToolNamesForSeveralServers() throws {
        XCTAssertGreaterThan(try MCPServerCatalogChecks.naming(), 0)
    }
    func testOneCatalogRoutesEachCallToItsServer() async throws {
        let count = try await MCPServerCatalogChecks.combinedRouting()
        XCTAssertGreaterThan(count, 0)
    }
    func testChatEntryStartsTheRunWithoutAnotherModelCall() async throws {
        let count = try await MCPServerCatalogChecks.chatEntry()
        XCTAssertGreaterThan(count, 0)
    }
    func testWebTaskAndSkillToolFollowTheMCPStep() async throws {
        let count = try await MCPServerCatalogChecks.handoffs()
        XCTAssertGreaterThan(count, 0)
    }
    func testLocalChangeBeforeMCPCountsTowardTheLimit() async throws {
        let count = try await MCPServerCatalogChecks.carriedLocalUse()
        XCTAssertGreaterThan(count, 0)
    }
}
#endif
