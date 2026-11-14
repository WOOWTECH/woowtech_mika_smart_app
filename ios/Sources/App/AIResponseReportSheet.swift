#if os(iOS)
import SwiftUI

/// What 檢舉 AI 回覆 opened: the reply and its plain text, as copied.
struct AIResponseReportTarget: Identifiable {
    let id = UUID()
    let reference: AIResponseReference
    let response: String
}

/// Android AiResponseReportDialog (964d7bec): the saved delivery state of one
/// reply's report, or a reason and an optional note to send one. Every state,
/// text and button follows that dialog, in its order, as a sheet.
@MainActor
struct AIResponseReportSheet: View {
    let target: AIResponseReportTarget
    let delivery: AIResponseReportDelivery
    let localizer: AppLocalizer
    @Environment(\.dismiss) private var dismiss

    @State private var reason = "offensive"
    @State private var note = ""
    @State private var saving = false
    @State private var savedReport: AIResponseReport?
    @State private var failed = false
    @State private var loading = true
    @State private var loadFailed = false
    @State private var ambiguous = false
    @State private var unidentified = false
    @State private var allowUnidentified = false
    @State private var loadVersion = 0
    @State private var manualCompose = false
    @State private var freshWarning = false
    @State private var manualSource: AIResponseReport?
    @State private var manualResponse: String
    @State private var showHistory = false
    @State private var history: [AIResponseReport] = []
    @State private var historyFailed = false
    @State private var reviewExisting = false
    @State private var confirmDelete = false
    @State private var deletionResult: AIResponseReportDeletionResult?
    @State private var deleted = false
    @State private var now = AIResponseReportQueue.currentTimeMs()

    init(target: AIResponseReportTarget, delivery: AIResponseReportDelivery, localizer: AppLocalizer) {
        self.target = target; self.delivery = delivery; self.localizer = localizer
        _manualResponse = State(initialValue: target.response)
    }

