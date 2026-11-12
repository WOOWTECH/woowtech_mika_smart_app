import Combine
import Foundation

/// Owns the one user-initiated background search; no file or network access.
@MainActor public final class DocumentPatternSearchController: ObservableObject {
    public enum State {
        case idle, running, completed(DocumentSearchResult), failed(DocumentPatternError), failedUnexpectedly
    }
    @Published public private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    // Internal handle lets lifecycle tests await an old, cancelled publisher.
    var inFlightTask: Task<Void, Never>? { task }
    private var generation = UUID()
    public private(set) var sourceID: UUID?
    private let runner: @Sendable (DocumentTextSnapshot, String, Bool) async throws -> DocumentSearchResult

    public convenience init() {
        self.init { source, pattern, ignoreCase in
            try DocumentPatternSearch.search(source: source, pattern: pattern, ignoreASCIICase: ignoreCase)
        }
    }

    // Allows lifecycle tests to hold a late completion without changing production behavior.
    init(runner: @escaping @Sendable (DocumentTextSnapshot, String, Bool) async throws -> DocumentSearchResult) {
        self.runner = runner
    }

    public func start(source: DocumentTextSnapshot, pattern: String, ignoreASCIICase: Bool) {
        reset()
        let token = UUID(); generation = token; sourceID = source.id; state = .running
        let runner = self.runner
        task = Task { [weak self] in
            let operation = Task.detached(priority: .userInitiated) { try await runner(source, pattern, ignoreASCIICase) }
            let outcome = await withTaskCancellationHandler {
                await operation.result
            } onCancel: { operation.cancel() }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.task = nil
            switch outcome {
            case .success(let result):
                guard result.sourceSHA256 == source.sha256 else { self.state = .failedUnexpectedly; return }
                self.state = .completed(result)
            case .failure(let error as DocumentPatternError): self.state = .failed(error)
            case .failure(is CancellationError): self.state = .idle
            case .failure: self.state = .failedUnexpectedly
            }
        }
    }

    /// Invalidates publication immediately, even if a worker returns late.
    public func reset() {
        generation = UUID(); task?.cancel(); task = nil; sourceID = nil; state = .idle
    }
}
