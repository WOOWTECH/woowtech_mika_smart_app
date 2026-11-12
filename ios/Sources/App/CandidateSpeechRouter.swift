import AssistantModels
import Foundation

/// Candidate wiring: the chat host uses system/off, while public settings do
/// not expose provider selection. A host must invalidate on lifecycle changes.
@MainActor
final class CandidateSpeechRouter: VoiceInputDriver {
    enum Choice: Equatable { case system, off, unavailable, provider(model: String, method: SpeechProviderMethod) }
    enum SelectionError: Error { case busy, superseded }
    typealias ProviderFactory = (@escaping () -> Bool, @escaping (UUID) -> Void,
                                 @escaping ProviderPCMVoiceDriver.Transcribe) -> any VoiceInputDriver
    private let flow: ConfiguredProviderSpeech
    private let store: SpeechChoiceStore
    private let systemFactory: () -> any VoiceInputDriver
    private let providerFactory: ProviderFactory
    private(set) var choice: Choice
    private var active: (id: UUID, driver: any VoiceInputDriver, isCurrent: () -> Bool,
                         emit: (UUID, VoiceInputEvent) -> Void)?
    private var lifecycleGeneration: UInt64 = 0
    private var selectionGeneration = UUID()
    private var probing = false

    init(flow: ConfiguredProviderSpeech, store: SpeechChoiceStore, systemFactory: @escaping () -> any VoiceInputDriver,
         providerFactory: @escaping ProviderFactory) {
        self.flow = flow; self.store = store; self.systemFactory = systemFactory; self.providerFactory = providerFactory
        do {
            switch try store.load() {
            case .automatic, .system: choice = .system
            case .off: choice = .off
            case .provider(let selection): choice = .provider(model: selection.model, method: selection.method)
            }
        } catch { choice = .unavailable }
    }

    func selectSystem() throws { try replaceChoice(.system, saved: .system) }
    func selectOff() throws { try replaceChoice(.off, saved: .off) }
    private func replaceChoice(_ newChoice: Choice, saved: SpeechModelChoice) throws {
        selectionGeneration = UUID(); probing = false
        cancelActive(); flow.invalidate(); choice = .unavailable
        try store.save(saved)
        choice = newChoice
    }

    /// User initiates a one-second silent probe; failure retains the old choice.
    /// The explicit address is required to review a previously saved URL.
    func selectProvider(rawBaseURL: String, kind: SpeechProviderKind, model: String) async throws {
        guard !probing else { throw SelectionError.busy }
        cancelActive()
        let generation = UUID(); selectionGeneration = generation; probing = true
        defer { if selectionGeneration == generation { probing = false } }
        let snapshot = try store.snapshot()
        let store = self.store
        let gate: ConfiguredProviderSpeech.DispatchGate = { dispatch in
            try store.withUnchanged(snapshot) { try dispatch() }
        }
        let method = try await flow.probe(rawBaseURL: rawBaseURL, kind: kind, model: model, dispatchGate: gate)
        guard selectionGeneration == generation else { throw SelectionError.superseded }
        do {
            let selection = try SpeechProviderSelection(providerID: "configured-model", model: model, method: method)
            try store.save(.provider(selection), ifUnchanged: snapshot)
        } catch {
            flow.invalidate(); choice = .unavailable; throw error
        }
        choice = .provider(model: model, method: method)
    }

    /// Host calls this on a model/credential edit or a non-active scene.
    func invalidate() {
        selectionGeneration = UUID(); probing = false
        cancelActive(); flow.invalidate()
        // A stale provider never silently falls back to system or a paid model.
    }

    /// Re-read the shared settings after the active gesture has been canceled.
    /// A restored provider remains unavailable until a fresh explicit probe.
    func reloadChoice() {
        invalidate()
        do {
            switch try store.load() {
            case .automatic, .system: choice = .system
            case .off: choice = .off
            case .provider(let selection): choice = .provider(model: selection.model, method: selection.method)
            }
        } catch { choice = .unavailable }
    }

    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        cancelActive()
        let generation = lifecycleGeneration
        guard !probing else { emit(id, .failed(.unavailable)); return }
        let driver: any VoiceInputDriver
        var providerToken: UUID?
        var choiceIsCurrent: () -> Bool = { true }
        switch choice {
        case .off, .unavailable: emit(id, .failed(.unavailable)); return
        case .system:
            let store = self.store
            guard let snapshot = try? store.snapshot(), snapshot.choice == .automatic || snapshot.choice == .system else {
                emit(id, .failed(.unavailable)); return
            }
            choiceIsCurrent = { (try? store.snapshot()) == snapshot }
            driver = systemFactory()
        case .provider(let model, let method):
            let store = self.store
            guard let snapshot = try? store.snapshot(),
                  let selection = try? SpeechProviderSelection(providerID: "configured-model", model: model, method: method),
                  snapshot.choice == .provider(selection) else { emit(id, .failed(.unavailable)); return }
            choiceIsCurrent = { (try? store.snapshot()) == snapshot }
            let gate: ConfiguredProviderSpeech.DispatchGate = { dispatch in
                try store.withUnchanged(snapshot) { try dispatch() }
            }
            guard let token = try? flow.beginRecording() else { emit(id, .failed(.unavailable)); return }
            providerToken = token
            let flow = self.flow
            driver = providerFactory({ [weak self] in
                guard let self, self.lifecycleGeneration == generation, self.active?.id == id else { return false }
                return choiceIsCurrent() && flow.isCurrentSelection()
            }, { _ in flow.discardUnsentRecording(token) }, { _, samples in
                try await flow.transcribe(recording: token, samples: samples, dispatchGate: gate)
            })
        }
        guard lifecycleGeneration == generation else {
            if let providerToken { flow.discardUnsentRecording(providerToken) }
            driver.cancel(id: id)
            return
        }
        active = (id, driver, choiceIsCurrent, emit)
        driver.start(id: id, mayContinue: { [weak self] in
            guard let self, self.lifecycleGeneration == generation, self.active?.id == id, mayContinue() else { return false }
            guard self.lifecycleGeneration == generation, self.active?.id == id else { return false }
            guard choiceIsCurrent() else { return false }
            if case .provider = self.choice { return self.flow.isCurrentSelection() }
            return true
        }, emit: { [weak self] incoming, event in
            guard let self, self.lifecycleGeneration == generation, self.active?.id == id, incoming == id else { return }
            guard choiceIsCurrent() else {
                self.cancelActive(); emit(id, .cancelled); return
            }
            switch event { case .final, .failed, .cancelled: self.active = nil; default: break }
            emit(incoming, event)
        })
    }
    func finish(id: UUID) {
        guard let current = active, current.id == id else { return }
        guard current.isCurrent() else { cancelActive(); current.emit(id, .cancelled); return }
        current.driver.finish(id: id)
    }
    func cancel(id: UUID) { if active?.id == id { cancelActive() } }
    private func cancelActive() {
        lifecycleGeneration &+= 1
        let previous = active; active = nil
        if let previous { previous.driver.cancel(id: previous.id) }
    }
}