    private struct RefreshKey: Equatable {
        let id: String?
        let allowUnidentified: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                responseSection
                if hasNotices { noticeSection }
                historySection
                if !loading && !loadFailed && savedReport == nil { draftSection }
                if hasResults { resultSection }
                if let report = savedReport { savedSection(report) }
            }
            .navigationTitle(localizer.text(.chatReportTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { dismissButton }
                ToolbarItem(placement: .confirmationAction) { confirmButton }
            }
        }
        .interactiveDismissDisabled(saving)
        .accessibilityIdentifier("chat.report")
        .task(id: loadVersion) { await load() }
        .task(id: RefreshKey(id: savedReport?.id, allowUnidentified: allowUnidentified)) { await refreshWhileOpen() }
        .alert(localizer.text(.chatReportDeleteTitle), isPresented: $confirmDelete) {
            Button(localizer.text(.chatReportDelete), role: .destructive) { Task { await deleteReport() } }
                .accessibilityIdentifier("chat.report.delete.confirm")
            Button(localizer.text(.chatReportCancel), role: .cancel) {}
        } message: {
            Text(localizer.text(.chatReportDeleteConfirm))
        }
    }

    // MARK: Sections, in the order of Android's dialog

    private var responseSection: some View {
        Section {
            Text(localizer.text(.chatReportDeliveryNotice))
                .accessibilityIdentifier("chat.report.notice")
            Text(localizer.text(.chatReportReference(reference: target.reference.conversationID,
                                                     message: target.reference.messageKey)))
                .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                .accessibilityIdentifier("chat.report.reference")
            if let selected = savedReport, selected.manualOnly {
                Text(localizer.text(.chatReportSelectedManual))
                Text(verbatim: selected.response)
                Text(reasonLabel(selected.reason))
                if !AIResponseReportQueue.isBlank(selected.note) { Text(verbatim: selected.note) }
            } else {
                Text(verbatim: AIResponseReportQueue.take(manualCompose ? manualResponse : target.response, 300))
                    .lineLimit(5).truncationMode(.tail)
                    .accessibilityIdentifier("chat.report.response")
            }
        }
    }

    private var hasNotices: Bool {
        loading || loadFailed || allowUnidentified || manualCompose || savedReport?.manualOnly == true || freshWarning
    }

    private var noticeSection: some View {
        Section {
            if loading { Text(localizer.text(.chatReportLoading)) }
            if loadFailed {
                Text(localizer.text(unidentified ? .chatReportUnidentified : ambiguous ? .chatReportAmbiguous : .chatReportLoadFailed))
                    .accessibilityIdentifier("chat.report.loadFailed")
            }
            if allowUnidentified { Text(localizer.text(.chatReportContinueNotice)) }
            if manualCompose || savedReport?.manualOnly == true { Text(localizer.text(.chatReportManualNotice)) }
            if freshWarning {
                Text(localizer.text(.chatReportNewWarning)).accessibilityIdentifier("chat.report.newWarning")
            }
        }
    }

    private var historySection: some View {
        Section {
            Button(localizer.text(.chatReportHistory)) { Task { await loadHistory() } }
                .disabled(saving)
                .accessibilityIdentifier("chat.report.history")
            if historyFailed { Text(localizer.text(.chatReportLoadFailed)) }
            if reviewExisting { Text(localizer.text(.chatReportReviewExisting)) }
            if showHistory {
                Text(localizer.text(.chatReportHistoryNotice))
                if history.isEmpty { Text(localizer.text(.chatReportHistoryEmpty)) }
                ForEach(history, id: \.id) { report in
                    Button { select(report) } label: {
                        Text(verbatim: report.id + "\n" + AIResponseReportQueue.take(report.response, 200))
                            .lineLimit(4).truncationMode(.tail)
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private var draftSection: some View {
        Section {
            ForEach(AIResponseReportQueue.reasons, id: \.self) { id in
                Button { reason = id } label: {
                    HStack {
                        Text(reasonLabel(id)).foregroundStyle(Color.primary)
                        Spacer()
                        if reason == id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .disabled(saving)
                .accessibilityAddTraits(reason == id ? .isSelected : [])
                .accessibilityIdentifier("chat.report.reason." + id)
            }
            TextField(localizer.text(.chatReportNote), text: $note, axis: .vertical)
                .lineLimit(2...4)
                .disabled(saving)
                .onChange(of: note) { _, value in
                    let kept = AIResponseReportQueue.take(value, AIResponseReportQueue.maximumNote)
                    if kept != value { note = kept }
                }
                .accessibilityIdentifier("chat.report.note")
        }
    }

    private var hasResults: Bool {
        failed || deleted || deletionResult == .retryable || deletionResult == .cannotVerify
    }

    private var resultSection: some View {
        Section {
            if failed { Text(localizer.text(.chatReportSaveFailed)).accessibilityIdentifier("chat.report.saveFailed") }
            if deleted { Text(localizer.text(.chatReportDeleted)).accessibilityIdentifier("chat.report.deleted") }
            if deletionResult == .retryable { Text(localizer.text(.chatReportDeleteFailed)) }
            if deletionResult == .cannotVerify { Text(localizer.text(.chatReportDeleteUnverified)) }
        }
    }

    private func savedSection(_ report: AIResponseReport) -> some View {
        Section {
            Text(statusText(report)).accessibilityIdentifier("chat.report.status")
            Button(localizer.text(.chatReportDelete), role: .destructive) { deletionResult = nil; confirmDelete = true }
                .disabled(saving)
                .accessibilityIdentifier("chat.report.delete")
        }
    }

    // MARK: Buttons

    private var dismissButton: some View {
        Button(localizer.text(freshWarning ? .chatReportBack : savedReport == nil ? .chatReportCancel : .chatReportClose)) {
            if freshWarning { freshWarning = false } else { dismiss() }
        }
        .disabled(saving)
        .accessibilityIdentifier("chat.report.dismiss")
    }

    @ViewBuilder private var confirmButton: some View {
        Group {
            if freshWarning && !loading {
                Button(localizer.text(.chatReportContinueRisk)) { continueFromOldReport() }
            } else if loadFailed && !loading && ambiguous {
                Button(localizer.text(.chatReportContinueRisk)) {
                    allowUnidentified = true; manualSource = nil; manualResponse = target.response
                    manualCompose = true; loadFailed = false; showHistory = false
                }
            } else if loadFailed && !loading && unidentified {
                Button(localizer.text(.chatReportContinueRisk)) { allowUnidentified = true; loadVersion += 1 }
            } else if loadFailed && !loading {
                Button(localizer.text(.chatReportRetry)) { loadVersion += 1 }
            } else if !loading && !loadFailed && savedReport == nil {
                Button(localizer.text(.chatReportSubmit)) { Task { await submit() } }.disabled(saving)
            } else if !loading && !loadFailed, let report = savedReport, report.status != .acknowledged,
                      report.outsideIntakeWindow(now: now) {
                Button(localizer.text(.chatReportCreateNew)) { freshWarning = true }
            } else if !loading && !loadFailed, let report = savedReport, report.status != .acknowledged {
                Button(localizer.text(.chatReportRetry)) { Task { await retryDelivery() } }.disabled(saving)
            }
        }
        .accessibilityIdentifier("chat.report.confirm")
    }

    // MARK: Text

    private func reasonLabel(_ id: String) -> String {
        switch id {
        case "offensive": return localizer.text(.chatReportOffensive)
        case "unsafe": return localizer.text(.chatReportUnsafe)
        default: return localizer.text(.chatReportOther)
        }
    }

    private func statusText(_ report: AIResponseReport) -> String {
        if report.status == .acknowledged { return localizer.text(.chatReportAcknowledged(reference: report.id)) }
        if report.outsideIntakeWindow(now: now) { return localizer.text(.chatReportExpired(reference: report.id)) }
        if report.status == .rejected || report.attempts >= AIResponseReportDelivery.maximumAttempts {
            return localizer.text(.chatReportNeedsRetry(reference: report.id))
        }
        return localizer.text(.chatReportPending(reference: report.id))
    }

    // MARK: Actions

    private func load() async {
        loading = true
        do {
            savedReport = try await delivery.find(target.reference, allowUnidentified: allowUnidentified)
            loadFailed = false; ambiguous = false; unidentified = false
        } catch {
            loadFailed = true
            ambiguous = error as? AIResponseReportError == .damagedReference
            unidentified = error as? AIResponseReportError == .unidentified
        }
        loading = false
    }

    /// Android rereads the report every five seconds, so a send that finished
    /// in the background shows here.
    private func refreshWhileOpen() async {
        guard let report = savedReport else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            now = AIResponseReportQueue.currentTimeMs()
            let manual = savedReport?.manualOnly ?? report.manualOnly
            let current = try? await delivery.report(report.id, manual: manual, allowUnidentified: allowUnidentified)
            if !saving, let current { savedReport = current }
        }
    }

    private func loadHistory() async {
        do {
            history = try await delivery.manualReports(conversationID: target.reference.conversationID,
                                                        allowUnidentified: allowUnidentified)
            showHistory = true; historyFailed = false
        } catch AIResponseReportError.unidentified {
            loadFailed = true; unidentified = true
        } catch {
            historyFailed = true
        }
    }

    private func select(_ report: AIResponseReport) {
        savedReport = report; manualCompose = false; freshWarning = false
        loadFailed = false; showHistory = false; failed = false; reviewExisting = false
    }

    /// The old report was never confirmed in time: write a new one from it.
    private func continueFromOldReport() {
        guard let source = savedReport else { return }
        manualSource = source; manualResponse = source.response
        reason = source.reason; note = source.note
        savedReport = nil; manualCompose = true; freshWarning = false; showHistory = false
    }

    private func submit() async {
        guard !saving else { return }
        saving = true; failed = false; reviewExisting = false
        let report: AIResponseReport
        do {
            if manualCompose {
                report = try await delivery.createManual(manualSource?.reference ?? target.reference, response: manualResponse,
                                                         reason: reason, note: note, sourceID: manualSource?.id,
                                                         allowUnidentified: allowUnidentified)
            } else {
                report = try await delivery.save(target.reference, response: target.response, reason: reason, note: note,
                                                 allowUnidentified: allowUnidentified)
            }
        } catch AIResponseReportError.existingManual(let existing) {
            savedReport = existing; manualCompose = false; reviewExisting = true; saving = false
            return
        } catch AIResponseReportError.unidentified {
            loadFailed = true; unidentified = true; saving = false
            return
        } catch {
            failed = true; saving = false
            return
        }
        savedReport = report; manualCompose = false; saving = false
        do {
            let delivered: AIResponseReport?
            if report.status == .acknowledged { delivered = report }
            else if report.manualOnly { delivered = try await delivery.sendManual(report.id, allowUnidentified: allowUnidentified) }
            else if allowUnidentified { delivered = try await delivery.deliverOne(report.id) }
            else {
                try await delivery.deliverDue()
                delivered = try await delivery.report(report.id, manual: false, allowUnidentified: false)
            }
            if let delivered { savedReport = delivered }
        } catch AIResponseReportError.unidentified {
            loadFailed = true; unidentified = true
        } catch {}
    }

    private func retryDelivery() async {
        guard !saving, let current = savedReport else { return }
        saving = true; failed = false
        do {
            if current.manualOnly { savedReport = try await delivery.sendManual(current.id, allowUnidentified: allowUnidentified) }
            else { savedReport = try await delivery.retry(current.id, allowUnidentified: allowUnidentified) }
        } catch AIResponseReportError.unidentified {
            loadFailed = true; unidentified = true
        } catch {
            failed = true
        }
        now = AIResponseReportQueue.currentTimeMs()
        saving = false
    }

    private func deleteReport() async {
        guard let id = savedReport?.id else { return }
        saving = true
        let result = (try? await delivery.delete(id, allowUnidentified: allowUnidentified)) ?? .retryable
        deletionResult = result
        if result == .deleted {
            savedReport = nil
            history.removeAll { $0.id == id }
            showHistory = false
            deleted = true
            loadVersion += 1
        }
        saving = false
    }
}
#endif
