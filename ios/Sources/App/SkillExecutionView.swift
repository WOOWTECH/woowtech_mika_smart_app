import AssistantBrowser
import AssistantSkills
import Combine
import Foundation
#if DEBUG
import Darwin
#endif

#if os(iOS) || SKILL_EXECUTION_EXPORT_CHECKS
#if canImport(AssistantSkills)
import AssistantSkills
#endif
import SwiftUI
import UniformTypeIdentifiers
#if DEBUG
import Darwin
#endif

/// An immutable UTF-8 snapshot of a completed extraction. FileDocument leaves
/// destination selection and writing to the system exporter, never to a skill.
struct SkillExecutionTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    let text: String

    init(text: String) throws {
        guard text.utf8.count <= SkillExecutionLimits.outputBytes else { throw SkillExecutionError.outputTooLarge }
        self.text = text
    }

    init(configuration: ReadConfiguration) throws { try self.init(fileWrapper: configuration.file) }

    init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isRegularFile, let data = fileWrapper.regularFileContents,
              data.count <= SkillExecutionLimits.outputBytes,
              let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(text: text)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { snapshot() }
    func snapshot() -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
#endif

#if os(iOS)
import Combine

private struct DocumentQueryPresentation: Identifiable {
    let id = UUID()
    let source: DocumentTextSnapshot
}

/// Parent integration: present from the documents skill with current model access.
/// Extraction always runs on the device with PDFKit; nothing is uploaded.
@MainActor struct SkillExecutionView: View {
    @Environment(\.appLocalizer) private var localizer
    private let learning: LearningStore
    private let modelAccess: () throws -> ModelAccess
    private let modelChanges: AnyPublisher<Void, Never>
    @StateObject private var model = SkillExecutionViewModel()
    @State private var choosingFile = false
    @State private var importChoice: PDFImportChoice = .original
    @State private var importCopyExpanded = false
    @State private var documentQuery: DocumentQueryPresentation?
    @State private var localSearch: DocumentLocalSearch?
    @State private var localSearchPreparationFailed = false
    @State private var pages = ""
    @State private var password = ""
    @State private var metadataOnly = false
    @State private var exportingText = false
    @State private var exportDocument: SkillExecutionTextDocument?
    @State private var exportPlanID: UUID?
    @State private var exportFilename = "PDF文字"
    @State private var exportStatus: AppText?
    #if DEBUG
    @State private var pickerObservation = "尚未觀察選檔器"
    #endif

    private var pickerExperiment: PDFNativePickerExperiment.Configuration? {
        #if DEBUG
        PDFNativePickerExperiment.configuration(arguments: ProcessInfo.processInfo.arguments,
                                                fixtureNamespace: model.uiTestFixture?.namespace)
        #else
        nil
        #endif
    }

    private var pickerObservationNamespace: UUID? {
        #if DEBUG
        model.uiTestFixture?.namespace
        #else
        nil
        #endif
    }

    init(learning: LearningStore, modelAccess: @escaping () throws -> ModelAccess, modelChanges: AnyPublisher<Void, Never>,
         downloadedPDF: BrowserDownloadedPDFSelection? = nil) {
        _model = StateObject(wrappedValue: SkillExecutionViewModel(downloadedPDF: downloadedPDF))
        self.learning = learning; self.modelAccess = modelAccess; self.modelChanges = modelChanges
    }

