import AssistantSkills
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Host passes the actual configured access plus a publisher that fires whenever
/// that configuration/credential changes. Saved references are read-only snapshots.
@MainActor struct TranscriptView: View {
    let modelAccess: () throws -> ModelAccess
    let modelChanges: AnyPublisher<Void, Never>
    let approvedSource: TranscriptSnapshot?
    @StateObject private var session: TranscriptSession
    @State private var choosing = false
    @State private var format: TranscriptFormat = .summary
    @State private var loadedApprovedSource: UUID?
    @State private var sourceExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer
    #if DEBUG
    @State private var fixtureNotice: String?
    #endif

    init(learning: LearningStore, modelAccess: @escaping () throws -> ModelAccess, modelChanges: AnyPublisher<Void, Never>,
         approvedSource: TranscriptSnapshot? = nil) {
        _session = StateObject(wrappedValue: TranscriptSession(learning: learning))
        self.modelAccess = modelAccess; self.modelChanges = modelChanges; self.approvedSource = approvedSource
    }

    var body: some View {
        Form {
            Section {
                Text(localizer.stored(session.status)).accessibilityIdentifier("transcript.status")
                Text(localizer.text(.transcriptScope))
                if let error = session.error {
                    Text(verbatim: localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("transcript.error")
                }
                Button(localizer.text(.catalogTranscriptOpen)) { choosing = true }
                    .disabled(session.running).accessibilityIdentifier("transcript.choose")
                #if DEBUG
                Text(session.diagnostic).font(.caption).accessibilityIdentifier("transcript.diagnostic")
                if let fixtureNotice {
                    Text(verbatim: fixtureNotice).accessibilityIdentifier("transcript.uitest.fixture")
                    Text(session.audit.evidence).font(.caption).accessibilityIdentifier("transcript.uitest.audit")
                }
                #endif
            }
            if let review = session.review {
                Section(localizer.text(.transcriptReviewSection)) {
                    Text(verbatim: review.filename).accessibilityIdentifier("transcript.review.filename")
                    Text(localizer.text(.transcriptReviewNote))
                    Button(localizer.text(.transcriptApproveRead)) { session.approveRead() }
                        .disabled(session.running).accessibilityIdentifier("transcript.approveRead")
                    Button(localizer.text(.transcriptRefuseRead), role: .cancel) { session.cancel() }
                        .accessibilityIdentifier("transcript.refuse")
                }
            }
            if let source = session.snapshot {
                Section(localizer.text(.transcriptSnapshotSection)) {
                    Text(verbatim: source.filename).accessibilityIdentifier("transcript.filename")
                    Text(localizer.text(.transcriptSnapshotSize(count: source.byteCount)))
                    if let url = source.sourceURL {
                        Text(verbatim: url.absoluteString).font(.caption).accessibilityIdentifier("transcript.sourceURL")
                    }
                    Button(localizer.text(sourceExpanded ? .transcriptHideSource : .transcriptShowSource)) { sourceExpanded.toggle() }
                        .accessibilityIdentifier("transcript.showSource")
                    if sourceExpanded {
                        Text(verbatim: source.text).textSelection(.enabled).accessibilityIdentifier("transcript.source")
                    }
                    Text(localizer.text(.transcriptSHA(value: source.sha256))).font(.caption).textSelection(.enabled)
                }
                Section(localizer.text(.transcriptSendSection)) {
                    Picker(localizer.text(.transcriptFormatPicker), selection: $format) {
                        ForEach(TranscriptFormat.allCases, id: \.self) { value in Text(localizer.text(.transcriptFormat(value))).tag(value) }
                    }.disabled(session.running).accessibilityIdentifier("transcript.format")
                    if let destination = session.destination {
                        Text(verbatim: localizer.stored(destination)).accessibilityIdentifier("transcript.destination")
                    }
                    Button(localizer.text(.documentQueryConfirmDestination)) { session.confirmDestination(modelAccess: modelAccess) }
                        .disabled(session.running).accessibilityIdentifier("transcript.confirmDestination")
                    Text(localizer.text(.transcriptReferenceNotice))
                        .accessibilityIdentifier("transcript.referenceNotice")
                    Button(localizer.text(.transcriptStart)) { session.start(format: format, modelAccess: modelAccess) }
                        .disabled(session.destination == nil || session.running).accessibilityIdentifier("transcript.start")
                }
            }
            if let refusal = session.refusal {
                Section(localizer.text(.transcriptRefusalSection)) { Text(verbatim: refusal).accessibilityIdentifier("transcript.refusal") }
            }
            if let result = session.result {
                Section(localizer.text(.transcriptResultSection)) {
                    Text(verbatim: result.title).font(.headline).accessibilityIdentifier("transcript.result")
                    Text(localizer.text(.transcriptResultNote))
                    ForEach(result.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: section.title).font(.headline)
                            Text(verbatim: section.text).textSelection(.enabled)
                                .accessibilityIdentifier("transcript.section.\(section.id)")
                            ForEach(Array(section.evidence.enumerated()), id: \.offset) { index, evidence in
                                VStack(alignment: .leading) {
                                    Text(localizer.text(evidence.timestamp.map { .transcriptEvidenceTimed(offset: evidence.offset, time: $0) }
                                                       ?? .transcriptEvidence(offset: evidence.offset)))
                                        .font(.caption)
                                    Text(verbatim: evidence.quote).textSelection(.enabled)
                                        .accessibilityIdentifier("transcript.evidence.\(section.id).\(index)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("transcript.form")
        .navigationTitle(localizer.text(.catalogTranscriptSection))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.commonDone)) { session.cancel(notice: false); dismiss() }.accessibilityIdentifier("transcript.close")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.running {
                Button(localizer.text(.transcriptStop)) { session.cancel() }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("transcript.cancel").padding()
                    .frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: Self.allowedTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard urls.count == 1, let url = urls.first else { session.selectionFailed(); return }
                session.select(url)
            case .failure: session.selectionFailed()
            }
        }
        .onAppear {
            if let approvedSource, loadedApprovedSource != approvedSource.id {
                session.loadApprovedSource(approvedSource); loadedApprovedSource = approvedSource.id
            }
            #if DEBUG
            do {
                if let fixture = try TranscriptUITestSupport.seedIfRequested() {
                    fixtureNotice = "測試文字檔已建立：" + fixture.filename
                }
            } catch { fixtureNotice = "測試文字檔建立失敗。" }
            #endif
        }
        .onReceive(modelChanges) { session.hostChanged() }
        .onDisappear { session.cancel(notice: false) }
    }

    private static var allowedTypes: [UTType] {
        [.plainText] + ["txt", "srt", "vtt", "md"].compactMap { UTType(filenameExtension: $0) }
    }
}
