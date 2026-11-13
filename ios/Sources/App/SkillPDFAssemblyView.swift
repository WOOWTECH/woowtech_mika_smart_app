import AssistantSkills
import SwiftUI
import UniformTypeIdentifiers
#if DEBUG && os(iOS)
import Darwin
#endif

/// A bounded immutable PDF snapshot. The native exporter owns the destination
/// dialog and any explicit user confirmation to replace an existing file.
struct SkillPDFAssemblyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(data: Data) throws {
        guard data.starts(with: Data("%PDF-".utf8)), data.count <= SkillPDFAssemblyLimits.outputBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    init(configuration: ReadConfiguration) throws {
        guard configuration.file.isRegularFile, let bytes = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: bytes)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        snapshot()
    }
    func snapshot() -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

#if os(iOS)
@MainActor
struct SkillPDFAssemblyView: View {
    @StateObject private var model = SkillPDFAssemblySession()
    @State private var choosingFile = false
    @State private var pickerRequest: SkillPDFAssemblySession.PickerRequest?
    @State private var importChoice: PDFImportChoice = .original
    @State private var exporting = false
    @State private var exportDocument: SkillPDFAssemblyDocument?
    @State private var exportPlanID: UUID?
    @State private var exportStatus: AppText?
    @FocusState private var orderFocused: Bool
    @Environment(\.appLocalizer) private var localizer
    #if DEBUG
    @State private var pickerObservation = "unobserved"
    @State private var importerCallbacks = 0
    @State private var importerOutcome = "none"
    @State private var totalImporterCallbacks = 0
    #endif

    private var pickerExperiment: PDFNativePickerExperiment.Configuration? {
        #if DEBUG
        return PDFNativePickerExperiment.assemblyConfiguration(arguments: ProcessInfo.processInfo.arguments,
                                                               fixtureNamespace: model.uiTestFixture?.namespace ?? model.uiTestPair?.namespace)
        #else
        return nil
        #endif
    }