    var body: some View {
        Form {
            Section(localizer.text(.skillExecutionSection)) {
                Text(localizer.text(.skillExecutionIntro))
                    .accessibilityIdentifier("skillExecution.intro")
                Text(verbatim: localizer.text(.skillExecutionPdfQueryScope))
                    .font(.caption).accessibilityIdentifier("skillExecution.pdfQuery.scope")
                if model.plan == nil {
                    TextField(localizer.text(.skillExecutionPagesPlaceholder), text: $pages)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(localizer.text(.skillExecutionPasswordPlaceholder), text: $password)
                    Toggle(localizer.text(.skillExecutionMetadataOnly), isOn: $metadataOnly)
                    if let download = model.downloadedPDF {
                        Text(verbatim: download.filename).accessibilityIdentifier("downloadPDF.filename")
                        Text(localizer.text(.skillExecutionDownloadSource))
                            .font(.caption).accessibilityIdentifier("downloadPDF.source")
                        Button(localizer.text(.skillExecutionPrepareDownload)) {
                            model.prepareDownload(pages: pages, password: password, metadataOnly: metadataOnly)
                            password = ""
                        }.disabled(!model.downloadAvailable).accessibilityIdentifier("downloadPDF.prepare")
                    } else {
                        Button(localizer.text(.skillExecutionSelectPDF)) { presentPicker(.original) }
                            .accessibilityIdentifier("skillExecutionSelectPDF")
                    }
                    if model.downloadedPDF == nil {
                        Button {
                            importCopyExpanded.toggle()
                        } label: {
                            HStack {
                                Text(localizer.text(.skillExecutionImportCopyToggle))
                                Spacer()
                                Image(systemName: importCopyExpanded ? "chevron.down" : "chevron.right")
                            }
                        }
                        .accessibilityIdentifier("skillExecution.importCopy.options")
                        .accessibilityValue(localizer.text(importCopyExpanded ? .commonExpanded : .commonCollapsed))
                        if importCopyExpanded {
                            Text(localizer.text(.skillExecutionImportCopyNotice))
                                .accessibilityIdentifier("skillExecution.importCopy.notice")
                            Button(localizer.text(.skillExecutionImportCopyButton)) { presentPicker(.importCopy) }
                                .accessibilityIdentifier("skillExecutionImportPDFCopy")
                        }
                    }
                }
                #if DEBUG
                if let fixture = model.uiTestFixture {
                    Text("測試文件已建立：\(fixture.filename)")
                        .font(.caption).accessibilityIdentifier("skillExecution.uitest.fixture")
                        .accessibilityValue(pickerObservation)
                }
                if let audit = model.uiTestAudit {
                    Text(audit.evidence).font(.caption)
                        .accessibilityIdentifier("skillExecution.uitest.audit")
                }
                if let audit = model.downloadUIAudit, let selection = model.downloadedPDF {
                    Text("download=\(selection.downloadID.uuidString) plan=\(model.plan?.id.uuidString ?? "none") reads=\(audit.reads) extractions=\(audit.extractions) results=\(audit.results)")
                        .font(.caption).accessibilityIdentifier("downloadPDF.audit")
                    if let result = model.result {
                        Text(verbatim: result.inputSHA256).font(.caption)
                            .accessibilityIdentifier("downloadPDF.resultDigest")
                    }
                }
                #endif
            }
            if let plan = model.plan {
                Section(localizer.text(.skillExecutionPlanSection)) {
                    Text(plan.filename).accessibilityIdentifier("skillExecution.filename")
                    Text(plan.metadataOnly ? localizer.text(.skillExecutionMetadataOnly)
                         : localizer.text(.skillExecutionPages(value: plan.pages ?? localizer.text(.skillExecutionAllPages))))
                    ForEach(plan.steps) { step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stepTitle(step)).font(.headline)
                            Text(stepDisclosure(step))
                            Text(localizer.text(model.completedStepIDs.contains(step.id) ? .skillExecutionStepDone :
                                (step.availability.available ? .skillExecutionStepNeedsApproval : .skillExecutionStepUnavailable)))
                                .font(.caption)
                            if model.nextStepID == step.id {
                                Button(localizer.text(model.running ? .skillExecutionRunning : .skillExecutionApproveStep)) { model.execute(stepID: step.id) }
                                    .disabled(model.running || !step.availability.available)
                                    .accessibilityIdentifier("skillExecutionApproveStep")
                                    .accessibilityValue(stepTitle(step))
                            }
                        }
                    }
                    DisclosureGroup(localizer.text(.skillExecutionSources)) {
                        Text(localizer.text(.skillExecutionFingerprint(value: plan.fingerprint))).font(.caption).textSelection(.enabled)
                            .accessibilityIdentifier("skillExecution.fingerprint")
                        ForEach(plan.steps.first?.provenance ?? [], id: \.path) { source in
                            Text(localizer.text(.skillExecutionSourceRow(path: source.path, revision: source.revision, sha: source.sha256))).font(.caption).textSelection(.enabled)
                        }
                        Text(localizer.text(.skillExecutionScopedNote))
                    }
                    .accessibilityIdentifier("skillExecution.sources")
                    Button(localizer.text(.skillExecutionClearPlan), role: .destructive) { resetExport(); model.clear(); password = "" }
                        .accessibilityIdentifier("skillExecutionClearPlan")
                }
            }
            if let result = model.result {
                Section(localizer.text(.skillExecutionResultSection)) {
                    Text(localizer.text(.skillExecutionResultSummary(count: result.pageCount, engine: result.engine)))
                        .accessibilityIdentifier("skillExecution.result.summary")
                    Text(resultNotice(result))
                    if !result.text.isEmpty {
                        Text(result.text).textSelection(.enabled).accessibilityIdentifier("skillExecution.result.text")
                        if result.pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Button(localizer.text(.localPDFSearchOpen)) { beginLocalSearch(result) }
                                .disabled(model.running || exportingText)
                                .accessibilityIdentifier("skillExecution.localSearch.open")
                            if localSearchPreparationFailed {
                                Text(verbatim: localizer.text(.localPDFSearchSourceFailed))
                                    .accessibilityIdentifier("skillExecution.localSearch.sourceError")
                            }
                            Button(localizer.text(.skillExecutionQueryPDF)) { beginQuery(result) }
                                .disabled(model.running || exportingText)
                                .accessibilityIdentifier("skillExecution.query")
                        }
                        Button(localizer.text(.skillExecutionExportText)) { beginExport(result) }
                            .disabled(exportingText)
                            .accessibilityIdentifier("skillExecutionExportText")
                    }
                    if let exportStatus {
                        Text(localizer.text(exportStatus)).accessibilityIdentifier("skillExecution.export.status")
                    }
                    ForEach(result.metadata.keys.sorted(), id: \.self) { key in
                        Text(localizer.text(.skillExecutionMetadataRow(key: key, value: result.metadata[key] ?? ""))).textSelection(.enabled)
                    }
                }
            }
            DocumentLocalSearchSection(search: $localSearch, localizer: localizer)
            if let status = model.status { Section { Text(localizer.stored(status)).accessibilityIdentifier("skillExecutionStatus") } }
        }
        .accessibilityIdentifier("skillExecution.form")
        .navigationTitle(localizer.text(.skillExecutionTitle))
        .modifier(PDFImportPresentation(isPresented: $choosingFile, choice: importChoice, experiment: pickerExperiment,
                                       onCompletion: receivePDFSelection, onCancellation: {
            #if DEBUG
            model.recordPickerCancellation()
            #endif
        }, onObservation: { value in
            #if DEBUG
            pickerObservation = value
            #endif
        }, observationNamespace: pickerObservationNamespace))
        .fileExporter(isPresented: $exportingText, document: exportDocument,
                      contentTypes: [.utf8PlainText], defaultFilename: exportFilename,
                      onCompletion: { outcome in
            switch outcome {
            case .success: finishExport(.skillExecutionExportSaved)
            case .failure: finishExport(.skillExecutionExportFailed)
            }
        }, onCancellation: { finishExport(.skillExecutionExportCancelled) })
        .sheet(item: $documentQuery) { presentation in
            NavigationStack {
                DocumentQueryView(source: presentation.source, learning: learning, modelAccess: modelAccess, modelChanges: modelChanges)
            }
        }
        .onChange(of: model.downloadAvailable) { _, available in
            if model.downloadedPDF != nil && !available { resetExport(); documentQuery = nil; localSearch = nil; localSearchPreparationFailed = false }
        }
        .onChange(of: model.plan?.id) { _, _ in localSearch = nil; localSearchPreparationFailed = false }
        .onAppear { if model.downloadedPDF == nil { model.seedUITestIfRequested() } }
        .onDisappear {
            resetExport()
            localSearch = nil
            localSearchPreparationFailed = false
            // The query sheet owns an immutable completed snapshot. Keep the
            // extraction available when returning; leaving its screen otherwise
            // still invalidates the original execution and its grants.
            if documentQuery == nil { model.clear() }
        }
    }

    private func beginLocalSearch(_ result: SkillExecutionPDFResult) {
        guard let plan = model.plan, !model.running, !exportingText else { return }
        localSearchPreparationFailed = false
        do {
            localSearch = DocumentLocalSearch(source: try DocumentTextSnapshot(result: result, filename: plan.filename, catalog: .bundled()))
        } catch {
            localSearch = nil
            localSearchPreparationFailed = true
        }
    }

    private func beginQuery(_ result: SkillExecutionPDFResult) {
        guard let plan = model.plan, !model.running, !exportingText, documentQuery == nil else { return }
        do {
            let source = try DocumentTextSnapshot(result: result, filename: plan.filename, catalog: .bundled())
            documentQuery = DocumentQueryPresentation(source: source)
        } catch { model.status = AppText.skillExecutionStatusNoSnapshot.traditionalFallback }
    }

    private func presentPicker(_ choice: PDFImportChoice) {
        // Every presentation gets an explicit choice; cancelling a copy import
        // cannot change the behavior of the original selection button.
        guard !choosingFile, model.plan == nil else { return }
        importChoice = choice
        #if DEBUG
        model.recordPickerPresentation()
        #endif
        choosingFile = true
    }

    private func receivePDFSelection(_ outcome: Result<[URL], Error>) {
        #if DEBUG
        model.recordImporterCallback(outcome)
        #endif
        switch outcome {
        case .success(let urls):
            guard let url = urls.first, urls.count == 1 else {
                model.status = AppText.skillExecutionStatusNoSelection.traditionalFallback
                return
            }
            model.prepare(url: url, pages: pages, password: password, metadataOnly: metadataOnly)
            password = ""
        case .failure: model.status = AppText.skillExecutionStatusPickFailed.traditionalFallback
        }
    }

    private func beginExport(_ result: SkillExecutionPDFResult) {
        guard let plan = model.plan, !model.running, !result.text.isEmpty else { return }
        do {
            exportDocument = try SkillExecutionTextDocument(text: result.text)
            exportPlanID = plan.id
            exportFilename = localizer.text(.skillExecutionExportName(value: URL(fileURLWithPath: plan.filename).deletingPathExtension().lastPathComponent))
            exportStatus = nil
            exportingText = true
        } catch { exportStatus = .skillExecutionExportTooLarge }
    }

    private func stepTitle(_ step: SkillExecutionStep) -> String {
        switch step.capability {
        case .selectedPDFRead: return localizer.text(.skillExecutionStepReadTitle)
        case .nativePDFText: return localizer.text(.skillExecutionStepExtractTitle)
        }
    }

    private func stepDisclosure(_ step: SkillExecutionStep) -> String {
        switch step.capability {
        case .selectedPDFRead: return localizer.text(.skillExecutionStepReadDisclosure)
        case .nativePDFText: return localizer.text(.skillExecutionStepExtractDisclosure)
        }
    }

    /// SkillExecutionPDFResult.notice in the App language.
    private func resultNotice(_ result: SkillExecutionPDFResult) -> String {
        if result.needsOCR { return localizer.text(.skillExecutionNoticeOCR) }
        if !result.emptyPages.isEmpty {
            return localizer.text(.skillExecutionNoticeEmptyPages(value: result.emptyPages.map(String.init).joined(separator: ", ")))
        }
        return localizer.text(.skillExecutionNoticeCheck)
    }

    private func finishExport(_ message: AppText) {
        // A late dialog callback must not affect a cleared or replaced plan.
        if let exportPlanID, model.plan?.id == exportPlanID { exportStatus = message }
        exportDocument = nil; exportPlanID = nil
    }

    private func resetExport() {
        exportPlanID = nil; exportingText = false; exportDocument = nil; exportStatus = nil
    }
}

