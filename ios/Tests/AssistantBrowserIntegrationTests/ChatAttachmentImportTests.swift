import Foundation
import XCTest
@testable import WoowAssistant

@MainActor final class ChatAttachmentImportTests: XCTestCase {
    func testLowSpaceRefusesTinyFilesWithStorageNoticeAndCleansStaging() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Synthetic capacity reproduces native264 without consuming device storage.
        let store = ChatAttachmentStore(root: root.appendingPathComponent("stored"),
                                        availableCapacity: { 428 * 1024 * 1024 })
        let photo = try picked("fixture-photo.png", under: root)
        let note = try picked("fixture-notes.txt", under: root)
        let outcome = store.importFiles([photo, note], conversationID: "chat", existing: [])
        XCTAssertTrue(outcome.added.isEmpty)
        XCTAssertEqual(outcome.overflow, 0)
        XCTAssertEqual(outcome.refused, [
            .init(name: photo.suggestedName, reason: .insufficientSpace),
            .init(name: note.suggestedName, reason: .insufficientSpace)
        ])
        for file in [photo, note] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.temporaryURL.deletingLastPathComponent().path))
        }
        let samples: [(AppDisplayLanguage, String)] = [
            (.english, "Couldn’t add: fixture-photo.png, fixture-notes.txt. There isn’t enough storage on this device. Free up space and try again."),
            (.traditionalChinese, "沒能新增：fixture-photo.png、fixture-notes.txt。裝置儲存空間不足，請騰出空間後再試。")
        ]
        for (language, expected) in samples {
            let localizer = AppLocalizer(language: language)
            XCTAssertFalse(localizer.resolve(.chatAttachInsufficientSpace(names: "sample")).usedFallback)
            let message = ChatAttachmentText(localizer: localizer).refused(outcome.refused)
            XCTAssertEqual(message, expected)
            XCTAssertFalse(message.contains("200 MB"))
        }
    }

    func testReserveUsesFileSizeAndAcceptsExactlyFiveHundredMiBRemaining() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(ChatAttachmentLimits.minimumFreeBytes, 500 * 1024 * 1024)
        XCTAssertEqual(ChatAttachmentLimits.maximumFileBytes, 200 * 1024 * 1024)
        for shortfall in [Int64(0), Int64(1)] {
            let capacity = ChatAttachmentLimits.minimumFreeBytes + 8 - shortfall
            let store = ChatAttachmentStore(root: root.appendingPathComponent(UUID().uuidString),
                                            availableCapacity: { capacity })
            let file = try picked("eight-bytes.txt", bytes: 8, under: root)
            let outcome = store.importFiles([file], conversationID: "chat", existing: [])
            if shortfall == 0 {
                XCTAssertTrue(outcome.refused.isEmpty)
                XCTAssertEqual(outcome.added.count, 1)
                let item = try XCTUnwrap(outcome.added.first)
                XCTAssertEqual(item.byteCount, 8)
                XCTAssertTrue(store.exists(item))
            } else {
                XCTAssertTrue(outcome.added.isEmpty)
                XCTAssertEqual(outcome.refused, [.init(name: file.suggestedName, reason: .insufficientSpace)])
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.temporaryURL.deletingLastPathComponent().path))
        }
    }

    func testMixedBatchKeepsSizeSpaceAndUnavailableReasonsSeparate() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatAttachmentStore(root: root.appendingPathComponent("stored"),
                                        availableCapacity: { 428 * 1024 * 1024 })
        let small = try picked("small.txt", under: root)
        // Sparse metadata exercises the real file-size check without a 200 MB allocation.
        let large = try picked("large.bin", bytes: UInt64(ChatAttachmentLimits.maximumFileBytes + 1), under: root)
        let missing = ChatPickedFile(temporaryURL: root.appendingPathComponent("missing/gone.txt"),
                                     suggestedName: "gone.txt", contentType: nil, dedupeKey: nil)
        let outcome = store.importFiles([small, large, missing], conversationID: "chat", existing: [])
        XCTAssertTrue(outcome.added.isEmpty)
        XCTAssertEqual(outcome.refused, [
            .init(name: "small.txt", reason: .insufficientSpace),
            .init(name: "large.bin", reason: .tooLarge),
            .init(name: "gone.txt", reason: .unavailable)
        ])
        for language in [AppDisplayLanguage.english, .traditionalChinese] {
            let localizer = AppLocalizer(language: language)
            let message = ChatAttachmentText(localizer: localizer).refused(outcome.refused)
            XCTAssertEqual(message.components(separatedBy: "\n"), [
                localizer.text(.chatAttachInsufficientSpace(names: "small.txt")),
                localizer.text(.chatAttachTooLarge(names: "large.bin")),
                localizer.text(.chatAttachRefused(names: "gone.txt"))
            ])
            XCTAssertTrue(localizer.text(.chatAttachTooLarge(names: "large.bin")).contains("200 MB"))
            XCTAssertFalse(localizer.text(.chatAttachRefused(names: "gone.txt")).contains("200 MB"))
        }
    }

    func testValidFileStillImportsAlongsideOversizeRefusal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatAttachmentStore(root: root.appendingPathComponent("stored"),
                                        availableCapacity: { 2 * 1024 * 1024 * 1024 })
        let large = try picked("large.bin", bytes: UInt64(ChatAttachmentLimits.maximumFileBytes + 1), under: root)
        let small = try picked("small.txt", under: root)
        let outcome = store.importFiles([large, small], conversationID: "chat", existing: [])
        XCTAssertEqual(outcome.refused, [.init(name: "large.bin", reason: .tooLarge)])
        XCTAssertEqual(outcome.added.map(\.name), ["small.txt"])
        XCTAssertTrue(store.exists(try XCTUnwrap(outcome.added.first)))
        XCTAssertEqual(outcome.overflow, 0)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentImportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func picked(_ name: String, bytes: UInt64 = 1, under root: URL) throws -> ChatPickedFile {
        let folder = root.appendingPathComponent("incoming/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: bytes)
        return ChatPickedFile(temporaryURL: url, suggestedName: name, contentType: nil, dedupeKey: nil)
    }
}
