import AssistantSkills
import SwiftUI

/// Parent entry: SkillAgentView(store: session.learning,
///                             modelAccess: { try session.modelAccess() })
@MainActor struct SkillAgentView: View {
    @ObservedObject var store: LearningStore
    let modelAccess: () throws -> ModelAccess
    @StateObject private var agent = SkillAgentSession()
    @State private var request = ""
    @State private var answer = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        Form {
            Section {
                Text(localizer.text(agent.activity)).accessibilityIdentifier("skillAgent.status")
                if let error = agent.error {
                    Text(verbatim: localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("skillAgent.error")
                }
            }
            if let receipt = agent.receipt {
                Section(localizer.text(.skillAgentSavedSection)) {
                    Text(verbatim: receipt.name).accessibilityIdentifier("skillAgent.receipt")
                    Text(localizer.text(.skillAgentSavedNote))
                    Text(localizer.text(.skillAgentVersion(value: receipt.version))).font(.caption)
                }
            } else if let review = agent.review {
                Section(localizer.text(.authoringRequestLabel)) { Text(verbatim: review.requestQuote) }
                Section(localizer.text(review.isUpdate ? .skillAgentReviewUpdate : .skillAgentReviewNew)) {
                    Text(verbatim: review.name).accessibilityIdentifier("skillAgent.review.name")
                    Text(localizer.text(.skillAgentReviewNote))
                    Text(verbatim: review.markdown).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).accessibilityIdentifier("skillAgent.review.markdown")
                    DisclosureGroup(localizer.text(.authoringSourceVersion)) {
                        Text(verbatim: review.original.path + "\n" + review.original.revision
                            + "\n" + localizer.text(.skillAgentOriginalHash(value: review.original.sha256))
                            + "\n" + localizer.text(.skillAgentDraftHash(value: review.draftFingerprint))
                            + (review.replacesFingerprint.map { "\n" + localizer.text(.skillAgentReplacedHash(value: $0)) } ?? ""))
                            .font(.caption).textSelection(.enabled)
                    }
                }
            } else if let question = agent.question {
                Section(localizer.text(.skillAgentMoreSection)) {
                    Text(verbatim: question).accessibilityIdentifier("skillAgent.question")
                    TextEditor(text: $answer).frame(minHeight: 110).focused($focused)
                        .autocorrectionDisabled().accessibilityLabel(localizer.text(.skillAgentMoreSection))
                        .accessibilityIdentifier("skillAgent.answer")
                }
            } else if !agent.running {
                Section(localizer.text(.skillAgentStartSection)) {
                    Text(localizer.text(.skillAgentIntro))
                    TextEditor(text: $request).frame(minHeight: 130).focused($focused)
                        .autocorrectionDisabled().accessibilityLabel(localizer.text(.skillAgentRequestLabel))
                        .accessibilityIdentifier("skillAgent.request")
                    Text(localizer.text(.skillAgentHelp))
                        .font(.footnote)
                    if let message = agent.message {
                        Text(verbatim: message).accessibilityIdentifier("skillAgent.model.message")
                    }
                }
            }
            if !agent.steps.isEmpty {
                Section(localizer.text(.skillAgentToolLog)) {
                    ForEach(Array(agent.steps.enumerated()), id: \.offset) { index, step in
                        Text(localizer.text(step.succeeded ? .skillAgentStepDone(tool: localizer.text(.skillAgentTool(step.tool)))
                                                       : .skillAgentStepFailed(tool: localizer.text(.skillAgentTool(step.tool)))))
                            .accessibilityIdentifier("skillAgent.step.\(index)")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(localizer.text(.skillAgentTitle))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack {
                if agent.running {
                    Button(localizer.text(.skillAgentStop)) { agent.cancel() }.accessibilityIdentifier("skillAgent.cancel")
                } else if agent.review != nil {
                    Button(localizer.text(.authoringApprove)) { focused = false; agent.approve(store: store, modelAccess: modelAccess) }
                        .disabled(!store.available).accessibilityIdentifier("skillAgent.approve")
                    Button(localizer.text(.skillAgentDiscard)) { agent.cancel() }.accessibilityIdentifier("skillAgent.refuse")
                } else if agent.question != nil {
                    Button(localizer.text(.skillAgentSendMore)) {
                        focused = false; agent.answer(answer, store: store, modelAccess: modelAccess); answer = ""
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("skillAgent.answer.send")
                } else if agent.receipt == nil {
                    Button(localizer.text(.skillAgentStart)) {
                        focused = false; agent.start(request: request, store: store, modelAccess: modelAccess)
                    }
                    .disabled(!store.available || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("skillAgent.start")
                }
            }.buttonStyle(.borderedProminent).padding().frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localizer.text(agent.receipt == nil ? .commonCancel : .commonDone)) { agent.cancel(showNotice: false); dismiss() }
                    .accessibilityIdentifier("skillAgent.close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button(localizer.text(.commonDoneTyping)) { focused = false }.accessibilityIdentifier("skillAgent.keyboard.done")
            }
        }
        .onReceive(store.objectWillChange) { agent.hostChanged() }
        .onDisappear { agent.cancel(showNotice: false) }
    }
}
