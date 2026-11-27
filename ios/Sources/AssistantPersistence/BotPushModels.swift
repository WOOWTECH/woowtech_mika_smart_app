import Foundation
import CoreFoundation
import CryptoKit

/// Dedicated iOS contract. Android capability alone never authorizes an iOS registration:
/// its data-only delivery cannot provide reliable visible iOS background notifications.
public struct BotPushDiscovery: Equatable {
    public static let devicePath = "/api/woowtech/ios-push/device"
    public let sessionID: String
    public let identity: String
    public let ready: Bool

    public init(data: Data, service: BotServiceRecord) throws {
        let value = try BotPushWire.object(data)
        guard value["kind"] as? String == "session", value["via"] as? String == "cookie",
              (value["scopes"] as? [String])?.contains("client") == true,
              BotPushWire.boolean(value["cookieOnly"]) != nil,
              let session = value["id"] as? String, Self.identifier(session, limit: 512),
              let environment = value["environmentId"] as? String, Self.identifier(environment, limit: 512),
              let capabilities = value["capabilities"] as? [String: Any],
              BotPushWire.version(capabilities["woowtechIOSPush"]),
              let config = value["woowtechIOSPush"] as? [String: Any],
              config["devicePath"] as? String == Self.devicePath,
              config["payloadVersion"] as? String == "1", config["auth"] as? String == "cookie",
              BotPushWire.boolean(config["acceptsCookieOnly"]) == true else { throw BotServiceError.invalidData }
        self.sessionID = session
        self.identity = Self.identity(service: service, environment: environment, session: session)
        self.ready = BotPushWire.boolean(config["enabled"]) == true && BotPushWire.boolean(config["ready"]) == true
    }

    private static func identifier(_ value: String, limit: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= limit && value.utf8.allSatisfy { (33...126).contains($0) }
    }
    public static func identity(service: BotServiceRecord, environment: String, session: String) -> String {
        // JSON array avoids concatenation ambiguity. Digest binds the exact saved website profile.
        let bytes = try! JSONEncoder().encode([service.profileID.uuidString.lowercased(), service.origin, environment, session])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public static func registrationBody(serviceID: UUID, token: String) throws -> Data {
        guard token.utf8.count >= 20, token.utf8.count <= 4096,
              token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw BotServiceError.invalidData }
        return try JSONSerialization.data(withJSONObject: ["v": 1, "platform": "fcm",
            "serviceId": serviceID.uuidString.lowercased(), "token": token])
    }
    public static func validateAcknowledgement(_ data: Data, serviceID: UUID?) throws {
        let value = try BotPushWire.object(data)
        guard Set(value.keys) == Set(["v", "serviceId", "registrationId", "state", "registered"]),
              BotPushWire.version(value["v"]), BotPushWire.boolean(value["registered"]) == (serviceID != nil),
              value["state"] as? String == (serviceID == nil ? "absent" : "registered") else { throw BotServiceError.invalidData }
        if let serviceID {
            guard value["serviceId"] as? String == serviceID.uuidString.lowercased(),
                  let registration = value["registrationId"] as? String,
                  UUID(uuidString: registration)?.uuidString.lowercased() == registration else { throw BotServiceError.invalidData }
        } else {
            guard value["serviceId"] is NSNull, value["registrationId"] is NSNull else { throw BotServiceError.invalidData }
        }
    }
}

public struct BotPushRegistration: Codable, Equatable {
    public var service: BotServiceRecord
    public var identity: String
    public var tokenDigest: String
    /// Written BEFORE sending PUT. Only an explicit validated ACK changes this to true.
    public var acknowledged: Bool
    public init(service: BotServiceRecord, identity: String, tokenDigest: String, acknowledged: Bool = false) {
        self.service = service; self.identity = identity; self.tokenDigest = tokenDigest; self.acknowledged = acknowledged
    }
}

public struct BotPushPreferences: Codable, Equatable {
    public var enabled = false
    public var registrations: [BotPushRegistration] = []
    public init() {}
    public func validate() throws {
        guard registrations.count <= 80, Set(registrations.map(\.identity)).count == registrations.count else { throw BotServiceError.invalidData }
        for item in registrations {
            try item.service.validate()
            guard item.service.origin.hasPrefix("https://"),
                  [item.identity, item.tokenDigest].allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } })
            else { throw BotServiceError.invalidData }
        }
    }
}

private enum BotPushWire {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 65536, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BotServiceError.invalidData }
        return value
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func version(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number == 1
    }
}
