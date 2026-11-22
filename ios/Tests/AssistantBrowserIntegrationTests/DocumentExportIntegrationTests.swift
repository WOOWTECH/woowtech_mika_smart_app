import AssistantDocuments
import Combine
import PDFKit
import XCTest
@testable import WoowAssistant

/// Real native rendering/file IO with synthetic documents. This is not a
/// provider, business-data or physical-device acceptance test.
final class DocumentExportIntegrationTests: XCTestCase {
    func testInferredPDFTitleAppearsOnlyOnce() throws {
        let report = try DocumentReport.parseMarkdown(source: "# IPAD_TITLE\n\n繁體中文 END_TITLE", title: "IPAD_TITLE", language: "zh-Hant")
        let pdf = try XCTUnwrap(PDFDocument(data: DocumentPDFRenderer.render(report)))
        let text = try XCTUnwrap(pdf.string)
        XCTAssertEqual(text.components(separatedBy: "IPAD_TITLE").count - 1, 1)
        XCTAssertTrue(text.contains("繁體中文"))
        XCTAssertTrue(text.contains("END_TITLE"))
    }

    func testChinesePDFRetainsTextThroughParagraphAndTablePagination() throws {
        let table = try DocumentTable(columns: ["項目", "說明"], rows: [
            ["跨頁儲存格", String(repeating: "繁體中文與 English 123，表格內容必須保留。\n", count: 150) + "TABLE_END_MARKER"],
            ["最後一列", "最後一列不可遺失"]
        ])
        let report = try DocumentReport(title: "中文跨頁報告", language: "zh-Hant", sections: [
            .heading(level: 1, text: "中文測試"),
            .paragraph(text: String(repeating: "長段落與 English 456，內容要完整。\n", count: 180) + "PARAGRAPH_END_MARKER"),
            .table(table), .paragraph(text: "DOCUMENT_END_MARKER")
        ])
        let data = try DocumentPDFRenderer.render(report)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 2)
        let extracted = try XCTUnwrap(document.string)
        // Keep the real output beside the assertion so a glyph/encoding problem
        // can be distinguished from pagination dropping source content.
        let pdf = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "chinese-pagination.pdf"; pdf.lifetime = .keepAlways
        add(pdf)
        let extraction = XCTAttachment(string: extracted)
        extraction.name = "chinese-pagination-extracted.txt"; extraction.lifetime = .keepAlways
        add(extraction)
        let text = extracted.filter { !$0.isWhitespace }
        for sentinel in ["中文跨頁報告", "PARAGRAPH_END_MARKER", "TABLE_END_MARKER", "最後一列不可遺失", "DOCUMENT_END_MARKER"] {
            XCTAssertTrue(text.contains(sentinel), "Missing PDF text: \(sentinel)")
        }
    }

    func testExportsUseDistinctFilesAndRetainBytesAfterRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        let source = "# 報告\n\n| 項目 | 值 |\n| --- | --- |\n| 中文 | =1+1 |\n| 編號 | 00123 |"
        let csv = try await store.generate(source: source, title: "../中文報告", language: "zh-Hant", format: .csv, table: 0)
        let html = try await store.generate(source: source, title: "../中文報告", language: "zh-Hant", format: .html, table: nil)
        XCTAssertNotEqual(csv.url.deletingLastPathComponent(), html.url.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: csv.url), csv.data)
        XCTAssertEqual(csv.protectedCells, 1)
        XCTAssertTrue(csv.data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(String(decoding: csv.data, as: UTF8.self).contains("'=1+1"))
        await store.release(csv.id)
        XCTAssertEqual(try Data(contentsOf: csv.url), csv.data, "Closing a sheet must not invalidate an external consumer's file")
        await store.release(html.id)
    }

    func testInvalidTableDoesNotCreateAFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        do {
            _ = try await store.generate(source: "| A | B |\n| --- | --- |\n| only one |", title: "Invalid", language: "en", format: .csv, table: 0)
            XCTFail("Ragged tables must not export as successful files")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testCleanupPreservesPinnedFilesAndStartsRetentionAtRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        let first = try await store.generate(source: "First", title: "First", language: "en", format: .html, table: nil)
        let folder = first.url.deletingLastPathComponent()
        let expired = Date(timeIntervalSinceNow: -48 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: expired], ofItemAtPath: folder.path)
        let second = try await store.generate(source: "Second", title: "Second", language: "en", format: .html, table: nil)
        XCTAssertEqual(try Data(contentsOf: first.url), first.data, "An active consumer remains pinned regardless of age")
        await store.release(first.id)
        let refreshed = try XCTUnwrap(folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertGreaterThan(refreshed, Date(timeIntervalSinceNow: -60))
        try FileManager.default.setAttributes([.modificationDate: expired], ofItemAtPath: folder.path)
        let third = try await store.generate(source: "Third", title: "Third", language: "en", format: .html, table: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        await store.release(second.id)
        await store.release(third.id)
    }

    @MainActor
    func testCancelledSourceValidationRetriesSameState() async throws {
        let store = DocumentExportStore()
        let source = "Valid source\n\n| A | B |\n| --- | --- |\n| one | two |"
        let expected = try await store.parse(source, title: "Report", language: "und")
        for cancelTask in [true, false] {
            let state = DocumentSourceValidation()
            let pause = SourceParsePause()
            var parserObservedCancellation = false
            var publications = 0
            let observation = state.objectWillChange.sink { publications += 1 }
            defer { observation.cancel() }
            let first = Task { @MainActor in
                await state.initialize {
                    await pause.wait()
                    // Also cover a dependency throwing CancellationError
                    // without this task's cancellation bit being set.
                    if !cancelTask { throw CancellationError() }
                    do {
                        return try await store.parse(source, title: "Report", language: "und")
                    } catch {
                        parserObservedCancellation = error is CancellationError
                        throw error
                    }
                }
            }
            defer { first.cancel(); pause.resume() }
            await fulfillment(of: [pause.entered], timeout: 5)
            if cancelTask { first.cancel() }
            pause.resume()
            let cancelled = await first.value
            XCTAssertNil(cancelled)
            if cancelTask { XCTAssertTrue(parserObservedCancellation, "The real parser must observe cancellation") }
            XCTAssertNil(state.report)
            XCTAssertNil(state.error)
            XCTAssertFalse(state.initialized)
            XCTAssertEqual(publications, 0, "Cancellation must not publish an invalid or empty terminal state")

            let retried = await state.initialize {
                try await store.parse(source, title: "Report", language: "und")
            }
            XCTAssertEqual(retried, expected)
            XCTAssertEqual(state.report, expected)
            XCTAssertNil(state.error)
            XCTAssertTrue(state.initialized)
            XCTAssertEqual(publications, 1)
        }
    }

    @MainActor
    func testSupersededSourceValidationCannotOverwriteNewResult() async throws {
        let store = DocumentExportStore()
        let source = "Valid immutable source"
        let expected = try await store.parse(source, title: "Report", language: "und")
        let completions: [Result<DocumentReport, Error>] = [
            .success(expected), .failure(DocumentError.invalidTable), .failure(CancellationError())
        ]
        for cancelOlder in [true, false] {
            for completion in completions {
                let state = DocumentSourceValidation()
                let pause = SourceParsePause()
                var publications = 0
                let observation = state.objectWillChange.sink { publications += 1 }
                defer { observation.cancel() }
                let older = Task { @MainActor in
                    await state.initialize {
                        await pause.wait()
                        return try completion.get()
                    }
                }
                defer { older.cancel(); pause.resume() }
                await fulfillment(of: [pause.entered], timeout: 5)
                if cancelOlder { older.cancel() }
                let newer = await state.initialize {
                    try await store.parse(source, title: "Report", language: "und")
                }
                XCTAssertEqual(newer, expected)
                XCTAssertEqual(publications, 1)
                // Complete the older success/error only after the newer
                // actual parse commits, exercising fast view-task re-entry.
                pause.resume()
                let stale = await older.value
                XCTAssertNil(stale, "A superseded task cannot select a table or publish state")
                XCTAssertEqual(state.report, expected)
                XCTAssertNil(state.error)
                XCTAssertTrue(state.initialized)
                XCTAssertEqual(publications, 1, "Neither old cancellation nor old results may publish")
            }
        }
    }

    @MainActor
    func testInvalidSourceValidationRemainsTerminal() async throws {
        let store = DocumentExportStore()
        let state = DocumentSourceValidation()
        let malformed = "| A | B |\n| --- | --- |\n| only one |"
        let result = await state.initialize {
            do {
                return try await store.parse(malformed, title: "Report", language: "und")
            } catch {
                XCTAssertEqual(error as? DocumentError, .invalidTable)
                throw error
            }
        }
        XCTAssertNil(result)
        XCTAssertNil(state.report)
        XCTAssertEqual(state.error, .documentInvalid)
        XCTAssertTrue(state.initialized)
        let repeated = await state.initialize {
            XCTFail("A genuinely invalid immutable source must remain terminal")
            return try await store.parse("Valid", title: "Report", language: "und")
        }
        XCTAssertNil(repeated)
        XCTAssertEqual(state.error, .documentInvalid)
        XCTAssertNil(state.report)
    }

    /// The test controls ordering with a continuation, never a sleep. The
    /// expectation bounds waiting for entry; every task is released in defer.
    @MainActor private final class SourceParsePause {
        let entered = XCTestExpectation(description: "Source parser entered")
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            if released { entered.fulfill(); return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }

        func resume() {
            released = true
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
    }

    func testCSVPreviewKeepsCompleteUTF8ScalarsAt64KiBBoundary() throws {
        let limit = 64 * 1024
        let csvHeader = "\u{FEFF}\"A\"\r\n\""
        // Exercise every cut position, including exact scalar boundaries, in
        // real CSV output with its BOM/header/quote bytes included in the limit.
        for scalar in ["é", "中", "🙂"] {
            for bytesBeforeLimit in 0...scalar.utf8.count {
                let ascii = String(repeating: "x", count: limit - csvHeader.utf8.count - bytesBeforeLimit)
                let report = try DocumentReport.parseMarkdown(
                    source: "| A |\n| --- |\n| \(ascii)\(scalar)TAIL |", title: "Boundary", language: "en")
                let data = Data(try report.csv().utf8)
                XCTAssertGreaterThan(data.count, limit)
                let preview = DocumentCSVPreviewText.text(from: data)
                let expected = csvHeader + ascii + (bytesBeforeLimit == scalar.utf8.count ? scalar : "")
                XCTAssertEqual(preview, expected, "Scalar \(scalar), bytes before limit \(bytesBeforeLimit)")
                XCTAssertLessThanOrEqual(preview.utf8.count, limit)
                XCTAssertFalse(preview.contains("\u{FFFD}"))
            }
        }
        for text in ["", "中文🙂", String(repeating: "a", count: limit)] {
            XCTAssertEqual(DocumentCSVPreviewText.text(from: Data(text.utf8)), text)
        }
        let ascii = String(repeating: "a", count: limit)
        XCTAssertEqual(DocumentCSVPreviewText.text(from: Data((ascii + "TAIL").utf8)), ascii)
    }

    func testCSVPreviewDoesNotTruncateStoredExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        // BOM + quoted header + CRLF + opening cell quote = nine bytes.
        let ascii = String(repeating: "x", count: 64 * 1024 - 10)
        let source = "| A |\n| --- |\n| \(ascii)中TAIL |"
        let file = try await store.generate(source: source, title: "CSV boundary", language: "zh-Hant", format: .csv, table: 0)
        let complete = Data(("\u{FEFF}\"A\"\r\n\"" + ascii + "中TAIL\"\r\n").utf8)
        XCTAssertEqual(file.data, complete)
        XCTAssertEqual(DocumentCSVPreviewText.text(from: file.data), "\u{FEFF}\"A\"\r\n\"" + ascii)
        XCTAssertEqual(try Data(contentsOf: file.url), complete)
        await store.release(file.id)
        XCTAssertEqual(try Data(contentsOf: file.url), complete)
    }

    func testQuotaFailureRetainsFilesAndRecoversOnlyAfterExpiry() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        let pinned = try await store.generate(source: String(repeating: "Pinned content. ", count: 100),
                                              title: "Pinned", language: "en", format: .html, table: nil)
        let pinnedFolder = pinned.url.deletingLastPathComponent()
        // Isolated sparse file models retained logical bytes without filling
        // the device's disk. The production 100 MiB limit is not injected/lowered.
        let retainedFolder = root.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: retainedFolder, withIntermediateDirectories: false)
        let retainedFile = retainedFolder.appendingPathComponent("synthetic-retained-cache.bin")
        XCTAssertTrue(manager.createFile(atPath: retainedFile.path, contents: Data()))
        let retainedBytes = 100 * 1024 * 1024 - pinned.data.count
        do {
            let handle = try FileHandle(forWritingTo: retainedFile)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(retainedBytes))
        }
        let expired = Date(timeIntervalSinceNow: -48 * 60 * 60)
        try manager.setAttributes([.modificationDate: expired], ofItemAtPath: pinnedFolder.path)
        let originalFolders = Set(try manager.contentsOfDirectory(atPath: root.path))

        for phase in ["pinned", "released"] {
            if phase == "released" {
                await store.release(pinned.id)
                let releasedAt = try XCTUnwrap(pinnedFolder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                XCTAssertGreaterThan(releasedAt, Date(timeIntervalSinceNow: -60))
            }
            do {
                _ = try await store.generate(source: "Retry", title: "Retry", language: "en", format: .html, table: nil)
                XCTFail("Quota must still reject while files are \(phase)")
            } catch {
                XCTAssertEqual(error as? DocumentExportFailure, .temporaryQuotaExceeded)
                XCTAssertEqual(DocumentExportFailure.message(for: error), .documentQuotaFull)
            }
            XCTAssertEqual(Set(try manager.contentsOfDirectory(atPath: root.path)), originalFolders)
            XCTAssertEqual(try Data(contentsOf: pinned.url), pinned.data)
            XCTAssertEqual(try retainedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, retainedBytes)
        }

        // Expire only the inactive retained file. A fresh release stays intact.
        try manager.setAttributes([.modificationDate: expired], ofItemAtPath: retainedFolder.path)
        let recovered = try await store.generate(source: "Retry", title: "Retry", language: "en", format: .html, table: nil)
        XCTAssertFalse(manager.fileExists(atPath: retainedFolder.path))
        XCTAssertEqual(try Data(contentsOf: pinned.url), pinned.data)
        XCTAssertEqual(try Data(contentsOf: recovered.url), recovered.data)
        await store.release(recovered.id)
    }

    func testDocumentExportFailuresDistinguishQuotaFromDeviceSpace() {
        XCTAssertEqual(DocumentExportFailure.message(for: DocumentExportFailure.temporaryQuotaExceeded), .documentQuotaFull)
        XCTAssertEqual(DocumentExportFailure.message(for: CocoaError(.fileWriteOutOfSpace)), .documentStorageFull)
        XCTAssertEqual(DocumentExportFailure.message(for: POSIXError(.ENOSPC)), .documentStorageFull)
        XCTAssertEqual(DocumentExportFailure.message(for: CocoaError(.fileWriteNoPermission)), .documentGenerationFailed)
        XCTAssertEqual(DocumentExportFailure.message(for: NSError(domain: "SyntheticOtherDomain", code: NSFileWriteOutOfSpaceError)),
                       .documentGenerationFailed, "An unrelated error with the same numeric code is not a disk-full diagnosis")
    }

    func testDocumentStorageNoticesResolveInBothLanguages() {
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            let quota = localizer.resolve(.documentQuotaFull)
            let disk = localizer.resolve(.documentStorageFull)
            XCTAssertFalse(quota.usedFallback)
            XCTAssertFalse(disk.usedFallback)
            XCTAssertEqual(quota.language, language)
            XCTAssertEqual(disk.language, language)
            XCTAssertTrue(quota.text.contains("100 MiB"))
            XCTAssertTrue(quota.text.contains("24"))
            XCTAssertFalse(disk.text.contains("100 MiB"))
            XCTAssertNotEqual(quota.text, disk.text)
        }
    }
}