    var body: some View {
        let request = pickerRequest
        Form {
            Section(localizer.text(.pdfAssemblySection)) {
                Text(localizer.text(.pdfAssemblyIntro))
                Text(localizer.text(.pdfAssemblySupport))
                    .font(.caption)
                if model.sources.isEmpty {
                    Button(localizer.text(.pdfAssemblySelect)) { presentPicker(.original) }
                        .accessibilityIdentifier("pdfAssembly.select")
                    Text(localizer.text(.pdfAssemblyImportCopyNotice))
                        .font(.caption).accessibilityIdentifier("pdfAssembly.importCopy.notice")
                    Button(localizer.text(.pdfAssemblyImportCopy)) { presentPicker(.importCopy) }
                        .accessibilityIdentifier("pdfAssembly.importCopy")
                }
                #if DEBUG
                if let fixture = model.uiTestFixture {
                    Text("測試文件已建立：\(fixture.filename)")
                        .font(.caption).accessibilityIdentifier("pdfAssembly.uitest.fixture")
                        .accessibilityValue(pickerObservation + " callbacks=\(importerCallbacks)")
                }
                if let pair = model.uiTestPair {
                    Text("測試雙檔已建立")
                        .font(.caption).accessibilityIdentifier("pdfAssembly.uitest.pair")
                        .accessibilityValue("callbacks=\(totalImporterCallbacks) sources=\(model.sources.count)" +
                            (totalImporterCallbacks == 0 && model.sources.isEmpty ? " " + pair.creationProof.accessibilityValue : ""))
                }
                #endif
            }
            if !model.sources.isEmpty {
                Section(localizer.text(.pdfAssemblySourcesSection)) {
                    ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizer.text(.pdfAssemblySource(number: index + 1, name: source.filename)))
                                .accessibilityIdentifier("pdfAssembly.source.\(index + 1)")
                                #if DEBUG
                                .accessibilityValue(model.uiTestPair == nil ? "" :
                                    pickerObservation + " callbacks=\(importerCallbacks) outcome=\(importerOutcome) sources=\(model.sources.count)")
                                #endif
                            if let receipt = model.receipts.first(where: { $0.id == source.id }) {
                                Text(localizer.text(.pdfAssemblyReceipt(pages: receipt.pageCount, bytes: receipt.byteCount)))
                                    .accessibilityIdentifier("pdfAssembly.receipt.\(index + 1)")
                                    #if DEBUG
                                    .accessibilityValue(model.uiTestPair == nil ? "" :
                                        "sources=\(model.sources.count) reads=\(model.receipts.count)")
                                    #endif
                            } else {
                                Text(localizer.text(.pdfAssemblySourceDisclosure)).font(.caption)
                                Button(localizer.text(.pdfAssemblyApproveRead)) { orderFocused = false; model.read(source.id) }
                                    .disabled(model.running)
                                    .accessibilityIdentifier("pdfAssembly.read.\(index + 1)")
                            }
                        }
                    }
                    Text(localizer.text(.pdfAssemblyAddNotice))
                        .font(.caption).accessibilityIdentifier("pdfAssembly.add.notice")
                    Button(localizer.text(.pdfAssemblyAdd)) { presentPicker(.original, adding: true) }
                        .disabled(!model.canAdd || choosingFile || exporting)
                        .accessibilityIdentifier("pdfAssembly.add")
                    Button(localizer.text(.pdfAssemblyAddCopy)) { presentPicker(.importCopy, adding: true) }
                        .disabled(!model.canAdd || choosingFile || exporting)
                        .accessibilityIdentifier("pdfAssembly.addCopy")
                    Text(localizer.text(.pdfAssemblySourcesNote))
                        .font(.caption)
                }
            }
            if model.receipts.count == model.sources.count && !model.sources.isEmpty && model.result == nil {
                Section(localizer.text(.pdfAssemblyOrderSection)) {
                    Text(localizer.text(.pdfAssemblyOrderHelp))
                        .font(.caption)
                    TextField(localizer.text(.pdfAssemblyOrderPlaceholder), text: $model.orderText, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($orderFocused).disabled(model.running)
                        .accessibilityIdentifier("pdfAssembly.order")
                        .onChange(of: model.orderText) { _, _ in model.invalidatePlan() }
                    Button(localizer.text(.pdfAssemblyPrepare)) { orderFocused = false; model.prepare() }
                        .disabled(!model.canPrepare).accessibilityIdentifier("pdfAssembly.prepare")
                }
            }
            if let plan = model.plan, model.result == nil {
                Section(localizer.text(.pdfAssemblyPlanSection)) {
                    Text(localizer.text(.pdfAssemblyPlanCount(count: plan.order.count))).accessibilityIdentifier("pdfAssembly.plan.count")
                    ForEach(Array(plan.order.enumerated()), id: \.offset) { index, page in
                        let number = (model.sources.firstIndex(where: { $0.id == page.sourceID }) ?? -1) + 1
                        Text(localizer.text(.pdfAssemblyPlanPage(index: index + 1, source: number, page: page.number)))
                            .accessibilityIdentifier("pdfAssembly.plan.page.\(index + 1)")
                    }
                    Text(localizer.text(.pdfAssemblyPlanNote))
                    Button(localizer.text(.pdfAssemblyAssemble)) { model.assemble() }
                        .disabled(model.running).accessibilityIdentifier("pdfAssembly.assemble")
                }
            }
            if let result = model.result {
                Section(localizer.text(.pdfAssemblyResultSection)) {
                    Text(localizer.text(.pdfAssemblyResult(pages: result.pageCount, bytes: result.data.count)))
                        .accessibilityIdentifier("pdfAssembly.result")
                        #if DEBUG
                        .accessibilityValue(model.uiTestPair == nil ? "" : model.uiTestPairOutput)
                        #endif
                    Text(localizer.text(.pdfAssemblyResultNotice)).font(.caption)
                    Button(localizer.text(.pdfAssemblySave)) { beginExport(result) }
                        .disabled(exporting).accessibilityIdentifier("pdfAssembly.export")
                    Text(localizer.text(.pdfAssemblySaveNote))
                        .font(.caption)
                    if let exportStatus { Text(localizer.text(exportStatus)).accessibilityIdentifier("pdfAssembly.export.status") }
                }
            }
            if model.running { ProgressView(localizer.text(.pdfAssemblyProcessing)).accessibilityIdentifier("pdfAssembly.running") }
            if let status = model.status { Text(localizer.stored(status)).accessibilityIdentifier("pdfAssembly.status") }
            if !model.sources.isEmpty {
                Button(localizer.text(model.running ? .pdfAssemblyCancelAndClear : .pdfAssemblyClear), role: .destructive) {
                    resetExport(); model.clear()
                }.accessibilityIdentifier("pdfAssembly.clear")
            }
        }
        .navigationTitle(localizer.text(.pdfAssemblyTitle))
        .accessibilityIdentifier("pdfAssembly.form")
        .onAppear {
            #if DEBUG
            model.seedUITestIfRequested()
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.commonHideKeyboard)) { orderFocused = false }.accessibilityIdentifier("pdfAssembly.keyboardDone")
            }
        }
        .modifier(PDFImportPresentation(isPresented: $choosingFile, choice: importChoice, experiment: pickerExperiment,
                                       allowsMultipleSelection: false,
                                       onCompletion: { receiveSelection($0, request: request) },
                                       onCancellation: {
            guard let request else { return }
            model.cancelPicker(request)
            if pickerRequest == request { pickerRequest = nil }
        },
                                       onObservation: { value in
            #if DEBUG
            pickerObservation = value
            #endif
        }))
        .onChange(of: choosingFile) { _, presented in
            #if DEBUG
            if presented { importerCallbacks = 0; pickerObservation = "unobserved"; importerOutcome = "none" }
            recordPickerEvent("bindingChanged presented=\(presented)")
            #endif
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentTypes: [.pdf],
                      defaultFilename: model.result.map { localizer.text(.pdfAssemblySuggestedName(value: $0.plan.id.uuidString)) }
                          ?? localizer.text(.pdfAssemblyDefaultName), onCompletion: { outcome in
            switch outcome {
            case .success: finishExport(.pdfAssemblySaved)
            case .failure: finishExport(.pdfAssemblySaveFailed)
            }
        }, onCancellation: { finishExport(.pdfAssemblySaveCancelled) })
        .onDisappear {
            #if DEBUG
            recordPickerEvent("viewDisappeared choosingFile=\(choosingFile) exporting=\(exporting)")
            #endif
            if !choosingFile && !exporting { resetExport(); model.clear() }
        }
    }

    private func presentPicker(_ choice: PDFImportChoice, adding: Bool = false) {
        guard !choosingFile, !exporting, let request = model.beginPicker(adding: adding) else { return }
        pickerRequest = request
        importChoice = choice
        choosingFile = true
    }

    private func receiveSelection(_ outcome: Result<[URL], Error>, request: SkillPDFAssemblySession.PickerRequest?) {
        guard let request else { return }
        #if DEBUG
        importerCallbacks = min(importerCallbacks + 1, 16)
        totalImporterCallbacks = min(totalImporterCallbacks + 1, 16)
        let category: String
        switch outcome {
        case .success(let urls): category = urls.isEmpty ? "empty" : urls.count == 1 ? "one" : "multiple"
        case .failure: category = "failure"
        }
        importerOutcome = category
        recordPickerEvent("completion outcome=\(category)")
        #endif
        switch outcome {
        case .success(let urls):
            if model.finishPicker(request, urls: urls) { resetExport() }
        case .failure: model.pickerFailed(request)
        }
        if pickerRequest == request { pickerRequest = nil }
    }

    #if DEBUG
    private func recordPickerEvent(_ event: String) {
        guard let configuration = pickerExperiment, importerCallbacks < 16 else { return }
        let source = importChoice == .importCopy ? "user-copy" : configuration.source
        print("SKILL_PDF_ASSEMBLY_PICKER namespace=\(configuration.namespace.uuidString) source=\(source) event=\(event) callbacks=\(importerCallbacks) sampledAt=\(Date().timeIntervalSince1970)")
        fflush(stdout)
    }
    #endif

    private func beginExport(_ result: SkillPDFAssemblyResult) {
        do {
            exportDocument = try SkillPDFAssemblyDocument(data: result.data)
            exportPlanID = result.plan.id; exportStatus = nil; exporting = true
        } catch { exportStatus = .pdfAssemblyExportUnavailable }
    }
    private func finishExport(_ message: AppText) {
        if exportPlanID == model.result?.plan.id { exportStatus = message }
        #if DEBUG
        model.observeUITestPairOutput()
        #endif
        exportDocument = nil; exportPlanID = nil
    }
    private func resetExport() {
        exporting = false; exportDocument = nil; exportPlanID = nil; exportStatus = nil
    }
}
#endif