#endif

/// Shared execution state: UIKit presentation is separate so the actual caller
/// and its cancellation/publication guards also execute in macOS checks.
@MainActor
final class SkillExecutionViewModel: ObservableObject {
    @Published var plan: SkillExecutionPlan?
    @Published var nextStepID: UUID?
    @Published var completedStepIDs: Set<UUID> = []
    @Published var result: SkillExecutionPDFResult?
    @Published var status: String?
    @Published var running = false
    private var runtime: SkillExecutionRuntime?
    private var task: Task<Void, Never>?
    let downloadedPDF: BrowserDownloadedPDFSelection?
    @Published private(set) var downloadAvailable: Bool
    var executingTask: Task<Void, Never>? { task }

    init(downloadedPDF: BrowserDownloadedPDFSelection? = nil) {
        self.downloadedPDF = downloadedPDF
        downloadAvailable = downloadedPDF?.isValid == true
        #if DEBUG
        if let downloadedPDF, let fixture = BrowserDownloadedPDFFixture.enabled,
           downloadedPDF.filename == fixture.filename { downloadUIAudit = DownloadUIAudit() }
        #endif
        downloadedPDF?.onInvalidated = { [weak self] in
            guard let self else { return }
            self.clear()
            self.downloadAvailable = false
            self.status = "下載檔案已刪除或變更，本次計畫已取消。請重新選取。"
        }
    }

