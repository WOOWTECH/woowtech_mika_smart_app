import Foundation

/// The browser's download limits (docs-woowtech/BROWSER_DOWNLOADS.md).
public struct BrowserDownloadLimits: Equatable, Sendable {
    /// One file: the chat's attachment limit, so a download it can read can be attached.
    public var maximumFileBytes: Int64 = 200 * 1_048_576
    /// Every download waiting in the app, those still arriving included.
    public var maximumStoredBytes: Int64 = 500 * 1_048_576
    /// Asking or downloading at once.
    public var maximumActive = 3
    /// How long the question waits for 下載 before the download is dropped.
    public var answerTime: TimeInterval = 120
    public var maximumRedirects = 5
    /// Ended downloads still listed; the oldest leave the list first.
    public var maximumListed = 20

    public init() {}
}

public enum BrowserDownloadFailure: String, Equatable, Sendable {
    /// Over the one-file limit, before or while it arrives.
    case tooLarge
    /// The downloads waiting in the app would pass their limit.
    case storageFull
    case tooMany
    /// The connection or the site ended it; WebKit's error is not kept.
    case network
    /// The device itself is full.
    case deviceFull
    /// It went, or redirected, to an address the browser does not open.
    case unsafeAddress
    /// No answer to the question in time.
    case expired
    /// The app's download folder could not be used.
    case unavailable
}

/// One download as the question and the list show it. Only the site's name is
/// kept of where it came from: no address, query, cookie or header.
public struct BrowserDownloadItem: Identifiable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// WebKit has the request; its name and size are not known yet.
        case starting
        /// The question is up. Nothing is written into the app before 下載.
        case asking
        case downloading
        /// In the app's folder, for 存到檔案, 分享, 附加到對話 or 移除.
        case finished
        /// Saved, shared or attached; the app's copy is deleted.
        case delivered(Delivery)
        /// Stopped by the person.
        case cancelled
        case failed(BrowserDownloadFailure)

        public var isActive: Bool { self == .starting || self == .asking || self == .downloading }
    }

    public enum Delivery: String, Equatable, Sendable { case saved, shared, attached }

    public let id: UUID
    public internal(set) var fileName: String
    public internal(set) var host: String
    public internal(set) var expectedBytes: Int64?
    public internal(set) var receivedBytes: Int64 = 0
    public internal(set) var phase: Phase
    /// When the question went up; the answer time counts from here.
    public internal(set) var askedAt: Date?
    /// The finished file, in the app's folder.
    public internal(set) var fileURL: URL?

    public init(id: UUID = UUID(), fileName: String, host: String, phase: Phase = .starting) {
        self.id = id; self.fileName = fileName; self.host = host; self.phase = phase
    }

    /// The question goes up with what WebKit learned from the response.
    public mutating func ask(fileName: String, expectedBytes: Int64?, host: String, now: Date) {
        guard phase == .starting else { return }
        self.fileName = fileName; self.expectedBytes = expectedBytes; self.host = host
        askedAt = now
        phase = .asking
    }

    /// The person's answer. Only the first answer, given in time, counts:
    /// true means WebKit may now write the file into the app.
    public mutating func answer(_ allowed: Bool, now: Date, limits: BrowserDownloadLimits) -> Bool {
        guard phase == .asking else { return false }
        guard !hasExpired(now: now, limits: limits) else { phase = .failed(.expired); return false }
        phase = allowed ? .downloading : .cancelled
        return allowed
    }

    /// Ends an unanswered question once its time is up; true when it did.
    public mutating func expire(now: Date, limits: BrowserDownloadLimits) -> Bool {
        guard phase == .asking, hasExpired(now: now, limits: limits) else { return false }
        phase = .failed(.expired)
        return true
    }

    public func hasExpired(now: Date, limits: BrowserDownloadLimits) -> Bool {
        guard let askedAt else { return false }
        return now.timeIntervalSince(askedAt) >= limits.answerTime
    }
}

/// The rules every download follows, without WebKit, so the checks run them.
public enum BrowserDownloadRules {
    /// Before the question: a download that cannot fit is refused at once.
    /// `storedBytes` is what waits in the app and what the others still bring.
    public static func refusal(expectedBytes: Int64?, storedBytes: Int64, active: Int,
                               limits: BrowserDownloadLimits) -> BrowserDownloadFailure? {
        if active >= limits.maximumActive { return .tooMany }
        if let expectedBytes, expectedBytes > limits.maximumFileBytes { return .tooLarge }
        if storedBytes + max(0, expectedBytes ?? 0) > limits.maximumStoredBytes { return .storageFull }
        return nil
    }

    /// While it arrives and once it is complete, by the bytes actually received.
    public static func refusal(receivedBytes: Int64, storedBytes: Int64,
                               limits: BrowserDownloadLimits) -> BrowserDownloadFailure? {
        if receivedBytes > limits.maximumFileBytes { return .tooLarge }
        if storedBytes + receivedBytes > limits.maximumStoredBytes { return .storageFull }
        return nil
    }

    /// Content-Disposition: attachment, with or without a file name.
    public static func isAttachment(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else { return false }
        return disposition.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "attachment"
    }

    /// The site's own name for the question: the host without www.
    public static func host(of url: URL?) -> String {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return "" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// A file name from the site, made one safe path component: no separators,
    /// control or format characters, at most 120 UTF-8 bytes with the
    /// extension kept. Nothing is decoded after the cleaning.
    public static func fileName(_ suggestion: String, fallback: String = "download") -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|%").union(.controlCharacters).union(.illegalCharacters)
        var cleaned = String(String.UnicodeScalarView(suggestion.precomposedStringWithCanonicalMapping.unicodeScalars.prefix(2_048).map {
            bad.contains($0) || $0.properties.generalCategory == .format ? "_" : $0
        }))
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if cleaned.isEmpty { cleaned = fallback }
        let ext = (cleaned as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.utf8.count <= 16 ? "." + ext : ""
        let base = suffix.isEmpty ? cleaned : String(cleaned.dropLast(suffix.count))
        var prefix = ""
        for character in base {
            if prefix.utf8.count + String(character).utf8.count > 120 - suffix.utf8.count { break }
            prefix.append(character)
        }
        return (prefix.isEmpty ? fallback : prefix) + suffix
    }

    /// The device has no room left (ENOSPC), not a network failure.
    public static func isDeviceFull(_ error: Error) -> Bool {
        let failure = error as NSError
        return (failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError)
            || (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC))
    }
}
