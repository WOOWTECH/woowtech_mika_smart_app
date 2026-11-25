import AssistantBrowser
import SwiftUI
import UIKit

/// Over every screen, since a download can start in the browser or on a web
/// task's page the person took over: the question before each download (its
/// name, size when known and site; nothing is written before 下載), the
/// downloads list, and a note when one ends while the list is closed.
struct BrowserDownloadPresentations: ViewModifier {
    @ObservedObject var manager: BrowserDownloadManager
    @ObservedObject var chat: ChatSession
    @Binding var showsList: Bool
    let localizer: AppLocalizer
    /// Copies a finished download into the chat's tray; true when it is there.
    let attach: (URL) async -> Bool

    func body(content: Content) -> some View {
        content
            .alert(localizer.text(.downloadAskTitle), isPresented: Binding(get: { manager.question != nil }, set: { _ in }),
                   presenting: manager.question) { item in
                Button(localizer.text(.downloadAskDownload)) {
                    manager.answer(item.id, allowed: true)
                    // Once the question has closed, the list shows the download arriving.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        showsList = true
                    }
                }
                .accessibilityIdentifier("download.ask.download")
                Button(localizer.text(.commonCancel), role: .cancel) { manager.answer(item.id, allowed: false) }
                    .accessibilityIdentifier("download.ask.cancel")
            } message: { item in
                Text(verbatim: localizer.text(.downloadAskMessage(
                    name: item.fileName, size: item.expectedBytes.map(BrowserDownloadsView.bytes) ?? localizer.text(.downloadSizeUnknown),
                    site: item.host.isEmpty ? "—" : item.host)))
            }
            .sheet(isPresented: $showsList, onDismiss: { manager.listIsOpen = false }) {
                BrowserDownloadsView(manager: manager, chat: chat, localizer: localizer, attach: attach)
            }
            .overlay(alignment: .top) { note }
    }

    @ViewBuilder private var note: some View {
        if let item = manager.notice, !showsList {
            Button {
                manager.notice = nil
                showsList = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.phase == .finished ? "arrow.down.circle.fill" : "exclamationmark.circle.fill")
                    Text(verbatim: localizer.text(item.phase == .finished ? .downloadNoticeFinished(name: item.fileName)
                                                  : .downloadNoticeFailed(name: item.fileName)))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(localizer.text(.downloadNoticeOpen)).fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 8)
            .accessibilityIdentifier("download.notice")
            .task(id: item.id) {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if manager.notice?.id == item.id { manager.notice = nil }
            }
        }
    }
}

/// The downloads list: progress and 停止下載 while one arrives; for a finished
/// file 存到檔案, 分享, 附加到對話 (when the chat can read it) and 移除. Each of
/// them deletes the app's copy once it is done; a cancel in the system's sheet
/// leaves the file as it was.
struct BrowserDownloadsView: View {
    @ObservedObject var manager: BrowserDownloadManager
    @ObservedObject var chat: ChatSession
    let localizer: AppLocalizer
    let attach: (URL) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var delivery: Delivery?
    /// Finished downloads the chat can read.
    @State private var readable: Set<UUID> = []
    @State private var attaching: UUID?

    private struct Delivery: Identifiable {
        let item: UUID
        let url: URL
        let share: Bool
        var id: String { (share ? "share-" : "save-") + item.uuidString }
    }

