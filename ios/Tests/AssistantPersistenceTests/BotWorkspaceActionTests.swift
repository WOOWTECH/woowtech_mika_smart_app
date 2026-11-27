import XCTest
@testable import AssistantPersistence

final class BotWorkspaceActionTests: XCTestCase {
    func testPresentationRequiresCurrentSavedOriginAndMainFrameActivation() throws {
        let service = try BotServiceRecord(name: "Workspace", address: "https://example.com")
        let page = URL(string: "https://example.com/?thread=one")!
        func parse(source: URL? = nil, current: URL? = nil, main: Bool = true, activated: Bool = true,
                   record: BotServiceRecord? = nil) -> BotWorkspaceAction? {
            BotWorkspaceAction.parse("woowtech-ui://services", service: record ?? service,
                source: source ?? page, current: current ?? page, mainFrame: main, linkActivated: activated)
        }
        XCTAssertEqual(parse(), .services)
        XCTAssertNil(parse(main: false)); XCTAssertNil(parse(activated: false))
        for address in ["https://example.com.evil.test/", "https://example.com:444/", "http://example.com/", "about:blank"] {
            let other = URL(string: address)!
            XCTAssertNil(parse(source: other), address); XCTAssertNil(parse(current: other), address)
        }
        var disabled = service; disabled.enabled = false
        XCTAssertNil(parse(record: disabled))
        XCTAssertNil(BotWorkspaceAction.parse("woowtech-ui://services", service: service, source: nil,
            current: page, mainFrame: true, linkActivated: true))
    }
    func testTwoExactActionsCannotCarryURLsCommandsOrCredentials() throws {
        let service = try BotServiceRecord(name: "Workspace", address: "https://example.com")
        func parse(_ text: String) -> BotWorkspaceAction? {
            BotWorkspaceAction.parse(text, service: service, source: service.policy.url,
                current: service.policy.url, mainFrame: true, linkActivated: true)
        }
        XCTAssertEqual(parse("woowtech-ui://services"), .services)
        XCTAssertEqual(parse("woowtech-ui://notifications"), .notifications)
        for address in ["woowtech-ui://services/", "woowtech-ui://services?url=https://evil.test",
                        "woowtech-ui://notifications#approve", "woowtech-ui://token@services",
                        "woowtech-ui://services:443", "woowtech-ui://execute", "woowtech-ui://%73ervices",
                        "https://example.com/?action=services", "woowtech-ui://services\n"] {
            XCTAssertNil(parse(address), address)
        }
    }
}
