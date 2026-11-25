import AssistantBrowser
import Foundation

/// The rules behind browser downloads and created files, without a page or
/// a network: the question's answer and its time, the size limits, file
/// names, Content-Disposition, cleanup by age, what a restart lists again,
/// and the created-file store. Real files in a temporary folder.
@main
enum CheckBrowserDownloads {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String, line: Int = #line) {
        do { guard try condition() else { fail(label, line: line) } } catch { fail(label + " threw \(error)", line: line) }
        assertions += 1
    }

    static func fail(_ label: String, line: Int) -> Never {
        FileHandle.standardError.write(Data("FAIL line \(line): \(label)\n".utf8))
        exit(1)
    }

    static let mebibyte: Int64 = 1_048_576

    @MainActor static func main() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("woow-downloads-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        limits()
        answers()
        names()
        try folders(scratch.appendingPathComponent("folder"))
        try restart(scratch.appendingPathComponent("downloads"))
        try createdFiles(scratch.appendingPathComponent("created"))
        print("{\"assertions\":\(assertions)}")
    }

    static func limits() {
        let limits = BrowserDownloadLimits()
        expect(limits.maximumFileBytes == 200 * mebibyte && limits.maximumStoredBytes == 500 * mebibyte
               && limits.maximumActive == 3 && limits.answerTime == 120 && limits.maximumRedirects == 5
               && limits.maximumListed == 20, "the documented limits")
        typealias R = BrowserDownloadRules
        expect(R.refusal(expectedBytes: 200 * mebibyte, storedBytes: 0, active: 0, limits: limits) == nil, "200 MB exactly")
        expect(R.refusal(expectedBytes: 200 * mebibyte + 1, storedBytes: 0, active: 0, limits: limits) == .tooLarge, "one byte over")
        expect(R.refusal(expectedBytes: nil, storedBytes: 0, active: 2, limits: limits) == nil, "an unknown size may ask")
        expect(R.refusal(expectedBytes: 1, storedBytes: 0, active: 3, limits: limits) == .tooMany, "a fourth at once")
        expect(R.refusal(expectedBytes: 100 * mebibyte, storedBytes: 400 * mebibyte, active: 0, limits: limits) == nil, "500 MB in all")
        expect(R.refusal(expectedBytes: 100 * mebibyte + 1, storedBytes: 400 * mebibyte, active: 0, limits: limits) == .storageFull,
               "over 500 MB in all")
        expect(R.refusal(expectedBytes: nil, storedBytes: 500 * mebibyte + 1, active: 0, limits: limits) == .storageFull,
               "a full folder refuses an unknown size")
        expect(R.refusal(receivedBytes: 200 * mebibyte + 1, storedBytes: 0, limits: limits) == .tooLarge, "arriving over the file limit")
        expect(R.refusal(receivedBytes: 150 * mebibyte, storedBytes: 351 * mebibyte, limits: limits) == .storageFull, "arriving over the total")
        expect(R.refusal(receivedBytes: 150 * mebibyte, storedBytes: 350 * mebibyte, limits: limits) == nil, "arriving within both")
    }

    static func answers() {
        let limits = BrowserDownloadLimits()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var item = BrowserDownloadItem(fileName: "a", host: "")
        expect(!item.answer(true, now: start, limits: limits) && item.phase == .starting, "no answer before the question")
        item.ask(fileName: "報告.pdf", expectedBytes: 10, host: "example.com", now: start)
        expect(item.phase == .asking && item.fileName == "報告.pdf" && item.askedAt == start, "the question")
        expect(!item.expire(now: start.addingTimeInterval(119), limits: limits) && item.phase == .asking, "still asking at 119 s")
        expect(item.answer(true, now: start.addingTimeInterval(119), limits: limits) && item.phase == .downloading, "下載 in time")
        expect(!item.answer(false, now: start.addingTimeInterval(119), limits: limits) && item.phase == .downloading,
               "a second answer does not count")
        item.ask(fileName: "other", expectedBytes: nil, host: "", now: start)
        expect(item.fileName == "報告.pdf", "no second question once downloading")

        var declined = BrowserDownloadItem(fileName: "a", host: "")
        declined.ask(fileName: "a", expectedBytes: nil, host: "", now: start)
        expect(!declined.answer(false, now: start, limits: limits) && declined.phase == .cancelled, "取消 downloads nothing")
        expect(!declined.answer(true, now: start, limits: limits) && declined.phase == .cancelled, "no 下載 after 取消")

        var late = BrowserDownloadItem(fileName: "a", host: "")
        late.ask(fileName: "a", expectedBytes: nil, host: "", now: start)
        expect(!late.answer(true, now: start.addingTimeInterval(120), limits: limits) && late.phase == .failed(.expired),
               "下載 after two minutes is too late")
        var unanswered = BrowserDownloadItem(fileName: "a", host: "")
        unanswered.ask(fileName: "a", expectedBytes: nil, host: "", now: start)
        expect(unanswered.expire(now: start.addingTimeInterval(120), limits: limits) && unanswered.phase == .failed(.expired),
               "unanswered for two minutes")
        expect(!unanswered.expire(now: start.addingTimeInterval(500), limits: limits), "expires once")
        expect(BrowserDownloadItem.Phase.asking.isActive && BrowserDownloadItem.Phase.starting.isActive
               && !BrowserDownloadItem.Phase.finished.isActive && !BrowserDownloadItem.Phase.failed(.network).isActive, "active phases")
    }

    static func names() {
        typealias R = BrowserDownloadRules
        func response(_ disposition: String?) -> URLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com/f")!, statusCode: 200, httpVersion: nil,
                            headerFields: disposition.map { ["Content-Disposition": $0] } ?? [:])!
        }
        expect(R.isAttachment(response("attachment")) && R.isAttachment(response("Attachment; filename=\"a.pdf\""))
               && R.isAttachment(response(" attachment ;filename*=UTF-8''%E5%A0%B1.pdf")), "attachment, any case and parameters")
        expect(!R.isAttachment(response("inline; filename=a.pdf")) && !R.isAttachment(response(nil))
               && !R.isAttachment(URLResponse(url: URL(string: "https://example.com")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)),
               "inline, none, or not HTTP")
        let names: [(String, String)] = [
            ("報告.pdf", "報告.pdf"), ("../../etc/passwd", "_.._etc_passwd"), ("a\\b:c*d?e\"f<g>h|i%2F.txt", "a_b_c_d_e_f_g_h_i_2F.txt"),
            ("", "download"), ("..", "download"), ("  .hidden ", "hidden"), ("tab\tname\u{202E}.exe", "tab_name_.exe"),
            (String(repeating: "長", count: 100) + ".xlsx", String(repeating: "長", count: 38) + ".xlsx"),
        ]
        for (raw, expected) in names { expect(R.fileName(raw) == expected, "file name \(raw) -> \(R.fileName(raw))") }
        expect(R.fileName(String(repeating: "長", count: 100) + ".xlsx").utf8.count <= 120, "120 bytes with the extension")
        expect(R.host(of: URL(string: "https://www.Example.com/a?b=c")) == "example.com" && R.host(of: nil) == "", "the site's name")
        expect(R.isDeviceFull(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
               && R.isDeviceFull(CocoaError(.fileWriteOutOfSpace))
               && !R.isDeviceFull(URLError(.notConnectedToInternet)), "a full device is not a network failure")
    }

    static func folders(_ root: URL) throws {
        let folder = PendingFileFolder(root: root)
        let now = Date()
        let fresh = UUID(), old = UUID(), kept = UUID()
        let file = try folder.write(Data("hello".utf8), named: "a.txt", id: fresh)
        expect(try Data(contentsOf: file) == Data("hello".utf8), "written")
        expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "excluded from backup")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        expect(permissions?.intValue == 0o700, "the item folder is the app's alone")
        expect((try? folder.write(Data(), named: "b.txt", id: fresh)) == nil, "an item folder is made once")
        _ = try folder.write(Data(count: 10), named: "old.bin", id: old)
        _ = try folder.write(Data(count: 7), named: "kept.bin", id: kept)
        try Data("note".utf8).write(to: root.appendingPathComponent(kept.uuidString).appendingPathComponent(".reply"))
        let day = PendingFileFolder.retention
        for id in [old, kept] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-day - 60)],
                                                  ofItemAtPath: root.appendingPathComponent(id.uuidString).path)
        }
        // Names that are not the app's items, and a link to a folder outside.
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        let link = UUID()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(link.uuidString), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(UUID().uuidString.lowercased()), withIntermediateDirectories: true)
        expect(Set(folder.items().map(\.id)) == [fresh, old, kept], "only the app's own item folders")
        expect(folder.storedBytes() == 5 + 10 + 7, "stored bytes leave out notes")
        let removed = folder.purge(now: now, keeping: [kept])
        expect(removed == [old], "older than a day goes, unless in use")
        expect(Set(folder.items().map(\.id)) == [fresh, kept], "the rest stay")
        expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep.txt").path), "a link is never followed")
        expect(folder.purge(olderThan: -1, now: now).count == 2, "everything, when asked")
        folder.remove(UUID())
        expect(folder.items().isEmpty, "removing nothing is harmless")
    }

    @MainActor static func restart(_ root: URL) throws {
        let now = Date()
        let partial = PendingFileFolder(root: root.appendingPathComponent("Partial"))
        let files = PendingFileFolder(root: root.appendingPathComponent("Files"))
        let arriving = UUID(), stale = UUID(), waiting = UUID()
        _ = try partial.write(Data(count: 3), named: "half.zip", id: arriving)
        _ = try files.write(Data(count: 4), named: "old.pdf", id: stale)
        let kept = try files.write(Data(count: 6), named: "新.pdf", id: waiting)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-PendingFileFolder.retention - 1)],
                                              ofItemAtPath: files.root.appendingPathComponent(stale.uuidString).path)
        let manager = BrowserDownloadManager(root: root, now: now, allowsURL: { _ in true })
        expect(partial.items().isEmpty, "what an earlier run left arriving is deleted")
        expect(files.items().map(\.id) == [waiting], "a finished file older than a day is deleted")
        expect(manager.items.count == 1 && manager.items[0].id == waiting && manager.items[0].phase == .finished
               && manager.items[0].fileName == "新.pdf" && manager.items[0].receivedBytes == 6, "the rest are listed again")
        expect(manager.file(waiting)?.lastPathComponent == kept.lastPathComponent, "its file")
        manager.delivered(waiting, as: .saved)
        expect(manager.items[0].phase == .delivered(.saved) && manager.file(waiting) == nil && files.items().isEmpty,
               "saved: the app's copy is deleted")
        manager.delivered(waiting, as: .shared)
        expect(manager.items[0].phase == .delivered(.saved), "delivered once")
        manager.remove(waiting)
        expect(manager.items.isEmpty && manager.question == nil, "removed from the list")
        let second = UUID()
        _ = try files.write(Data(count: 2), named: "b.txt", id: second)
        let again = BrowserDownloadManager(root: root, now: now, allowsURL: { _ in true })
        again.remove(second)
        expect(again.items.isEmpty && files.items().isEmpty, "移除 deletes a finished file")
        again.cancelAll()
        expect(again.items.isEmpty, "nothing to stop")
    }

    static func createdFiles(_ root: URL) throws {
        let store = ChatCreatedFileStore(folder: PendingFileFolder(root: root))
        let reply = UUID()
        let file = try store.save(Data("%PDF".utf8), name: "報告.pdf", format: "pdf")
        let orphan = try store.save(Data("x".utf8), name: "x.docx", format: "docx")
        store.attach(file, to: reply)
        expect(store.exists(file) && file.byteCount == 4 && file.state == .ready, "saved")
        var cards = store.load()
        expect(cards[reply]?.map(\.name) == ["報告.pdf"] && cards.count == 1, "a card comes back by its reply")
        expect(!store.exists(orphan), "a file whose reply never came is deleted at start")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-PendingFileFolder.retention - 1)],
                                              ofItemAtPath: file.url.deletingLastPathComponent().path)
        cards = store.load()
        expect(cards.isEmpty && !store.exists(file), "a day later it is deleted")
        // A sparse file fills the logical limit without using the disk.
        let filler = try store.save(Data(), name: "filler.bin", format: "zip")
        let handle = try FileHandle(forWritingTo: filler.url)
        try handle.truncate(atOffset: UInt64(ChatCreatedFileLimits.maximumStoredBytes))
        try handle.close()
        do {
            _ = try store.save(Data("y".utf8), name: "y.pdf", format: "pdf")
            fail("over the limit was saved", line: #line)
        } catch ChatCreatedFileError.storageFull { assertions += 1 }
        store.remove(filler)
        expect((try? store.save(Data("y".utf8), name: "y.pdf", format: "pdf")) != nil, "room again once removed")
    }
}
