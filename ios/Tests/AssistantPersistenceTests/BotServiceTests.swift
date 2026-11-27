import XCTest
@testable import AssistantPersistence

final class BotServiceTests: XCTestCase {
    func testPairingRequiresSameHTTPSOriginAndExactFragmentShape() throws {
        let origin = try BotServiceOrigin("https://example.com")
        XCTAssertEqual(try BotPairingLink.validate("https://example.com/pair#code=abcdef_123", for: origin).host, "example.com")
        for raw in ["https://other.test/pair#code=abcdef", "http://example.com/pair#code=abcdef",
                    "https://example.com/pair?code=abcdef", "https://example.com/pair#code=abc",
                    "https://example.com/pair#code=abcdef&url=evil", "https://example.com/%70air#code=abcdef",
                    "https://user@example.com/pair#code=abcdef", "https://example.com/pair#code=abcdef%20",
                    "https://example.com/pair#code=abcdef\n"] {
            XCTAssertThrowsError(try BotPairingLink.validate(raw, for: origin), raw)
        }
    }
    func testOriginsRejectCredentialsAndAmbiguousLocalAddresses() throws {
        XCTAssertEqual(try BotServiceOrigin("https://EXAMPLE.com:443/").value, "https://example.com")
        for address in ["https://user:pass@example.com", "https://example.com/pair#code=secret", "https://example.com?token=x",
                        "https://127.0.0.1", "https://127.1", "https://2130706433", "https://169.254.169.254",
                        "https://[::1]", "https://[::ffff:127.0.0.1]", "https://localhost", "https://example.com.",
                        "https://0x7f.0.0.1", "https://0x7f000001", "https://[fe80::1]", "https://[::]",
                        "http://example.com", "http://192.168.001.2", "https://example.com\\@other.com"] {
            XCTAssertThrowsError(try BotServiceOrigin(address, allowHTTPLAN: true), address)
        }
        XCTAssertThrowsError(try BotServiceOrigin("http://192.168.2.10"))
        XCTAssertEqual(try BotServiceOrigin("http://192.168.2.10:8123", allowHTTPLAN: true).value, "http://192.168.2.10:8123")
        let policy = try BotServiceOrigin("https://example.com")
        XCTAssertTrue(policy.allows(URL(string: "https://example.com/pair#code=ephemeral")!))
        XCTAssertFalse(policy.allows(URL(string: "https://example.com.evil.test/")!))
        XCTAssertFalse(policy.allows(URL(string: "https://example.com:444/")!))
    }

    func testSameOriginProfilesAreIndependentAndRetirementSurvivesReload() throws {
        var registry = BotServiceRegistry()
        let a = try BotServiceRecord(name: "Home", address: "https://example.com")
        let b = try BotServiceRecord(name: "Work", address: "https://example.com")
        try registry.add(a); try registry.add(b)
        XCTAssertNotEqual(a.profileID, b.profileID)
        _ = try registry.retire(a.id, remove: false)
        let restored = try JSONDecoder().decode(BotServiceRegistry.self, from: JSONEncoder().encode(registry))
        try restored.validate()
        XCTAssertFalse(restored.services[0].enabled)
        XCTAssertNotEqual(restored.services[0].profileID, a.profileID)
        XCTAssertEqual(restored.services[1], b)
        XCTAssertEqual(restored.retiredProfiles, [a.profileID])
    }

    func testTargetsCannotSupplyURLsOrReconnectDisabledService() throws {
        let service = try BotServiceRecord(name: "Work", address: "https://example.com")
        let fields = ["v":"1", "serviceId":service.id.uuidString, "eventId":"event_demo_0001",
                      "botId":"bot-1", "threadId":"seed-2", "reason":"finished"]
        let target = try BotNotificationTarget(fields: fields)
        XCTAssertEqual(try target.url(for: service).absoluteString, "https://example.com/?thread=seed-2&bot=bot-1")
        var disabled = service; disabled.enabled = false
        XCTAssertThrowsError(try target.url(for: disabled))
        var bad = fields; bad["url"] = "https://evil.test"; XCTAssertThrowsError(try BotNotificationTarget(fields: bad))
        bad = fields; bad["threadId"] = "seed&bot=other"; XCTAssertThrowsError(try BotNotificationTarget(fields: bad))
        bad = fields; bad["eventId"] = "event/invalid"; XCTAssertThrowsError(try BotNotificationTarget(fields: bad))
        bad = fields; bad["threadId"] = "seed-3"
        XCTAssertNotEqual(try BotNotificationTarget(fields: bad).deduplicationKey, target.deduplicationKey)
        XCTAssertThrowsError(try target.url(for: BotServiceRecord(name: "Other", address: service.origin)))
    }

    func testInvalidSnapshotAndAvatarFailClosed() throws {
        let record = try BotServiceRecord(name: "Work", address: "https://example.com")
        var registry = BotServiceRegistry(); try registry.add(record)
        XCTAssertThrowsError(try registry.add(record))
        XCTAssertEqual(registry.services.count, 1)
        var avatar = BotConversationAvatar(); avatar.color = 11
        XCTAssertThrowsError(try avatar.validate())
        avatar.color = 10; XCTAssertNoThrow(try avatar.validate())
        avatar.palette = 1; avatar.color = 6
        XCTAssertThrowsError(try avatar.validate())
        avatar.palette = 2; avatar.color = 0; avatar.jpeg = Data("not an image".utf8)
        XCTAssertThrowsError(try avatar.validate())
    }

    /// Avatars saved before the eleven-colour palette have no `palette` key: they must read as the six
    /// original colours, keep their look when upgraded, and not count as a customised conversation.
    func testLegacyAvatarKeepsItsLookWhenUpgraded() throws {
        let legacy = try JSONDecoder().decode(BotConversationAvatar.self, from: Data(#"{"robot":2,"color":3,"face":1}"#.utf8))
        XCTAssertEqual(legacy.palette, 1)
        XCTAssertNoThrow(try legacy.validate())
        XCTAssertEqual(legacy.colorIndex, 4)      // purple stays purple
        XCTAssertEqual(legacy.faceMode, 0)        // the old expression is not a face colour
        let upgraded = legacy.upgraded()
        XCTAssertEqual(upgraded.palette, 2)
        XCTAssertEqual(upgraded.color, 4)
        XCTAssertEqual(upgraded.robot, 2)
        XCTAssertFalse(legacy.isDefault)
        let plain = try JSONDecoder().decode(BotConversationAvatar.self, from: Data("{}".utf8))
        XCTAssertTrue(plain.isDefault)            // legacy blue robot == the new default
        XCTAssertTrue(BotConversationAvatar().isDefault)
        let round = try JSONDecoder().decode(BotConversationAvatar.self, from: JSONEncoder().encode(upgraded))
        XCTAssertEqual(round, upgraded)
    }
}
