import XCTest
@testable import AssistantPersistence

final class BotPushTests: XCTestCase {
    private func service() throws -> BotServiceRecord {
        try BotServiceRecord(name: "Dedicated iOS", address: "https://example.com")
    }
    private func discovery() -> [String: Any] {
        ["kind": "session", "via": "cookie", "scopes": ["client"], "cookieOnly": true,
         "id": "ios-session-1", "environmentId": "environment-1", "capabilities": ["woowtechIOSPush": 1],
         "woowtechIOSPush": ["devicePath": BotPushDiscovery.devicePath, "payloadVersion": "1",
             "auth": "cookie", "acceptsCookieOnly": true, "enabled": true, "ready": true]]
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    func testAndroidCapabilityDoesNotAuthorizeIOSRegistration() throws {
        var value = discovery(); value["capabilities"] = ["woowtechAndroidPush": 1]
        XCTAssertThrowsError(try BotPushDiscovery(data: data(value), service: service()))
    }
    func testIdentityBindsProfileOriginEnvironmentAndSession() throws {
        let a = try service(), b = try service()
        let first = try BotPushDiscovery(data: data(discovery()), service: a)
        XCTAssertTrue(first.ready)
        XCTAssertNotEqual(first.identity, try BotPushDiscovery(data: data(discovery()), service: b).identity)
        var value = discovery(); value["environmentId"] = "different-environment"
        XCTAssertNotEqual(first.identity, try BotPushDiscovery(data: data(value), service: a).identity)
        value = discovery(); value["id"] = "another-session"
        XCTAssertNotEqual(first.identity, try BotPushDiscovery(data: data(value), service: a).identity)
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        encoded["origin"] = "https://other.test"
        let changed = try JSONDecoder().decode(BotServiceRecord.self, from: data(encoded))
        XCTAssertNotEqual(first.identity, try BotPushDiscovery(data: data(discovery()), service: changed).identity)
    }
    func testCookieAuthAndExactDevicePathAreRequired() throws {
        for (key, value) in [("kind", "bearer"), ("via", "bearer"), ("id", "session\r\nInjected: x")] {
            var json = discovery(); json[key] = value
            XCTAssertThrowsError(try BotPushDiscovery(data: data(json), service: service()))
        }
        for path in ["https://evil.test/device", "/api/woowtech/android-push/device", "//evil.test/device"] {
            var json = discovery(), config = json["woowtechIOSPush"] as! [String: Any]
            config["devicePath"] = path; json["woowtechIOSPush"] = config
            XCTAssertThrowsError(try BotPushDiscovery(data: data(json), service: service()))
        }
    }
    func testBooleansAndVersionsAreNotCoerced() throws {
        var value = discovery(); value["capabilities"] = ["woowtechIOSPush": true]
        XCTAssertThrowsError(try BotPushDiscovery(data: data(value), service: service()))
        value = discovery(); value["cookieOnly"] = 1
        XCTAssertThrowsError(try BotPushDiscovery(data: data(value), service: service()))
        value = discovery(); var config = value["woowtechIOSPush"] as! [String: Any]
        config["ready"] = 1; value["woowtechIOSPush"] = config
        XCTAssertFalse(try BotPushDiscovery(data: data(value), service: service()).ready)
    }
    func testPendingOrWrongIdentityIsNotRegistrationAcknowledgement() throws {
        let id = UUID()
        let good: [String: Any] = ["v": 1, "serviceId": id.uuidString.lowercased(),
            "registrationId": UUID().uuidString.lowercased(), "state": "registered", "registered": true]
        XCTAssertNoThrow(try BotPushDiscovery.validateAcknowledgement(data(good), serviceID: id))
        for (key, value) in [("state", "pending"), ("serviceId", UUID().uuidString.lowercased()), ("registrationId", "invalid")] {
            var bad = good; bad[key] = value
            XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(data(bad), serviceID: id))
        }
        var bad = good; bad["registered"] = 1
        XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(data(bad), serviceID: id))
        bad = good; bad["v"] = true
        XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(data(bad), serviceID: id))
        bad = good; bad["token"] = "unrequested-field"
        XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(data(bad), serviceID: id))
    }
    func testRevocationNeedsExplicitAbsentAcknowledgement() throws {
        let absent: [String: Any] = ["v": 1, "serviceId": NSNull(), "registrationId": NSNull(), "state": "absent", "registered": false]
        XCTAssertNoThrow(try BotPushDiscovery.validateAcknowledgement(data(absent), serviceID: nil))
        var bad = absent; bad["serviceId"] = UUID().uuidString.lowercased()
        XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(data(bad), serviceID: nil))
        XCTAssertThrowsError(try BotPushDiscovery.validateAcknowledgement(Data("{\"ok\":true}".utf8), serviceID: nil))
    }
    func testRegistrationUsesSavedServiceAndBoundedOpaqueToken() throws {
        let id = UUID()
        let value = try JSONSerialization.jsonObject(with: BotPushDiscovery.registrationBody(serviceID: id, token: String(repeating: "A", count: 40))) as! [String: Any]
        XCTAssertEqual(value["serviceId"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(value["platform"] as? String, "fcm")
        for bad in ["short", String(repeating: "A", count: 4097), String(repeating: "A", count: 40) + "\n"] {
            XCTAssertThrowsError(try BotPushDiscovery.registrationBody(serviceID: id, token: bad))
        }
    }
    func testAmbiguousRegistrationSurvivesPersistenceAndDuplicatesAreRejected() throws {
        let service = try service()
        let discovery = try BotPushDiscovery(data: data(discovery()), service: service)
        let entry = BotPushRegistration(service: service, identity: discovery.identity, tokenDigest: String(repeating: "a", count: 64))
        var prefs = BotPushPreferences(); prefs.enabled = true; prefs.registrations = [entry]
        let restored = try JSONDecoder().decode(BotPushPreferences.self, from: JSONEncoder().encode(prefs))
        try restored.validate()
        XCTAssertFalse(restored.registrations[0].acknowledged)
        prefs.registrations.append(entry); XCTAssertThrowsError(try prefs.validate())
    }
}
