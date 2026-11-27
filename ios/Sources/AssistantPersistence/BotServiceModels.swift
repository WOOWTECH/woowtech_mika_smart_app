import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum BotServiceError: Error, Equatable {
    case invalidAddress, invalidName, invalidData, limit, unavailable, stale
}

/// A user-selected origin. Pairing codes, paths and credentials never become registry metadata.
public struct BotServiceOrigin: Equatable, Sendable {
    public let value: String
    public let insecureLAN: Bool
    public var url: URL { URL(string: value)! }

    public init(_ input: String, allowHTTPLAN: Bool = false) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !text.contains("\\"), let c = URLComponents(string: text),
              let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", let raw = c.host?.lowercased(),
              !raw.hasSuffix("."), !raw.contains("%"), !raw.isEmpty,
              c.port.map({ (1...65535).contains($0) }) ?? true
        else { throw BotServiceError.invalidAddress }
        let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let lan: Bool
        if host.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { throw BotServiceError.invalidAddress }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            guard !bytes.prefix(15).allSatisfy({ $0 == 0 }),
                  !(bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80),
                  !(bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255),
                  bytes[0] != 255 else { throw BotServiceError.invalidAddress }
            lan = bytes[0] & 0xfe == 0xfc
        } else if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && ($0.count == 1 || !$0.hasPrefix("0")) }),
                  parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false })
            else { throw BotServiceError.invalidAddress }
            let ip = parts.map { Int($0)! }
            guard ip[0] != 0, ip[0] != 127, ip[0] < 224,
                  !(ip[0] == 169 && ip[1] == 254) else { throw BotServiceError.invalidAddress }
            lan = ip[0] == 10 || (ip[0] == 172 && (16...31).contains(ip[1])) || (ip[0] == 192 && ip[1] == 168)
        } else {
            // WebKit accepts hexadecimal IPv4 spellings as addresses. Do not
            // let the DNS branch turn one into a loopback/metadata bypass.
            var numeric = in_addr()
            guard inet_aton(host, &numeric) == 0 else { throw BotServiceError.invalidAddress }
            guard host != "localhost", !host.hasSuffix(".localhost"), host.contains("."),
                  host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                      !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                      label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
                  }) else { throw BotServiceError.invalidAddress }
            lan = host.hasSuffix(".local")
        }
        guard scheme == "https" || (allowHTTPLAN && lan) else { throw BotServiceError.invalidAddress }
        var clean = URLComponents()
        clean.scheme = scheme; clean.host = raw
        clean.port = c.port == (scheme == "https" ? 443 : 80) ? nil : c.port
        guard let url = clean.url else { throw BotServiceError.invalidAddress }
        value = url.absoluteString; insecureLAN = scheme == "http"
    }

    public func allows(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.user == nil, c.password == nil,
              !url.absoluteString.contains("\\"), let host = c.host, let scheme = c.scheme else { return false }
        var origin = URLComponents(); origin.scheme = scheme; origin.host = host; origin.port = c.port
        return origin.string.flatMap { try? BotServiceOrigin($0, allowHTTPLAN: insecureLAN).value } == value
    }
}

public struct BotServiceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let origin: String
    public let allowHTTPLAN: Bool
    public var enabled: Bool
    public var profileID: UUID
    public var policy: BotServiceOrigin { try! BotServiceOrigin(origin, allowHTTPLAN: allowHTTPLAN) }

    public init(name: String, address: String, allowHTTPLAN: Bool = false) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validName(name) else { throw BotServiceError.invalidName }
        let origin = try BotServiceOrigin(address, allowHTTPLAN: allowHTTPLAN)
        id = UUID(); self.name = name; self.origin = origin.value
        self.allowHTTPLAN = origin.insecureLAN; enabled = true; profileID = UUID()
    }
    public static func validName(_ name: String) -> Bool {
        (1...80).contains(name.count) && name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
        !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    public func validate() throws {
        guard Self.validName(name), try BotServiceOrigin(origin, allowHTTPLAN: allowHTTPLAN).value == origin,
              profileID.uuidString != "00000000-0000-0000-0000-000000000000" else { throw BotServiceError.invalidData }
    }
}

public struct BotServiceRegistry: Codable, Equatable, Sendable {
    public private(set) var services: [BotServiceRecord] = []
    public private(set) var retiredProfiles: [UUID] = []
    public init() {}
    public func validate() throws {
        guard services.count <= 20, retiredProfiles.count <= 64,
              Set(services.map(\.id)).count == services.count,
              Set(services.map(\.profileID)).count == services.count,
              Set(retiredProfiles).count == retiredProfiles.count,
              !retiredProfiles.contains(where: { $0.uuidString == "00000000-0000-0000-0000-000000000000" }),
              Set(retiredProfiles).isDisjoint(with: services.map(\.profileID)) else { throw BotServiceError.invalidData }
        try services.forEach { try $0.validate() }
    }
    public mutating func add(_ record: BotServiceRecord) throws {
        guard services.count < 20 else { throw BotServiceError.limit }
        var next = self; next.services.append(record); try next.validate(); self = next
    }
    public mutating func setEnabled(_ id: UUID, _ enabled: Bool) throws {
        guard let i = services.firstIndex(where: { $0.id == id }) else { throw BotServiceError.stale }
        services[i].enabled = enabled
    }
    /// The host persists this snapshot before clearing a profile or publishing it.
    public mutating func retire(_ id: UUID, remove: Bool) throws -> BotServiceRecord {
        guard let old = services.first(where: { $0.id == id }) else { throw BotServiceError.stale }
        guard retiredProfiles.count < 64 else { throw BotServiceError.limit }
        var next = self
        if remove { next.services.removeAll { $0.id == id } }
        else if let i = next.services.firstIndex(where: { $0.id == id }) {
            next.services[i].profileID = UUID(); next.services[i].enabled = false
        }
        next.retiredProfiles.append(old.profileID); try next.validate(); self = next
        return old
    }
    public mutating func acknowledgeRemoval(_ profile: UUID) { retiredProfiles.removeAll { $0 == profile } }
}

