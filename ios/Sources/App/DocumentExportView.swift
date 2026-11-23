import AssistantDocuments
import Foundation
import PDFKit
import SwiftUI
import UIKit
import WebKit

/// A value snapshot: later conversation updates cannot silently change this export.
struct DocumentExportSource: Identifiable {
    let id = UUID()
    let content: String
    var format: DocumentFormat = .pdf
}

struct GeneratedDocument: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let data: Data
    let format: DocumentFormat
    let protectedCells: Int
}

/// StateObject lifetime outlives a nested full-screen system sheet. Cleanup must
/// not depend on onDisappear, which also fires while a child sheet is presented.
@MainActor private final class DocumentExportLifetime: ObservableObject {
    var task: Task<Void, Never>?
    var fileID: UUID?
    deinit {
        task?.cancel()
        if let fileID { Task { await DocumentExportStore.shared.release(fileID) } }
    }
}

/// Logical cache capacity is separate from a device filesystem failure.
enum DocumentExportFailure: Error, Equatable {
    case temporaryQuotaExceeded

    static func message(for error: Error) -> AppText {
        if error as? DocumentExportFailure == .temporaryQuotaExceeded { return .documentQuotaFull }
        let failure = error as NSError
        if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError)
            || (failure.domain == NSPOSIXErrorDomain && failure.code == Int(POSIXErrorCode.ENOSPC.rawValue)) {
            return .documentStorageFull
        }
        return .documentGenerationFailed
    }
}

/// Serializes parsing, rendering and disk work away from the UI actor. Only this
/// directory is pruned. Live previews/shares stay pinned until their sheet closes.
actor DocumentExportStore {
    static let shared = DocumentExportStore()
    private var active: [UUID: URL] = [:]
    private let storageRoot: URL?
    private let maximumStoredBytes = 100 * 1024 * 1024
    private let retention: TimeInterval = 24 * 60 * 60

    init(storageRoot: URL? = nil) { self.storageRoot = storageRoot }

    func parse(_ source: String, title: String, language: String) throws -> DocumentReport {
        try DocumentReport.parseMarkdown(source: source, title: title, language: language)
    }

    func generate(source: String, title: String, language: String,
                  format: DocumentFormat, table: Int?) throws -> GeneratedDocument {
        try Task.checkCancellation()
        let report = try DocumentReport.parseMarkdown(source: source, title: title, language: language)
        let data: Data
        var protectedCells = 0
        switch format {
        case .html: data = Data(try report.html().utf8)
        case .pdf: data = try DocumentPDFRenderer.render(report)
        case .csv:
            guard let table else { throw DocumentError.tableIndexOutOfBounds }
            data = Data(try report.csv(tableIndex: table).utf8)
            protectedCells = try report.formulaProtectedCellCount(tableIndex: table)
        }
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= DocumentLimits.maximumOutputBytes else { throw DocumentError.outputTooLarge }
        let root = try storageRoot ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("GeneratedDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let remaining = try prune(root: root)
        guard remaining + data.count <= maximumStoredBytes else { throw DocumentExportFailure.temporaryQuotaExceeded }
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent(report.safeFilename(format: format))
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var excluded = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            active[id] = directory
            return GeneratedDocument(id: id, url: url, data: data, format: format, protectedCells: protectedCells)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func release(_ id: UUID) {
        if let directory = active.removeValue(forKey: id) {
            // Retain for a day after the consumer closes, even when a preview
            // has stayed open longer than a day before the user shares it.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
        }
    }

    private func prune(root: URL) throws -> Int {
        var total = 0
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let modified = try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
            if active[id] == nil, Date().timeIntervalSince(modified) > retention {
                try FileManager.default.removeItem(at: folder)
                continue
            }
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) {
                total += try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            }
        }
        return total
    }
}

/// Only a completed parse is terminal. A cancelled view task can retry on the
/// same object; an older attempt never publishes over a newer attempt.
@MainActor
final class DocumentSourceValidation: ObservableObject {
    @Published private(set) var report: DocumentReport?
    @Published private(set) var error: AppText?
    var initialized: Bool { report != nil || error != nil }
    private var latestAttempt: UUID?

    func initialize(parse: @MainActor () async throws -> DocumentReport) async -> DocumentReport? {
        guard !initialized, !Task.isCancelled else { return nil }
        let attempt = UUID()
        latestAttempt = attempt
        do {
            let parsed = try await parse()
            guard !Task.isCancelled, latestAttempt == attempt else { return nil }
            report = parsed
            return parsed
        } catch is CancellationError {
            // No publication or reset: a newer attempt may already be valid.
            return nil
        } catch {
            guard !Task.isCancelled, latestAttempt == attempt else { return nil }
            self.error = .documentInvalid
            return nil
        }
    }
}