    func prepareDownload(pages: String, password: String, metadataOnly: Bool) {
        clear()
        do {
            guard let downloadedPDF else { throw SkillExecutionError.invalidSelection }
            try prepare(selection: downloadedPDF.selectedFile(), pages: pages, password: password,
                        metadataOnly: metadataOnly)
        } catch { status = (error as? LocalizedError)?.errorDescription ?? "無法建立執行計畫。" }
    }

    private func validateDownload() throws {
        if let downloadedPDF { _ = try downloadedPDF.selectedFile() }
    }
    #if DEBUG
    struct DownloadUIAudit { var reads = 0, extractions = 0, results = 0 }
    @Published private(set) var downloadUIAudit: DownloadUIAudit?
    @Published private(set) var uiTestFixture: SkillExecutionUITestSupport.Fixture?
    @Published private(set) var uiTestAudit: SkillExecutionUITestAudit?
    private var pickerDiagnosticOrdinal = 0
    private var pickerDiagnosticPending = false
    #endif

    func seedUITestIfRequested() {
        #if DEBUG
        guard uiTestFixture == nil else { return }
        do {
            uiTestFixture = try SkillExecutionUITestSupport.seedIfRequested()
            if uiTestFixture != nil { uiTestAudit = SkillExecutionUITestAudit() }
        } catch { status = "測試 PDF 無法建立；請檢查測試命名空間與檔案設定。" }
        #endif
    }