    var body: some View {
        NavigationStack {
            List {
                if manager.items.isEmpty {
                    Text(localizer.text(.downloadEmpty)).foregroundStyle(.secondary)
                }
                ForEach(manager.items) { item in row(item) }
                Section {
                    Text(localizer.text(.downloadLimits)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(localizer.text(.downloadTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonDone)) { dismiss() }.accessibilityIdentifier("download.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("browser.downloads")
        .onAppear { manager.listIsOpen = true; manager.notice = nil }
        .sheet(item: $delivery) { target in
            if target.share {
                DocumentSharePicker(url: target.url) { completed, _ in
                    delivery = nil
                    if completed { manager.delivered(target.item, as: .shared, deleteAfter: ChatCreatedFileLimits.deleteAfterShare) }
                }
            } else {
                DocumentSavePicker(url: target.url) { saved in
                    delivery = nil
                    if saved { manager.delivered(target.item, as: .saved) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func row(_ item: BrowserDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.fileName).font(.headline).lineLimit(2)
            Text(verbatim: status(item)).font(.caption)
                .foregroundStyle(failed(item) ? Color.red : Color.secondary)
                .accessibilityIdentifier("download.status." + item.id.uuidString)
            if item.phase == .downloading {
                if let total = item.expectedBytes, total > 0 {
                    ProgressView(value: min(1, Double(item.receivedBytes) / Double(total)))
                } else {
                    ProgressView()
                }
            }
            HStack(spacing: 8) {
                if item.phase.isActive {
                    Button(localizer.text(.downloadStop), role: .destructive) { manager.cancel(item.id) }
                        .accessibilityIdentifier("download.stop." + item.id.uuidString)
                } else if item.phase == .finished, let url = manager.file(item.id) {
                    Button(localizer.text(.chatFileSave)) { delivery = Delivery(item: item.id, url: url, share: false) }
                        .accessibilityIdentifier("download.save." + item.id.uuidString)
                    Button(localizer.text(.chatFileShare)) { delivery = Delivery(item: item.id, url: url, share: true) }
                        .accessibilityIdentifier("download.share." + item.id.uuidString)
                    if readable.contains(item.id) {
                        Button(localizer.text(.downloadAttach)) { attachToChat(item.id, url) }
                            .disabled(chat.isSubmitting || chat.isAddingAttachments || attaching != nil)
                            .accessibilityIdentifier("download.attach." + item.id.uuidString)
                    }
                }
                Spacer(minLength: 0)
                if !item.phase.isActive {
                    Button(localizer.text(.downloadRemove)) { manager.remove(item.id) }
                        .accessibilityIdentifier("download.remove." + item.id.uuidString)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .task(id: item.phase) {
            guard item.phase == .finished, let url = manager.file(item.id) else { return }
            // The chat's own reader decides, off the main actor, as for a picked file.
            let problem = await Task.detached(priority: .utility) {
                ChatAttachmentReader.problem(fileURL: url, kind: ChatAttachmentNaming.kind(forName: url.lastPathComponent),
                                             contentType: nil)
            }.value
            if problem == nil { readable.insert(item.id) }
        }
    }

    private func attachToChat(_ id: UUID, _ url: URL) {
        attaching = id
        Task {
            if await attach(url) {
                manager.delivered(id, as: .attached)
                dismiss()
            }
            attaching = nil
        }
    }

    private func failed(_ item: BrowserDownloadItem) -> Bool {
        if case .failed = item.phase { return true }
        return false
    }

    private func status(_ item: BrowserDownloadItem) -> String {
        switch item.phase {
        case .starting: return localizer.text(.downloadStarting)
        case .asking: return localizer.text(.downloadAsking)
        case .downloading:
            let received = Self.bytes(item.receivedBytes)
            return item.expectedBytes.map { localizer.text(.downloadArriving(received: received, total: Self.bytes($0))) }
                ?? localizer.text(.downloadArrivingUnknown(received: received))
        case .finished: return localizer.text(.downloadFinished) + " · " + Self.bytes(item.receivedBytes)
        case .delivered(.saved): return localizer.text(.downloadSaved)
        case .delivered(.shared): return localizer.text(.downloadShared)
        case .delivered(.attached): return localizer.text(.downloadAttached)
        case .cancelled: return localizer.text(.downloadCancelled)
        case .failed(let reason):
            switch reason {
            case .tooLarge: return localizer.text(.downloadFailedTooLarge)
            case .storageFull: return localizer.text(.downloadFailedStorageFull)
            case .tooMany: return localizer.text(.downloadFailedTooMany)
            case .network: return localizer.text(.downloadFailedNetwork)
            case .deviceFull: return localizer.text(.downloadFailedDeviceFull)
            case .unsafeAddress: return localizer.text(.downloadFailedUnsafe)
            case .expired: return localizer.text(.downloadFailedExpired)
            case .unavailable: return localizer.text(.downloadFailedUnavailable)
            }
        }
    }

    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