@MainActor
struct DocumentExportView: View {
    let source: DocumentExportSource
    let localizer: AppLocalizer
    /// Like Play, which passes the locale's language tag: Chinese labels the PDF's column bands
    /// 欄 and gets Traditional Chinese glyphs, instead of the undetermined "und".
    private var language: String { localizer.language.rawValue }
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var format: DocumentFormat = .pdf
    @State private var selectedTable = -1
    @State private var generated: GeneratedDocument?
    @State private var busy = false
    @State private var status: AppText?
    @State private var delivery: DocumentDelivery?
    @State private var preview: GeneratedDocument?
    @State private var didSetInitialOptions = false
    @StateObject private var sourceValidation = DocumentSourceValidation()
    @StateObject private var lifetime = DocumentExportLifetime()

    private var report: DocumentReport? { sourceValidation.report }

    private var canGenerate: Bool {
        report != nil && !busy && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (format != .csv || selectedTable >= 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(localizer.text(.documentSource)) {
                    Text(verbatim: String(source.content.prefix(1_500)))
                        .lineLimit(6).textSelection(.enabled)
                        .accessibilityIdentifier("document.source")
                    Text(localizer.text(.documentLocalNotice)).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField(localizer.text(.documentTitle), text: $title)
                        .accessibilityIdentifier("document.title")
                        .onChange(of: title) { _, value in
                            if value.count > 80 { title = String(value.prefix(80)) }
                            invalidate()
                        }
                    Picker(localizer.text(.documentFormat), selection: $format) {
                        ForEach(DocumentFormat.allCases, id: \.self) { value in
                            Text(value.rawValue.uppercased()).tag(value)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("document.format")
                        .onChange(of: format) { _, _ in invalidate() }
                    if format == .csv {
                        if let report, !report.tables.isEmpty {
                            Picker(localizer.text(.documentTable), selection: $selectedTable) {
                                Text(localizer.text(.documentChooseTable)).tag(-1)
                                ForEach(Array(report.tables.enumerated()), id: \.offset) { index, table in
                                    Text("\(index + 1). " + table.columns.prefix(4).map { String($0.prefix(40)) }.joined(separator: " · ")).tag(index)
                                }
                            }.accessibilityIdentifier("document.table")
                                .onChange(of: selectedTable) { _, _ in invalidate() }
                        } else {
                            Text(localizer.text(.documentNoTable)).accessibilityIdentifier("document.noTable")
                        }
                        Text(localizer.text(.documentCSVNotice)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        generate()
                    } label: {
                        if busy { ProgressView(localizer.text(.documentGenerating)) }
                        else { Text(localizer.text(.documentGenerate)) }
                    }.disabled(!canGenerate).accessibilityIdentifier("document.generate")
                }.disabled(busy)

                if let status = sourceValidation.error ?? status {
                    Section {
                        Text(localizer.text(status)).accessibilityIdentifier("document.status")
                    }
                }
                if let generated {
                    Section {
                        Text(verbatim: generated.url.lastPathComponent).accessibilityIdentifier("document.filename")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(generated.data.count), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(localizer.text(.documentPreview)) { preview = generated }
                            .accessibilityIdentifier("document.preview")
                        Button(localizer.text(.documentSave)) { present(.save(generated)) }
                            .accessibilityIdentifier("document.save")
                        Button(localizer.text(.documentShare)) { present(.share(generated)) }
                            .accessibilityIdentifier("document.share")
                        if generated.protectedCells > 0 {
                            Text(localizer.text(.documentProtectedCells(count: generated.protectedCells)))
                                .font(.caption).accessibilityIdentifier("document.protectedCells")
                        }
                    }
                }
            }
            .navigationTitle(localizer.text(.documentAction))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonDone)) { dismiss() }.accessibilityIdentifier("document.done")
                }
            }
        }
        .task {
            guard !sourceValidation.initialized else { return }
            if !didSetInitialOptions {
                format = source.format
                // Like Play: a reply that starts with a table, or has no first line, is titled 回答 /
                // Answer rather than after its header row.
                let firstLine = source.content.split(maxSplits: 1, whereSeparator: \.isNewline).first.map(String.init) ?? ""
                title = firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("|") ? "" :
                    String(firstLine.unicodeScalars.prefix(512).filter { !CharacterSet.controlCharacters.contains($0) }
                        .map(String.init).joined().trimmingCharacters(in: CharacterSet(charactersIn: "# ")).prefix(80))
                if title.isEmpty { title = localizer.text(.documentDefaultTitle) }
                // Retrying a cancelled parse must not reset the user's edits.
                didSetInitialOptions = true
            }
            // Source validation is independent of the editable/inferred title.
            let language = self.language
            if let parsed = await sourceValidation.initialize(parse: {
                try await DocumentExportStore.shared.parse(source.content, title: "Report", language: language)
            }) {
                selectedTable = parsed.tables.count == 1 ? 0 : -1
            }
        }
        .sheet(item: $preview) { file in DocumentPreviewView(file: file, localizer: localizer) }
        .sheet(item: $delivery, onDismiss: {
            if status == .documentSaving || status == .documentShareOpened { status = .documentCancelled }
        }) { target in
            switch target {
            case .save(let file):
                DocumentSavePicker(url: file.url) { saved in
                    status = saved ? .documentSaved : .documentCancelled
                    delivery = nil
                }
            case .share(let file):
                DocumentSharePicker(url: file.url) { completed, failed in
                    status = failed ? .documentDeliveryFailed : (completed ? .documentActivityCompleted : .documentCancelled)
                    delivery = nil
                }
            }
        }
    }

    private func invalidate() {
        if let generated { Task { await DocumentExportStore.shared.release(generated.id) } }
        lifetime.fileID = nil
        generated = nil
        status = nil
    }

    private func generate() {
        invalidate()
        busy = true
        let selectedTitle = title, selectedFormat = format, table = selectedTable >= 0 ? selectedTable : nil
        let content = source.content, language = self.language
        let owner = lifetime
        lifetime.task = Task { [weak owner, generated = $generated, status = $status, busy = $busy] in
            defer { if owner != nil { busy.wrappedValue = false } }
            do {
                let file = try await DocumentExportStore.shared.generate(source: content, title: selectedTitle,
                                                                         language: language, format: selectedFormat, table: table)
                guard !Task.isCancelled, let owner else {
                    await DocumentExportStore.shared.release(file.id)
                    return
                }
                owner.fileID = file.id
                generated.wrappedValue = file
                status.wrappedValue = .documentCreated
            } catch is CancellationError {
                if owner != nil { status.wrappedValue = .documentCancelled }
            } catch {
                if owner != nil {
                    status.wrappedValue = DocumentExportFailure.message(for: error)
                }
            }
        }
    }

    private func present(_ target: DocumentDelivery) {
        guard FileManager.default.isReadableFile(atPath: target.file.url.path) else {
            status = .documentMissing
            return
        }
        status = target.isSave ? .documentSaving : .documentShareOpened
        delivery = target
    }
}

