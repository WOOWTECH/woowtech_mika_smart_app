import AssistantBrowser
import AssistantModels
import AssistantSkills
import Foundation

/// The steps a chat web task took, as the executed actions SkillLearningService
/// judges and drafts from. Like Play's Eligibility, reads, finds, waits and the
/// control list are observations; opening, going back, scrolling, tapping,
/// typing and choosing are actions; confirmations, hand-overs and questions are
/// neither.
enum ChatWebLearningEvidence {
    /// SkillLearningService accepts at most 60 actions and 96 KB in all.
    static let maximumActions = 60
    static let evidenceBudget = 60 * 1024

    static func actions(from result: ChatWebTaskResult) -> [SkillExecutedAction] {
        var budget = evidenceBudget
        var actions: [SkillExecutedAction] = []
        // Newest first, so the pages closest to the answer keep their text.
        for step in result.steps.reversed() {
            guard actions.count < maximumActions, let (tool, kind) = tool(for: step.kind) else { continue }
            let target = String(step.title.prefix(200))
            var text: String
            if kind == .observation {
                text = result.evidence[step.id] ?? ""
                if text.utf8.count > budget { text = "" }
                budget -= text.utf8.count
            } else {
                // An action counts only with a result; it holds what the step did, never typed text.
                text = String("\(tool) \(step.site) \(target)".prefix(300))
            }
            let observed = kind == .observation && !text.isEmpty ? step.url : nil
            actions.append(SkillExecutedAction(id: "step-\(step.id)", toolName: tool, kind: kind,
                arguments: ["site": String(step.site.prefix(200)), "target": target],
                result: text, succeeded: step.succeeded, observedURL: observed))
        }
        return actions.reversed()
    }

    static func tool(for kind: ChatWebStep.Kind) -> (String, SkillActionKind)? {
        switch kind {
        case .open: return ("web_navigate", .navigation)
        case .back: return ("web_back", .navigation)
        case .scroll: return ("web_scroll", .navigation)
        case .read: return ("web_read_page", .observation)
        case .find: return ("web_find", .observation)
        case .wait: return ("web_wait_for", .observation)
        case .observe: return ("web_observe", .observation)
        case .tap: return ("web_tap", .interaction)
        case .type: return ("web_type_text", .interaction)
        case .select: return ("web_select", .interaction)
        case .confirm, .handover, .ask: return nil
        }
    }
}

/// What a chat skill step left for learning: the personal skills it read and
/// the tools that returned success.
struct ChatSkillLearningInput {
    let requestID: UUID
    let used: [SkillUsedReference]
    let completedTools: [String]
}

extension ChatSession {
    /// Play's RunLearning after a chat web task: judge the answer against the
    /// pages read and, when it was done in at least five actions, draft a skill
    /// under 待確認. Runs after delivery and never changes the answer.
    func learnFromWebTask(_ result: ChatWebTaskResult, goal: String, generation: UUID,
                          client: any ChatModelClient, configuration: ModelConfiguration, key: String) {
        guard result.status == .succeeded, let answer = result.answer, learning.available,
              learning.memory.preferences.learnSkills, !result.userInterrupted else { return }
        let actions = ChatWebLearningEvidence.actions(from: result)
        // A web task reads no skills, so the judgment only serves a draft: below
        // Play's five actions, or when the user did part of it, nothing is asked.
        guard SkillLearningService.countedActions(actions) >= 5 else { return }
        let toolNames = ChatWebCommand.toolNames
        let state = learning.skills
        let builtinNames = chatSkillCatalog().builtinNames
        let runID = UUID()
        Task { [weak self] in
            let assessment = try? await SkillLearningService(client: client).assess(
                goal: String(goal.prefix(4000)), answer: String(answer.prefix(12_000)), actions: actions,
                context: SkillTaskContext(runID: runID, userInterrupted: result.userInterrupted),
                state: state, availableToolNames: toolNames, builtinNames: builtinNames, allowDraft: true,
                configuration: configuration, apiKey: key)
            guard let self, let assessment, !Task.isCancelled else { return }
            self.learning.applyChatLearning(assessment, availableToolNames: toolNames, builtinNames: builtinNames,
                                            expectedGeneration: generation)
        }
    }

    /// Play's recordOutcomes after a chat skill step that read personal skills:
    /// Play's outcome judge decides done, partial or not possible, and a trial
    /// skill becomes regular after a done run, or pauses after a failed one.
    /// `generation` is read after the reply's memory organizing has started.
    func learnFromSkillStep(requestID: UUID, goal: String, answer: String, priorTurns: [String],
                            client: any ChatModelClient, configuration: ModelConfiguration, key: String) {
        guard let input = takeSkillLearning(requestID: requestID), !input.used.isEmpty else { return }
        let generation = learning.generation
        Task { [weak self] in
            let outcome = (try? await ChatOutcomeJudge(client: client).judge(
                goal: goal, answer: answer, priorTurns: priorTurns, completedTools: input.completedTools,
                configuration: configuration, apiKey: key)) ?? .unknown
            guard let self, !Task.isCancelled else { return }
            self.learning.recordChatSkillOutcomes(input.used,
                evidence: SkillRunEvidence(end: .succeeded, outcome: outcome, wasRead: true, followed: true),
                expectedGeneration: generation)
        }
    }

    /// A skill step that ran out of calls or time failed like Play's StepLimit;
    /// other failures (the model, the network, cancelling) say nothing about the skill.
    func recordFailedSkillStep(requestID: UUID, error: Error, generation: UUID) {
        guard let input = takeSkillLearning(requestID: requestID), !input.used.isEmpty,
              let failure = error as? ChatSkillRunError else { return }
        let kind: SkillFailureKind
        switch failure {
        case .toolCallLimit, .modelCallLimit, .expired: kind = .stepLimit
        case .invalidCommand: kind = .model
        }
        learning.recordChatSkillOutcomes(input.used,
            evidence: SkillRunEvidence(end: .failed, failureKind: kind, wasRead: true, followed: true),
            expectedGeneration: generation)
    }

    private func takeSkillLearning(requestID: UUID) -> ChatSkillLearningInput? {
        guard let input = pendingSkillLearning, input.requestID == requestID else { return nil }
        pendingSkillLearning = nil
        return input
    }
}
