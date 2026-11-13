import AssistantBrowser
import SwiftUI
import UIKit

/// Standalone sheet content. Parent owns/passes the workspace's shared manager.
@MainActor
struct BrowserDownloadsView: View {
    @ObservedObject var manager: BrowserDownloadManager
    var pdfDestination: ((BrowserDownloadedPDFSelection) -> AnyView)? = nil
    @State private var selectedPDF: BrowserDownloadedPDFSelection?
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: BrowserDownloadItem?
    @State private var sharing: SharedFile?
    @State private var actionError: String?
    @Environment(\.appLocalizer) private var localizer

    private struct SharedFile: Identifiable {
        let id: UUID
        let url: URL
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = manager.errorMessage {
                    Section {
                        Text(localizer.stored(error)).foregroundStyle(.red)
                        Button(localizer.text(.commonDismissNotice)) { manager.clearError() }
                    }
                }
                if manager.items.isEmpty {
                    ContentUnavailableView(localizer.text(.downloadEmptyTitle), systemImage: "arrow.down.circle",
                                           description: Text(localizer.text(.downloadEmptyHelp)))
                }
                ForEach(manager.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.fileName).font(.headline).lineLimit(2)
                        HStack {
                            Text(localizer.text(.downloadStatus(item.status)))
                            Spacer()
                            Text(sizeDescription(item)).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                        if item.status == .downloading || item.status == .waiting {
                            if let fraction = item.fractionCompleted { ProgressView(value: fraction) }
                            else { ProgressView().accessibilityLabel(localizer.text(.downloadSizeUnknownProgress)) }
                        }
                        if let failure = item.failureMessage { Text(localizer.stored(failure)).font(.caption).foregroundStyle(.red) }
                        HStack {
                            if item.status.isActive {
                                Button(localizer.text(.downloadCancel), role: .destructive) { manager.cancel(id: item.id) }
                                    .disabled(item.status == .cancelling)
                            } else {
                                if item.status == .completed {
                                    if pdfDestination != nil, URL(fileURLWithPath: item.fileName).pathExtension.lowercased() == "pdf" {
                                        Button(localizer.text(.downloadProcessPDF)) { openPDF(item) }
                                            .accessibilityIdentifier("download.pdf.\(item.id)")
                                            .accessibilityHint(localizer.text(.downloadProcessPDFHint))
                                    }
                                    Button { share(item) } label: {
                                        Label(localizer.text(.downloadOpenOrShare), systemImage: "square.and.arrow.up")
                                    }.accessibilityIdentifier("download.share.\(item.id)")
                                }
                                Spacer()
                                Button(localizer.text(.commonDelete), role: .destructive) { deleting = item }
                                    .disabled(sharing?.id == item.id)
                            }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
                Section {
                    Text(localizer.text(.downloadLimits(count: manager.limits.maximumCount, active: manager.limits.maximumActive,
                                                         fileLimit: bytes(manager.limits.maximumFileBytes),
                                                         totalLimit: bytes(manager.limits.maximumTotalBytes))))
                    Text(localizer.text(.downloadStorage))
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(localizer.text(.downloadTitle))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localizer.text(.commonDone)) { dismiss() } } }
            .confirmationDialog(localizer.text(.downloadDeleteTitle), isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible, presenting: deleting) { item in
                Button(localizer.text(.downloadDeleteConfirm), role: .destructive) {
                    do { try manager.delete(id: item.id, confirmed: true) }
                    catch { actionError = localizer.error(error, fallback: .downloadDeleteFailed) }
                    deleting = nil
                }
                Button(localizer.text(.commonCancel), role: .cancel) { deleting = nil }
            } message: { item in
                Text(localizer.text(.downloadDeleteMessage(value: item.fileName)))
            }
            .navigationDestination(isPresented: Binding(get: { selectedPDF != nil }, set: { presented in
                if !presented { selectedPDF?.invalidate(); selectedPDF = nil }
            })) {
                if let selectedPDF, let pdfDestination { pdfDestination(selectedPDF) }
            }
            .sheet(item: $sharing) { file in BrowserDownloadShareSheet(url: file.url) }
            .alert(localizer.text(.downloadActionFailed), isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button(localizer.text(.commonOK), role: .cancel) { actionError = nil }
            } message: { Text(actionError ?? "") }
        }.accessibilityIdentifier("browser.downloads")
    }

    private func openPDF(_ item: BrowserDownloadItem) {
        do {
            selectedPDF?.invalidate()
            selectedPDF = try BrowserDownloadedPDFSelection(manager: manager, userSelectedID: item.id)
        } catch { actionError = localizer.error(error, fallback: .downloadOpenFailed) }
    }

    private func share(_ item: BrowserDownloadItem) {
        do { sharing = SharedFile(id: item.id, url: try manager.fileURL(id: item.id)) }
        catch { actionError = localizer.error(error, fallback: .downloadOpenFailed) }
    }

    private func sizeDescription(_ item: BrowserDownloadItem) -> String {
        if let total = item.totalBytes { return bytes(item.receivedBytes) + " / " + bytes(total) }
        return localizer.text(.downloadSizeUnknown(value: bytes(item.receivedBytes)))
    }

    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

@MainActor
private struct BrowserDownloadShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
