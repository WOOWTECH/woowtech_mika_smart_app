import AssistantAttachments
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A host-owned bridge. Construct once per draft and keep it alive while the
/// sheet is closed. The presenter never sends; the host owns context changes,
/// confirmed take, and discard on conversation/background transitions.
@MainActor final class ChatAttachmentPickerViewModel: ObservableObject {
    let presenter: ChatAttachmentPresenter
    @Published private(set) var state: ChatAttachmentPresentationState

    convenience init() { self.init(presenter: ChatAttachmentPresenter()) }
    init(presenter: ChatAttachmentPresenter) {
        self.presenter = presenter; state = presenter.state
        presenter.onChange = { [weak self] in self?.state = $0 }
    }
    func confirm() { try? presenter.confirm() }
}

/// A standalone sheet that can be presented by a future host. Dismissing the
/// sheet leaves the staged attachment with the host-owned view model.
@MainActor struct ChatAttachmentPickerView: View {
    @ObservedObject var model: ChatAttachmentPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("選取後會在此裝置讀取及檢查檔案；本頁不會傳送或儲存原始附件。")
                    Text("限一個 JPEG、PNG（最多 5 MiB）或 UTF-8 文字檔（最多 32 KiB）；PDF 使用另一個功能。")
                }
                Section("附件") {
                    switch model.state.phase {
                    case .empty, .consumed:
                        Text(model.state.phase == .consumed ? "附件已交給主程式。" : "尚未選取附件。")
                    case .loading(let filename):
                        Label { Text(verbatim: filename) } icon: { ProgressView() }
                        Text("正在讀取及檢查附件。")
                    case .ready(let metadata), .confirmed(let metadata), .taking(let metadata):
                        Label { Text(verbatim: metadata.filename) } icon: { Image(systemName: metadata.kind == .text ? "doc.text" : "photo") }
                            .accessibilityIdentifier("chat.attachment.filename")
                        Text("\(metadata.byteCount) 位元組 · \(kindLabel(metadata.kind))")
                            .accessibilityIdentifier("chat.attachment.metadata")
                        if case .confirmed = model.state.phase {
                            Text("已確認此範圍；尚未傳送。")
                                .accessibilityIdentifier("chat.attachment.confirmed")
                        }
                        if case .taking = model.state.phase { Text("正在交給主程式。") }
                    }
                    Button(model.state.phase == .empty || model.state.phase == .consumed ? "選取附件" : "更換附件（移除目前附件）") {
                        choosing = true
                    }
                    .accessibilityIdentifier("chat.attachment.select")
                    if model.state.phase != .empty && model.state.phase != .consumed {
                        Button("移除附件", role: .destructive) { model.presenter.discard() }
                            .accessibilityIdentifier("chat.attachment.remove")
                    }
                    if let error = model.state.error {
                        Text(error.errorDescription ?? "附件處理失敗。")
                            .foregroundStyle(.red).accessibilityIdentifier("chat.attachment.error")
                    }
                }
                if showsReview {
                    Section("傳送前確認") {
                        if let context = model.state.context {
                            Text(verbatim: "目的服務：" + context.baseURL.absoluteString)
                                .accessibilityIdentifier("chat.attachment.destination")
                            Text(verbatim: "模型：" + context.model).accessibilityIdentifier("chat.attachment.model")
                            Text(verbatim: "另會傳送：" + context.additionalDataDescription)
                                .accessibilityIdentifier("chat.attachment.context")
                            Text("確認後，主程式可在這一次請求中傳送完整附件；按下確認本身不會傳送。")
                            if case .ready = model.state.phase {
                                Button("確認本次傳送範圍") { model.confirm() }
                                    .accessibilityIdentifier("chat.attachment.confirm")
                            }
                        } else {
                            Text("請先設定模型與本次傳送範圍。")
                        }
                    }
                }
            }
            .navigationTitle("聊天附件")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: Self.allowedTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if urls.count == 1, let url = urls.first { model.presenter.picked(url) }
                    else if urls.isEmpty { model.presenter.pickerCancelled() }
                    else { model.presenter.pickerFailed() }
                case .failure(let error):
                    let cocoa = error as NSError
                    if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError { model.presenter.pickerCancelled() }
                    else { model.presenter.pickerFailed() }
                }
            }
        }
    }

    private static var allowedTypes: [UTType] {
        [.jpeg, .png, .plainText] + ["md", "csv", "tsv"].compactMap { UTType(filenameExtension: $0) }
    }
    private var showsReview: Bool {
        switch model.state.phase { case .ready, .confirmed, .taking: return true; default: return false }
    }
    private func kindLabel(_ kind: ChatAttachmentKind) -> String {
        switch kind { case .jpeg: return "JPEG 圖片"; case .png: return "PNG 圖片"; case .text: return "UTF-8 文字" }
    }
}
