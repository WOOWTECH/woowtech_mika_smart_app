import Foundation

/// Which reply a report is about. Android also keeps a run ID and answer
/// indexes for replies saved without a stable ID (AiResponseReference); every
/// reply here keeps its own UUID in the archive, so two references name the
/// same reply exactly when both parts match.
struct AIResponseReference: Hashable, Sendable {
    let conversationID: String
    let messageKey: String
}

/// One report of an AI reply, as the Play build keeps it (AiResponseReports.kt
/// at 964d7bec). It stays pending until the relay acknowledges this exact ID.
struct AIResponseReport: Equatable, Sendable {
    enum Status: String, Sendable { case queuedLocal = "queued_local", rejected, acknowledged }

    let id: String
    let reference: AIResponseReference
    let response: String
    let reason: String
    let note: String
    let createdAtMs: Int64
    var status: Status = .queuedLocal
    var attempts = 0
    var nextAttemptAtMs: Int64 = 0
    var acknowledgedAtMs: Int64?
    var deletionReceipt: String?
    var manualOnly = false
    var replacementOf: String?

    /// The relay accepts a report dated within seven days of its arrival.
    func outsideIntakeWindow(now: Int64) -> Bool {
        let window: Int64 = 7 * 24 * 60 * 60 * 1_000
        return createdAtMs < now - window || createdAtMs > now + window
    }
}

enum AIResponseReportError: Error, Equatable {
    /// A saved file could not be read at all, so it could be a report of any reply.
    case unidentified
    /// A saved report of this reply is damaged; whether it was sent is unknown.
    case damagedReference
    /// A new report for this old one already exists with different details.
    case existingManual(AIResponseReport)
    case invalid
}

/// The reports saved on this device, one JSON file each, like Android's
/// AiResponseReportQueue. A file that cannot be read keeps every automatic
/// send stopped until the user chooses to continue (fail closed).
final class AIResponseReportQueue: @unchecked Sendable {
    static let reasons = ["offensive", "unsafe", "other"]
    /// Android keeps the first 4,000 and 1,000 UTF-16 units (String.take).
    static let maximumResponse = 4_000
    static let maximumNote = 1_000

    let directory: URL
    private let clock: @Sendable () -> Int64
    private let makeID: @Sendable () -> String
    /// One lock for every queue on the device, like Android's companion lock;
    /// recursive because operations build on each other, as Kotlin's monitors allow.
    private static let lock = NSRecursiveLock()

    init(directory: URL, clock: @escaping @Sendable () -> Int64 = AIResponseReportQueue.currentTimeMs,
         makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.directory = directory; self.clock = clock; self.makeID = makeID
    }