    #if DEBUG
    func recordPickerPresentation() {
        pickerDiagnosticOrdinal = min(pickerDiagnosticOrdinal + 1, 4)
        pickerDiagnosticPending = true
        guard let fixture = uiTestFixture else { return }
        SkillExecutionUITestSupport.recordReadPickerSnapshot(fixture, phase: "prePicker", ordinal: pickerDiagnosticOrdinal)
    }

    func recordPickerCancellation() {
        guard pickerDiagnosticPending, let fixture = uiTestFixture else { return }
        pickerDiagnosticPending = false
        SkillExecutionUITestSupport.recordReadPickerSnapshot(fixture, phase: "cancelled", ordinal: pickerDiagnosticOrdinal)
    }

    func recordImporterCallback(_ outcome: Result<[URL], Error>) {
        // This fixture exists only after the seeder's strict DEBUG test gates
        // pass. Report delivery/counts only, never URLs or error descriptions.
        guard let fixture = uiTestFixture else { return }
        if pickerDiagnosticPending {
            pickerDiagnosticPending = false
            switch outcome {
            case .success(let urls):
                SkillExecutionUITestSupport.recordReadPickerSnapshot(fixture, phase: "selectionReturned",
                    ordinal: pickerDiagnosticOrdinal, returnedURLs: urls)
            case .failure:
                SkillExecutionUITestSupport.recordReadPickerSnapshot(fixture, phase: "selectionFailure", ordinal: pickerDiagnosticOrdinal)
            }
        }
        let outcomeName: String
        let count: String
        switch outcome {
        case .success(let urls): outcomeName = "success"; count = String(urls.count)
        case .failure: outcomeName = "failure"; count = "none"
        }
        print("SKILL_PDF_IMPORTER_CALLBACK namespace=\(fixture.namespace.uuidString) outcome=\(outcomeName) count=\(count) sampledAt=\(Date().timeIntervalSince1970)")
        fflush(stdout)
    }
    #endif

