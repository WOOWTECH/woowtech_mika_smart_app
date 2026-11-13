import AssistantSkills
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DocumentQueryView: View {
    let modelAccess: () throws -> ModelAccess
    let modelChanges: AnyPublisher<Void, Never>
    @StateObject private var session: DocumentQuerySession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var questionFocused: Bool
    @State private var exporting = false
    @State private var exportDocument: SkillExecutionTextDocument?
    @State private var exportDeliveryID: UUID?
    @State private var exportStatus: AppText?
    @Environment(\.appLocalizer) private var localizer

    init(source: DocumentTextSnapshot, learning: LearningStore, modelAccess: @escaping () throws -> ModelAccess,
         modelChanges: AnyPublisher<Void, Never>) {
        self.modelAccess = modelAccess; self.modelChanges = modelChanges
        _session = StateObject(wrappedValue: DocumentQuerySession(source: source, learning: learning))
    }

    var body: some View {
        Form {
            Section(localizer.text(.documentQuerySourceSection)) {
                Text(verbatim: session.source.filename).accessibilityIdentifier("documentQuery.filename")
                Text(localizer.text(.documentQuerySourceSummary(pages: session.source.pages.count, bytes: session.source.byteCount)))
                Text(localizer.text(.documentQuerySourceNote))
                    .font(.caption)
                DisclosureGroup(localizer.text(.documentQuerySourceInfo)) {
                    Text(verbatim: session.source.engine)
                    Text(localizer.text(.documentQueryPdfHash(value: session.source.inputSHA256))).font(.caption).textSelection(.enabled)
                    Text(localizer.text(.documentQuerySnapshotHash(value: session.source.sha256))).font(.caption).textSelection(.enabled)
                }
            }
            Section(localizer.text(.documentQueryQuestionSection)) {
                TextEditor(text: Binding(get: { session.question }, set: { session.setQuestion($0) }))
                    .frame(minHeight: 100).focused($questionFocused)
                    .disabled(session.running || exporting)
                    .accessibilityIdentifier("documentQuery.question")
                Button(localizer.text(.documentQueryConfirmDestination)) { session.confirmDestination(modelAccess: modelAccess) }
                    .disabled(session.running || exporting)
                    .accessibilityIdentifier("documentQuery.confirmDestination")
                if let destination = session.destination {
                    Text(verbatim: localizer.stored(destination)).accessibilityIdentifier("documentQuery.destination")
                }
                Text(localizer.text(.documentQueryDisclosure))
                    .font(.caption)
                Button(localizer.text(.documentQueryStart)) {
                    questionFocused = false; session.start(modelAccess: modelAccess)
                }
                .disabled(session.running || exporting || session.destination == nil
                          || session.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("documentQuery.start")
            }
            Section {
                statusLabel
                if session.running { ProgressView(localizer.text(.documentQueryProgress)) }
                if let error = session.error {
                    Text(verbatim: localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("documentQuery.error")
                }
                if let refusal = session.refusal {
                    Text(verbatim: refusal).accessibilityIdentifier("documentQuery.refusal")
                }
            }
            if let result = session.result {
                Section(localizer.text(.documentQueryAnswerSection)) {
                    Text(verbatim: result.question).font(.caption).accessibilityIdentifier("documentQuery.answeredQuestion")
                    Text(verbatim: result.answer).textSelection(.enabled).accessibilityIdentifier("documentQuery.answer")
                    Text(localizer.text(.documentQueryCitationNote))
                        .font(.caption)
                    ForEach(Array(result.citations.enumerated()), id: \.offset) { index, citation in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(localizer.text(.documentQueryCitationPage(page: citation.pageNumber, index: citation.pageIndex)))
                                .font(.caption).accessibilityIdentifier("documentQuery.citation.page.\(index)")
                            Text(verbatim: citation.quote).textSelection(.enabled)
                                .accessibilityIdentifier("documentQuery.citation.quote.\(index)")
                        }
                    }
                    Button(localizer.text(.documentQueryExport)) { beginExport() }
                        .disabled(exporting || session.running)
                        .accessibilityIdentifier("documentQuery.export")
                    if let exportStatus {
                        Text(localizer.text(exportStatus)).accessibilityIdentifier("documentQuery.exportStatus")
                    }
                }
            }
        }
        .accessibilityIdentifier("documentQuery.form")
        .navigationTitle(localizer.text(.documentQueryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.commonDone)) { session.cancel(notice: false); dismiss() }
                    .accessibilityIdentifier("documentQuery.close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.commonDoneTyping)) { questionFocused = false }
                    .accessibilityIdentifier("documentQuery.keyboardDone")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.running {
                Button(localizer.text(.documentQueryStop)) { session.cancel() }
                    .buttonStyle(.borderedProminent).padding()
                    .frame(maxWidth: .infinity).background(.regularMaterial)
                    .accessibilityIdentifier("documentQuery.cancel")
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentTypes: [.utf8PlainText], defaultFilename: localizer.text(.documentQueryExportName),
                      onCompletion: { result in
            switch result {
            case .success: finishExport(.documentQueryExportSaved)
            case .failure: finishExport(.documentQueryExportFailed)
            }
        }, onCancellation: { finishExport(.documentQueryExportCancelled) })
        .onReceive(modelChanges) { session.hostChanged() }
        .onChange(of: session.deliveryID) { _, _ in resetExport() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && session.running { session.cancel() }
        }
        .onDisappear { session.cancel(notice: false); resetExport() }
    }

    private var statusLabel: some View {
        #if DEBUG
        Text(localizer.stored(session.status)).accessibilityIdentifier("documentQuery.status")
            .accessibilityValue(session.audit.evidence)
        #else
        Text(localizer.stored(session.status)).accessibilityIdentifier("documentQuery.status")
        #endif
    }

    private func beginExport() {
        guard let result = session.result, let id = session.deliveryID, !session.running else { return }
        do {
            exportDocument = try SkillExecutionTextDocument(text: result.textForExport)
            exportDeliveryID = id; exportStatus = nil; exporting = true
        } catch { exportStatus = .documentQueryExportUnavailable }
    }

    private func finishExport(_ message: AppText) {
        guard let exportDeliveryID, exportDeliveryID == session.deliveryID else { return }
        exportStatus = message; self.exportDeliveryID = nil; exportDocument = nil; exporting = false
    }

    private func resetExport() {
        exportDeliveryID = nil; exportDocument = nil; exporting = false; exportStatus = nil
    }
}