    static let currentTimeMs: @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)) }

    /// The saved report of this reply, or a new pending one.
    func save(_ reference: AIResponseReference, response: String, reason: String, note: String,
              allowUnidentified: Bool = false) throws -> AIResponseReport {
        try locked {
            guard Self.reasons.contains(reason), !Self.isBlank(response) else { throw AIResponseReportError.invalid }
            if let existing = try find(reference, allowUnidentified: allowUnidentified) { return existing }
            let report = AIResponseReport(id: makeID(), reference: reference, response: Self.take(response, Self.maximumResponse),
                                          reason: reason, note: Self.normalizedNote(note), createdAtMs: clock())
            try write(report)
            return report
        }
    }

    func get(_ id: String, allowUnidentified: Bool = false) throws -> AIResponseReport? {
        try locked { try all(allowUnidentified: allowUnidentified).first { $0.id == id } }
    }

    /// Removes only a known report. Network deletion must be confirmed first for a sent report.
    func remove(_ id: String, allowUnidentified: Bool = false) throws -> Bool {
        try locked {
            guard let report = try get(id, allowUnidentified: allowUnidentified) else { return false }
            let target = file(for: report)
            try? FileManager.default.removeItem(at: target)
            return !FileManager.default.fileExists(atPath: target.path)
        }
    }

    /// The saved automatic report of this reply; an acknowledged one first.
    func find(_ reference: AIResponseReference, allowUnidentified: Bool = false) throws -> AIResponseReport? {
        try locked {
            let scan = try scan()
            if scan.unidentified && !allowUnidentified { throw AIResponseReportError.unidentified }
            if scan.damaged.contains(reference) { throw AIResponseReportError.damagedReference }
            let matches = scan.reports.filter { !$0.manualOnly && $0.reference == reference }
            return matches.first { $0.status == .acknowledged } ?? matches.first
        }
    }

    func recordAttempt(_ id: String, result: AIResponseReportDeliveryResult, now: Int64,
                       allowUnidentified: Bool = false) throws -> AIResponseReport {
        try locked {
            guard let old = try get(id, allowUnidentified: allowUnidentified) else { throw AIResponseReportError.invalid }
            if old.status == .acknowledged { return old }
            var updated = old
            updated.attempts += 1
            switch result {
            case .acknowledged(let receipt):
                updated.status = .acknowledged; updated.acknowledgedAtMs = now; updated.deletionReceipt = receipt
            case .rejected:
                updated.status = .rejected
            case .retryable:
                updated.nextAttemptAtMs = now + (updated.attempts == 1 ? 30_000 : 120_000)
            }
            try write(updated)
            return updated
        }
    }

    func retry(_ id: String, allowUnidentified: Bool = false) throws -> AIResponseReport {
        try locked {
            guard var report = try get(id, allowUnidentified: allowUnidentified) else { throw AIResponseReportError.invalid }
            if report.status == .acknowledged { return report }
            report.status = .queuedLocal; report.attempts = 0; report.nextAttemptAtMs = 0
            try write(report)
            return report
        }
    }

    /// A new, independent report, sent only when the user submits or retries it.
    func createManual(_ reference: AIResponseReference, response: String, reason: String, note: String,
                      replacementOf: String? = nil, now: Int64? = nil) throws -> AIResponseReport {
        try locked {
            guard Self.reasons.contains(reason), !Self.isBlank(response) else { throw AIResponseReportError.invalid }
            let report = AIResponseReport(id: makeID(), reference: reference, response: Self.take(response, Self.maximumResponse),
                                          reason: reason, note: Self.normalizedNote(note), createdAtMs: now ?? clock(),
                                          manualOnly: true, replacementOf: replacementOf)
            try write(report)
            return report
        }
    }

    /// This conversation's independent reports, newest first.
    func manualReports(conversationID: String, allowUnidentified: Bool = false) throws -> [AIResponseReport] {
        try locked {
            let scan = try scan()
            if scan.unidentified && !allowUnidentified { throw AIResponseReportError.unidentified }
            return scan.reports.filter { $0.manualOnly && $0.reference.conversationID == conversationID }.reversed()
        }
    }

    /// A new independent report pauses automatic sends of any old report of the same reply.
    func autoBlockedByManual(_ report: AIResponseReport, allowUnidentified: Bool = false) throws -> Bool {
        try locked {
            let scan = try scan()
            if scan.unidentified && !allowUnidentified { throw AIResponseReportError.unidentified }
            return scan.reports.contains { $0.manualOnly && $0.reference == report.reference }
        }
    }

    func getManual(_ id: String, allowUnidentified: Bool = false) throws -> AIResponseReport? {
        try locked {
            let scan = try scan()
            if scan.unidentified && !allowUnidentified { throw AIResponseReportError.unidentified }
            return scan.reports.first { $0.id == id && $0.manualOnly }
        }
    }

    func recordManualAttempt(_ id: String, result: AIResponseReportDeliveryResult, now: Int64,
                             allowUnidentified: Bool = false) throws -> AIResponseReport {
        try locked {
            guard let old = try getManual(id, allowUnidentified: allowUnidentified) else { throw AIResponseReportError.invalid }
            if old.status == .acknowledged { return old }
            var updated = old
            updated.attempts += 1
            switch result {
            case .acknowledged(let receipt):
                updated.status = .acknowledged; updated.acknowledgedAtMs = now; updated.deletionReceipt = receipt
            case .rejected: updated.status = .rejected
            case .retryable: updated.status = .queuedLocal
            }
            try write(updated)
            return updated
        }
    }

    /// Every readable report, leaving out those of a reply with a damaged report.
    func all(allowUnidentified: Bool = false) throws -> [AIResponseReport] {
        try locked {
            let scan = try scan()
            if scan.unidentified && !allowUnidentified { throw AIResponseReportError.unidentified }
            return scan.reports.filter { !scan.damaged.contains($0.reference) }
        }
    }

    // MARK: Files

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try body()
    }

    private func file(for report: AIResponseReport) -> URL {
        directory.appendingPathComponent((report.manualOnly ? "manual-" : "") + report.id + ".json", isDirectory: false)
    }

    private func write(_ report: AIResponseReport) throws {
        let manager = FileManager.default
        var attributes: [FileAttributeKey: Any] = [:]
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        try Self.excludeFromBackup(directory)
        var object: [String: Any] = [
            "id": report.id, "conversationId": report.reference.conversationID, "messageKey": report.reference.messageKey,
            "response": report.response, "reason": report.reason, "note": report.note, "createdAtMs": report.createdAtMs,
            "status": report.status.rawValue, "attempts": report.attempts, "nextAttemptAtMs": report.nextAttemptAtMs,
            "acknowledgedAtMs": report.acknowledgedAtMs.map { $0 as Any } ?? NSNull(),
            "deletionReceipt": report.deletionReceipt.map { $0 as Any } ?? NSNull(),
        ]
        if report.manualOnly { object["manualOnly"] = true }
        if let replacementOf = report.replacementOf { object["replacementOf"] = replacementOf }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let target = file(for: report)
        try data.write(to: target, options: options)
        try Self.excludeFromBackup(target)
    }

    /// Reports stay out of iCloud and computer backups, as the privacy policy says:
    /// the folder, and each file again because a write replaces it.
    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try url.setResourceValues(values)
    }

    private struct Scan {
        var reports: [AIResponseReport] = []
        var damaged: Set<AIResponseReference> = []
        var unidentified = false
    }

    /// A damaged file whose reference cannot be read could be an acknowledged
    /// copy of any report, so it stops everything; a readable reference only
    /// stops reports of that reply.
    private func scan() throws -> Scan {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return Scan() }
        guard isDirectory.boolValue else { throw AIResponseReportError.invalid }
        var scan = Scan()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                scan.unidentified = true; continue
            }
            if let report = Self.parseReport(object), Self.valid(report, name: file.deletingPathExtension().lastPathComponent) {
                scan.reports.append(report)
            } else if let reference = Self.parseReference(object) {
                scan.damaged.insert(reference)
            } else {
                scan.unidentified = true
            }
        }
        scan.reports.sort { ($0.createdAtMs, $0.id) < ($1.createdAtMs, $1.id) }
        return scan
    }

    private static func valid(_ report: AIResponseReport, name: String) -> Bool {
        let manualFile = name.hasPrefix("manual-")
        return report.manualOnly == manualFile && report.id == (manualFile ? String(name.dropFirst("manual-".count)) : name)
            && UUID(uuidString: report.id)?.uuidString.lowercased() == report.id
            && reasons.contains(report.reason) && !isBlank(report.response) && report.attempts >= 0
    }

    private static func parseReference(_ object: [String: Any]) -> AIResponseReference? {
        guard let conversation = object["conversationId"] as? String, let key = object["messageKey"] as? String else { return nil }
        return AIResponseReference(conversationID: conversation, messageKey: key)
    }

    private static func parseReport(_ object: [String: Any]) -> AIResponseReport? {
        guard let reference = parseReference(object), let id = object["id"] as? String,
              let response = object["response"] as? String, let reason = object["reason"] as? String,
              let createdAtMs = integer(object["createdAtMs"]),
              let statusText = object["status"] as? String, let status = AIResponseReport.Status(rawValue: statusText) else { return nil }
        var manualOnly = false
        if let flag = object["manualOnly"] {
            guard let number = flag as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            manualOnly = number.boolValue
        }
        return AIResponseReport(id: id, reference: reference, response: response, reason: reason,
                                note: object["note"] as? String ?? "", createdAtMs: createdAtMs, status: status,
                                attempts: integer(object["attempts"]).map { Int(clamping: $0) } ?? 0,
                                nextAttemptAtMs: integer(object["nextAttemptAtMs"]) ?? 0,
                                acknowledgedAtMs: integer(object["acknowledgedAtMs"]),
                                deletionReceipt: object["deletionReceipt"] as? String,
                                manualOnly: manualOnly, replacementOf: object["replacementOf"] as? String)
    }

    /// A whole JSON number; true, false and fractions are not.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        return number.int64Value
    }

    // MARK: Text, as Kotlin counts it

    static func isBlank(_ text: String) -> Bool { text.allSatisfy(\.isWhitespace) }

    /// Kotlin trim() drops characters up to U+0020 at both ends; take(n) keeps n
    /// UTF-16 units. A character is never split here.
    static func normalizedNote(_ note: String) -> String {
        let scalars = note.unicodeScalars
        guard let first = scalars.firstIndex(where: { $0.value > 0x20 }),
              let last = scalars.lastIndex(where: { $0.value > 0x20 }) else { return "" }
        return take(String(scalars[first...last]), maximumNote)
    }

    static func take(_ text: String, _ limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var used = 0, end = text.startIndex
        for index in text.indices {
            let next = text.index(after: index)
            let width = text[index..<next].utf16.count
            guard used + width <= limit else { break }
            used += width; end = next
        }
        return String(text[..<end])
    }
}