private enum DocumentDelivery: Identifiable {
    case save(GeneratedDocument), share(GeneratedDocument)
    var file: GeneratedDocument { switch self { case .save(let file), .share(let file): return file } }
    var isSave: Bool { if case .save = self { return true }; return false }
    var id: String { (isSave ? "save-" : "share-") + file.id.uuidString }
}

/// CSV output is valid UTF-8. Bound preview work without cutting a scalar or
/// changing the full generated data used by Files and Share.
enum DocumentCSVPreviewText {
    static let maximumBytes = 64 * 1024

    static func text(from data: Data) -> String {
        var end = data.index(data.startIndex, offsetBy: min(data.count, maximumBytes))
        if end < data.endIndex {
            // At most three continuation bytes for the generated UTF-8 input.
            while end > data.startIndex && data[end] & 0xC0 == 0x80 {
                data.formIndex(before: &end)
            }
        }
        return String(decoding: data[..<end], as: UTF8.self)
    }
}

private struct DocumentPreviewView: View {
    let file: GeneratedDocument
    let localizer: AppLocalizer
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if failed { Text(localizer.text(.documentPreviewFailed)) }
                else {
                    switch file.format {
                    case .html:
                        DocumentHTMLPreview(html: String(decoding: file.data, as: UTF8.self), failed: $failed)
                    case .pdf:
                        DocumentPDFPreview(data: file.data, failed: $failed)
                    case .csv:
                        VStack(alignment: .leading) {
                            if file.data.count > DocumentCSVPreviewText.maximumBytes {
                                Text(localizer.text(.documentPreviewPartial)).font(.caption).padding(.horizontal)
                            }
                            DocumentCSVPreview(text: DocumentCSVPreviewText.text(from: file.data))
                        }
                    }
                }
            }
            .accessibilityIdentifier("document.preview.content")
            .navigationTitle(file.url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonDone)) { dismiss() }.accessibilityIdentifier("document.preview.done")
                }
            }
        }
    }
}

private struct DocumentCSVPreview: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.text = text
        view.accessibilityIdentifier = "document.csv.content"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {}
}

private struct DocumentHTMLPreview: UIViewRepresentable {
    let html: String
    @Binding var failed: Bool
    func makeCoordinator() -> Coordinator { Coordinator(failed: $failed) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsLinkPreview = false
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var failed: Bool
        init(failed: Binding<Bool>) { _failed = failed }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only the generated in-memory document. No downloads, external
            // schemes, linked files or navigation driven by document content.
            decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank"
                            && action.targetFrame?.isMainFrame == true ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed = true }
    }
}

private struct DocumentPDFPreview: UIViewRepresentable {
    let data: Data
    @Binding var failed: Bool
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        if view.document == nil { DispatchQueue.main.async { failed = true } }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

private struct DocumentSavePicker: UIViewControllerRepresentable {
    let url: URL
    let complete: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (Bool) -> Void
        init(complete: @escaping (Bool) -> Void) { self.complete = complete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { complete(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete(false) }
    }
}

private struct DocumentSharePicker: UIViewControllerRepresentable {
    let url: URL
    let complete: (Bool, Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in complete(completed, error != nil) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
