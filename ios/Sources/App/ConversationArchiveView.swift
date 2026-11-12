import AssistantPersistence
import SwiftUI

@MainActor struct ConversationArchiveView: View {
    @ObservedObject var store: ConversationArchiveStore
    @ObservedObject var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer
    @State private var showsNewConversationConfirmation = false
    @State private var pendingNewConversationProtection: NewConversationProtection?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: localizer.text(.archiveBoundary))
                        .font(.footnote).accessibilityIdentifier("archive.boundary")
                    if let error = store.error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("archive.error")
                        Button("重新讀取") { store.reload() }.accessibilityIdentifier("archive.reload")
                    }
                }
                Section(localizer.text(.archiveSavedCount(count: store.conversations.count))) {
                    if store.conversations.isEmpty {
                        Text(verbatim: localizer.text(.archiveEmpty)).accessibilityIdentifier("archive.empty")
                    }
                    ForEach(store.conversations) { record in
                        NavigationLink {
                            ConversationArchiveDetail(store: store, session: session, id: record.id) {
                                if RecentConversationAccess.open(record, in: session) { dismiss() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).lineLimit(2)
                                Text("\(record.turns.count) 輪 · \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("archive.row." + record.id.uuidString)
                        .accessibilityLabel(record.title)
                    }
                }
            }
            .navigationTitle(localizer.text(.shellChatHistory))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.archiveClose)) { dismiss() }.accessibilityIdentifier("archive.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(localizer.text(.shellNewConversation), action: requestNewConversation)
                        .disabled(session.isSubmitting).accessibilityIdentifier("archive.new")
                }
            }
        }
        .alert(localizer.text(.newConversationConfirmTitle), isPresented: $showsNewConversationConfirmation) {
            Button(localizer.text(.newConversationDiscard), role: .destructive) {
                let approved = pendingNewConversationProtection
                pendingNewConversationProtection = nil
                guard let approved, NewConversationAction.start(in: session, approved: approved) else { return }
                dismiss()
            }
            Button(localizer.text(.newConversationKeep), role: .cancel) {
                pendingNewConversationProtection = nil
            }
        } message: {
            Text(pendingNewConversationProtection?.warningKeys.map { localizer.text($0) }.joined(separator: "\n") ?? "")
        }
    }

    private func requestNewConversation() {
        guard !session.isSubmitting else { return }
        if let protection = NewConversationProtection.current(in: session) {
            pendingNewConversationProtection = protection
            showsNewConversationConfirmation = true
        } else if NewConversationAction.start(in: session, approved: nil) {
            dismiss()
        }
    }
}

@MainActor private struct ConversationArchiveDetail: View {
    @ObservedObject var store: ConversationArchiveStore
    @ObservedObject var session: ChatSession
    let id: UUID
    let open: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer
    @State private var confirmsDelete = false
    @State private var pendingDeleteApproval: ArchiveDeletionApproval?

    var body: some View {
        Group {
            if let record = store.state.conversations.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("保存時的模型：\(record.destination.model)")
                            Text(record.destination.baseURL).font(.caption).textSelection(.enabled)
                            if !session.canOpenConversation(record) {
                                Text("模型服務、模型或金鑰身分與目前設定不同；僅供檢視，不會帶入目前服務。")
                                    .accessibilityIdentifier("archive.destinationMismatch")
                            }
                            if let block = RecentConversationAccess.block(record, in: session),
                               block != .differentDestination {
                                Text(localizer.text(block.message))
                                    .accessibilityIdentifier("archive.switchBlocked")
                            }
                            ForEach(Array(record.turns.enumerated()), id: \.element.userID) { index, turn in
                                Text("你").font(.caption.bold())
                                Text(turn.userText).textSelection(.enabled)
                                    .accessibilityIdentifier("archive.turn.\(index).user")
                                Text("助理").font(.caption.bold())
                                Text(turn.assistantText).textSelection(.enabled)
                                    .accessibilityIdentifier("archive.turn.\(index).assistant")
                            }
                            if let error = store.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("archive.error") }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    HStack {
                        Button("刪除對話", role: .destructive) {
                            pendingDeleteApproval = ArchiveDeletionApproval.capture(id: id, in: session)
                            confirmsDelete = pendingDeleteApproval != nil
                        }
                            .disabled(session.isCurrentConversation(id: id) &&
                                      (session.isSubmitting || session.pendingMCPApproval != nil ||
                                       session.pendingProfileReview != nil || session.pendingMemoryReview != nil))
                            .accessibilityIdentifier("archive.delete")
                        Spacer()
                        Button("開啟此對話", action: open)
                            .disabled(RecentConversationAccess.block(record, in: session) != nil)
                            .accessibilityIdentifier("archive.open")
                    }.padding().background(.bar)
                }
            } else { Text("此對話已刪除").accessibilityIdentifier("archive.deleted") }
        }
        .navigationTitle("保存的問答")
        .alert("刪除此對話？", isPresented: $confirmsDelete) {
            Button("取消", role: .cancel) { pendingDeleteApproval = nil }
            Button("刪除", role: .destructive) {
                let approved = pendingDeleteApproval
                pendingDeleteApproval = nil
                if let approved, ArchiveDeletionAction.delete(approved: approved, in: session) { dismiss() }
            }.accessibilityIdentifier("archive.delete.confirm")
        } message: {
            let original = "會移除已保存的問答、附件擷取文字與引文；已確認的記憶與個人檔案保留。"
            let warnings = pendingDeleteApproval?.newConversation?.warningKeys.map { localizer.text($0) }.joined(separator: "\n")
            Text(original + (warnings.map { "\n" + $0 } ?? ""))
        }
    }
}
