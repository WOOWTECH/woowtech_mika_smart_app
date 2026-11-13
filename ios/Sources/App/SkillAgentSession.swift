import AssistantModels
import AssistantSkills
import Combine
import Foundation

struct SkillAgentStep: Equatable {
    let tool: String
    let succeeded: Bool
}

@MainActor final class SkillAgentSession: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var activity: AppText = .skillAgentActivityStart
    @Published private(set) var question: String?
    @Published private(set) var review: SkillAuthoringSaveReview?
    @Published private(set) var receipt: SkillAuthoringSaveReceipt?
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    @Published private(set) var steps: [SkillAgentStep] = []
    private var runtime: SkillToolSession?
    private var task: Task<Void, Never>?
    private var operationID: UUID?
    private var access: ModelAccess?
    private var storeGeneration: UUID?
    private(set) var committing = false

    func start(request: String, store: LearningStore, modelAccess: () throws -> ModelAccess) {
        cancel(showNotice: false)
        receipt = nil; message = nil; error = nil; steps = []
        do {
            let access = try modelAccess()
            let request = try SkillAuthoringUserRequest(quote: request)
            runtime = try SkillToolSession(request: request, store: store, catalog: .bundled())
            self.access = access; storeGeneration = store.generation
            advance()
        } catch { fail(error) }
    }

    func answer(_ value: String, store: LearningStore, modelAccess: () throws -> ModelAccess) {
        guard question != nil, !running else { return }
        do { try validateContext(store: store, modelAccess: modelAccess); advance(answer: value) }
        catch { fail(error) }
    }

    func approve(store: LearningStore, modelAccess: () throws -> ModelAccess) {
        guard let review, let runtime, !running else { return }
        committing = true
        defer { committing = false }
        do {
            try validateContext(store: store, modelAccess: modelAccess)
            let result = try runtime.approve(reviewID: review.id, fingerprint: review.draftFingerprint)
            self.review = nil; receipt = result; self.runtime = nil; access = nil
            activity = result.updated ? .authoringSavedUpdated : .authoringSavedAdded
        } catch { fail(error) }
    }

    func cancel(showNotice: Bool = true) {
        operationID = nil; task?.cancel(); task = nil; runtime?.cancel(); runtime = nil
        access = nil; storeGeneration = nil; running = false; question = nil; review = nil
        if showNotice { activity = .skillAgentActivityCancelled }
    }

    /// Host changes invalidate pending reviews as well as in-flight model calls.
    func hostChanged() {
        guard !committing, runtime != nil else { return }
        cancel(showNotice: false)
        activity = .skillAgentActivityStopped
        error = AppText.skillAgentErrorChanged.traditionalFallback
    }

    private func validateContext(store: LearningStore, modelAccess: () throws -> ModelAccess) throws {
        let current = try modelAccess()
        guard let access, access.configuration.baseURL == current.configuration.baseURL,
              access.configuration.model == current.configuration.model,
              access.identity == current.identity, storeGeneration == store.generation else {
            throw SkillAuthoringError.storageChanged
        }
    }

    private func advance(answer: String? = nil) {
        guard let runtime, let access else { return }
        let id = UUID(); operationID = id; running = true; question = nil; error = nil
        // Skill documents can be longer than ordinary chat answers. Stay within
        // the existing HTTP client's supported 8192-token maximum.
        let configuration = ModelConfiguration(baseURL: access.configuration.baseURL,
            model: access.configuration.model, maxOutputTokens: 8192)
        task = Task { [weak self] in
            do {
                let outcome = try await runtime.advance(client: access.client, configuration: configuration,
                    apiKey: access.key, answer: answer) { [weak self] event in
                    guard let self, self.operationID == id else { return }
                    switch event {
                    case .requestingModel(let count): self.activity = .skillAgentActivityRound(count: count)
                    case .executed(let name, let succeeded):
                        self.steps.append(SkillAgentStep(tool: name, succeeded: succeeded))
                    }
                }
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                self.running = false; self.task = nil
                switch outcome {
                case .review(let review): self.review = review; self.activity = .skillAgentActivityReview
                case .question(let question): self.question = question; self.activity = .skillAgentActivityQuestion
                case .finished(let message):
                    self.message = message; self.activity = .skillAgentActivityFinished
                    self.runtime = nil; self.access = nil
                }
            } catch {
                guard let self, self.operationID == id else { return }
                self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        cancel(showNotice: false)
        activity = .skillAgentActivityFailed
        self.error = Self.explain(error)
    }

    private static func explain(_ error: Error) -> String {
        if let error = error as? SkillToolError { return error.errorDescription ?? AppText.skillAgentErrorIncomplete.traditionalFallback }
        if let error = error as? HTTPChatModelError, error == .invalidConfiguration {
            return AppText.skillAgentErrorNoModel.traditionalFallback
        }
        if error is ModelSettingsError {
            return AppText.skillAgentErrorCredentials.traditionalFallback
        }
        return LearningStore.message(error)
    }
}
