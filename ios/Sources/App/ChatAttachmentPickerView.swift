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
    let localizer: AppLocalizer
    var hostIssue: AppText? = nil
    var onRemove: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(localizer.text(.attachmentLocalNotice))
                    Text(localizer.text(.attachmentLimits))
                }
                if let hostIssue {
                    Text(localizer.text(hostIssue)).foregroundStyle(.red)
                        .accessibilityIdentifier("chat.attachment.hostIssue")
                }
                #if DEBUG
                if ChatAttachmentComposerUITestFixture.selected() != nil {
                    Section("Synthetic offline fixture") {
                        Button("Select synthetic text") { selectFixture(oversize: false) }
                            .accessibilityIdentifier("attachment.fixture.select")
                        Button("Select oversized text") { selectFixture(oversize: true) }
                            .accessibilityIdentifier("attachment.fixture.oversize")
                        Button("Cancel selection") { model.presenter.pickerCancelled() }
                            .accessibilityIdentifier("attachment.fixture.cancel")
                        Button("Fail replacement") {
                            model.presenter.picked(URL(fileURLWithPath: "/synthetic-unsupported.pdf"))
                        }.accessibilityIdentifier("attachment.fixture.failReplacement")
                    }
                }
                #endif
                Section(localizer.text(.attachmentSection)) {
                    switch model.state.phase {
                    case .empty, .consumed:
                        Text(localizer.text(model.state.phase == .consumed ? .attachmentConsumed : .attachmentEmpty))
                    case .loading(let filename):
                        Label { Text(verbatim: filename) } icon: { ProgressView() }
                        Text(localizer.text(.attachmentLoading))
                    case .ready(let metadata), .confirmed(let metadata), .taking(let metadata):
                        Label { Text(verbatim: metadata.filename) } icon: { Image(systemName: metadata.kind == .text ? "doc.text" : "photo") }
                            .accessibilityIdentifier("chat.attachment.filename")
                        Text(localizer.text(.attachmentMetadata(count: metadata.byteCount, kind: localizer.text(AppLocalizer.attachmentKind(metadata.kind)))))
                            .accessibilityIdentifier("chat.attachment.metadata")
                        if case .confirmed = model.state.phase {
                            Text(localizer.text(.attachmentConfirmed))
                                .accessibilityIdentifier("chat.attachment.confirmed")
                        }
                        if case .taking = model.state.phase { Text(localizer.text(.attachmentTaking)) }
                    }
                    Button(localizer.text(model.state.phase == .empty || model.state.phase == .consumed ? .attachmentSelect : .attachmentReplace)) {
                        choosing = true
                    }
                    .accessibilityIdentifier("chat.attachment.select")
                    if model.state.phase != .empty || model.state.error != nil || hostIssue != nil {
                        Button(localizer.text(.attachmentRemove), role: .destructive) {
                            if let onRemove { onRemove() } else { model.presenter.discard() }
                        }
                            .accessibilityIdentifier("chat.attachment.remove")
                    }
                    if let error = model.state.error {
                        Text(localizer.text(AppLocalizer.attachmentError(error)))
                            .foregroundStyle(.red).accessibilityIdentifier("chat.attachment.error")
                        switch error {
                        case .pickerFailed, .importing:
                            Text(localizer.text(.attachmentSelectionRetry))
                                .accessibilityIdentifier("chat.attachment.selectionRetry")
                        default: EmptyView()
                        }
                    }
                }
                if showsReview {
                    Section(localizer.text(.attachmentReview)) {
                        if let context = model.state.context {
                            Text(verbatim: localizer.text(.attachmentDestination(value: context.baseURL.absoluteString)))
                                .accessibilityIdentifier("chat.attachment.destination")
                            Text(verbatim: localizer.text(.attachmentModel(value: context.model))).accessibilityIdentifier("chat.attachment.model")
                            Text(verbatim: localizer.text(.attachmentOtherData(value: localizer.attachmentDataDescription(context.additionalData))))
                                .accessibilityIdentifier("chat.attachment.context")
                            Text(localizer.text(.attachmentSendNotice))
                            Text(localizer.text(.chatAttachmentBoundary))
                            if case .ready(let metadata) = model.state.phase, metadata.kind != .text {
                                Text(localizer.text(.chatAttachmentVisionNotice))
                            }
                            if case .ready = model.state.phase, model.state.error == nil {
                                Button(localizer.text(.attachmentConfirm)) { model.confirm() }
                                    .accessibilityIdentifier("chat.attachment.confirm")
                            }
                        } else {
                            Text(localizer.text(.attachmentNeedsContext))
                        }
                    }
                }
            }
            .navigationTitle(localizer.text(.attachmentTitle))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localizer.text(.attachmentDone)) { dismiss() }
                .accessibilityIdentifier("chat.attachment.done") } }
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

    #if DEBUG
    private func selectFixture(oversize: Bool) {
        do { model.presenter.picked(try ChatAttachmentComposerUITestFixture.file(oversize: oversize)) }
        catch { model.presenter.pickerFailed() }
    }
    #endif
    private static var allowedTypes: [UTType] {
        [.jpeg, .png, .plainText] + ["md", "csv", "tsv"].compactMap { UTType(filenameExtension: $0) }
    }
    private var showsReview: Bool {
        switch model.state.phase { case .ready, .confirmed, .taking: return true; default: return false }
    }
}