/// Compatible event IDs and target fields; receipt is not proof of a remote registration.
public struct BotNotificationTarget: Equatable, Sendable {
    public let serviceID: UUID
    public let botID: String
    public let threadID: String
    public let eventID: String
    public let reason: String
    public var deduplicationKey: String { [serviceID.uuidString, botID, threadID, eventID].joined(separator: "|") }
    /// Why the service notified; `failed` is a run that ended in an error (owner 2026-11-27, as Android).
    public static let reasons: Set<String> = ["finished", "permission", "attention", "failed"]
    public init(fields: [String: String]) throws {
        guard Set(fields.keys) == ["v", "serviceId", "botId", "threadId", "eventId", "reason"], fields["v"] == "1",
              let service = fields["serviceId"].flatMap(UUID.init(uuidString:)),
              let event = fields["eventId"], Self.validID(event),
              let bot = fields["botId"], Self.validID(bot), let thread = fields["threadId"], Self.validID(thread),
              let reason = fields["reason"], Self.reasons.contains(reason)
        else { throw BotServiceError.invalidData }
        serviceID = service; eventID = event; botID = bot; threadID = thread; self.reason = reason
    }
    public static func validID(_ id: String) -> Bool {
        guard (1...128).contains(id.utf8.count), let first = id.utf8.first,
              (65...90).contains(first) || (97...122).contains(first) || (48...57).contains(first) else { return false }
        return id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [95, 46, 58, 45].contains($0) }
    }
    public func url(for service: BotServiceRecord) throws -> URL {
        guard service.id == serviceID, service.enabled else { throw BotServiceError.stale }
        var c = URLComponents(url: service.policy.url, resolvingAgainstBaseURL: false)!
        c.path = "/"; c.queryItems = [URLQueryItem(name: "thread", value: threadID), URLQueryItem(name: "bot", value: botID)]
        return c.url!
    }
}

/// A conversation's identity tile, the same data Android keeps (`BotUiProfile`). `palette` 1 is the
/// original six colours, where `face` was an expression; 2 is woowtechbot's eleven-colour palette, where
/// `face` is 0 automatic / 1 white / 2 black. Data saved before the palette change reads as 1, so no
/// conversation changes colour; the editor saves generation 2.
public struct BotConversationAvatar: Codable, Equatable, Sendable {
    public var robot = 0
    public var color = 1
    public var face = 0
    public var jpeg: Data?
    public var palette = 2
    public static let colorCount = 11
    private static let legacyColorCount = 6
    /// blue, green, orange, purple, pink, cyan (the old six) → the same hues in the eleven.
    private static let legacyToCurrent = [1, 0, 3, 4, 6, 5]
    public init() {}

    private enum CodingKeys: String, CodingKey { case robot, color, face, jpeg, palette }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        robot = try values.decodeIfPresent(Int.self, forKey: .robot) ?? 0
        face = try values.decodeIfPresent(Int.self, forKey: .face) ?? 0
        jpeg = try values.decodeIfPresent(Data.self, forKey: .jpeg)
        palette = try values.decodeIfPresent(Int.self, forKey: .palette) ?? 1
        color = try values.decodeIfPresent(Int.self, forKey: .color) ?? 0
    }

    public func validate() throws {
        guard (0...2).contains(robot), (1...2).contains(palette),
              (0..<(palette >= 2 ? Self.colorCount : Self.legacyColorCount)).contains(color), (0...2).contains(face),
              jpeg.map({ $0.count <= 512_000 && $0.count > 3 && $0.starts(with: [0xff, 0xd8, 0xff]) }) ?? true
        else { throw BotServiceError.invalidData }
    }

    /// Index into the eleven-colour palette, whichever generation this was saved with.
    public var colorIndex: Int {
        palette >= 2 ? color : Self.legacyToCurrent[min(max(color, 0), Self.legacyColorCount - 1)]
    }
    /// 0 automatic (dark ink on orange, yellow and silver, otherwise white), 1 white, 2 black.
    public var faceMode: Int { palette >= 2 ? face : 0 }
    /// The same look expressed in the current palette, for editing and saving.
    public func upgraded() -> BotConversationAvatar {
        guard palette < 2 else { return self }
        var copy = self
        copy.color = colorIndex; copy.face = 0; copy.palette = 2
        return copy
    }
    /// Still the built-in blue robot a new conversation starts with.
    public var isDefault: Bool {
        let value = upgraded()
        return value.robot == 0 && value.color == 1 && value.face == 0 && value.jpeg == nil
    }
}

public enum BotPairingLink {
    /// Only this service's short-lived, fragment-only invitation. Native code
    /// neither reads the token nor stores it; the website consumes it.
    public static func validate(_ raw: String, for origin: BotServiceOrigin) throws -> URL {
        guard (1...2048).contains(raw.utf8.count),
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !raw.contains("\\"), let c = URLComponents(string: raw), let url = c.url,
              c.scheme == "https", origin.allows(url), c.percentEncodedPath == "/pair", c.query == nil,
              let fragment = c.percentEncodedFragment, fragment.hasPrefix("code=") else { throw BotServiceError.invalidAddress }
        let code = fragment.dropFirst(5)
        guard (6...256).contains(code.utf8.count), code.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
        }) else { throw BotServiceError.invalidAddress }
        return url
    }
}