    func prepare(url: URL, pages: String, password: String, metadataOnly: Bool) {
        clear()
        do {
            guard downloadedPDF == nil else { throw SkillExecutionError.invalidSelection }
            try prepare(selection: SkillExecutionSelectedFile(userSelectedURL: url), pages: pages, password: password,
                        metadataOnly: metadataOnly)
            #if DEBUG
            uiTestAudit?.selections += 1
            #endif
        } catch { status = (error as? LocalizedError)?.errorDescription ?? "無法建立執行計畫。" }
    }

    private func prepare(selection: SkillExecutionSelectedFile, pages: String, password: String,
                         metadataOnly: Bool) throws {
        let options = try SkillExecutionPDFOptions(pages: pages, metadataOnly: metadataOnly, password: password.isEmpty ? nil : password)
        let execution = try SkillExecutionRuntime(selectedFile: selection, options: options,
            catalog: BundledSkillCatalog.bundled())
        runtime = execution; plan = execution.plan; nextStepID = execution.plan.steps.first?.id
    }

    func execute(stepID: UUID) {
        guard let runtime, !running else { return }
        do { try validateDownload() }
        catch { return } // Invalidation publishes the fixed cancellation notice.
        let id = runtime.plan.id
        running = true; status = nil
        task = Task {
            do {
                let grant = try await runtime.authorize(stepID: stepID)
                try Task.checkCancellation()
                try validateDownload()
                guard plan?.id == id else { return }
                #if DEBUG
                // Count the actual runtime dispatch, before awaiting it. A missing
                // result alone is not evidence that extraction never started.
                if runtime.plan.steps.first(where: { $0.id == stepID })?.capability == .selectedPDFRead {
                    uiTestAudit?.reads += 1; downloadUIAudit?.reads += 1
                } else { uiTestAudit?.extractionAttempts += 1; downloadUIAudit?.extractions += 1 }
                #endif
                let outcome = try await runtime.execute(grant)
                guard plan?.id == id, !Task.isCancelled else { return }
                try validateDownload()
                guard plan?.id == id, !Task.isCancelled else { return }
                switch outcome {
                case .selectedFileRead(let count, _): status = "已讀取 \(count) 位元組。請核准下一個步驟。"
                case .pdf(let value):
                    result = value; status = "擷取完成。"
                    #if DEBUG
                    uiTestAudit?.results += 1; downloadUIAudit?.results += 1
                    #endif
                }
                completedStepIDs.insert(stepID)
                let next = await runtime.nextStep()?.id
                guard plan?.id == id, !Task.isCancelled else { return }
                try validateDownload()
                nextStepID = next
            } catch {
                guard plan?.id == id else { return }
                status = (error as? SkillExecutionError)?.errorDescription ?? "執行未完成。"
            }
            if plan?.id == id { running = false; task = nil }
        }
    }

    func clear() {
        task?.cancel(); task = nil
        if let runtime { Task { await runtime.cancel() } }
        runtime = nil; plan = nil; nextStepID = nil; completedStepIDs = []; result = nil; status = nil; running = false
    }
}
