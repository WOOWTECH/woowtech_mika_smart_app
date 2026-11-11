#if DEBUG
import AssistantModels
import Combine
import Foundation

/// A closed, opt-in simulator fixture. It cannot contact a network or expose
/// credentials. Deliberately ignores cancellation until a test releases it.
@MainActor
final class ModelConnectionUITestFixture: ObservableObject {
    static let flag = "-UITestModelConnectionDelay"
    private static let shared = ModelConnectionUITestFixture()
    @Published private(set) var started = 0
    @Published private(set) var cancelled = 0
    @Published private(set) var released = 0
    @Published private(set) var settled = 0
    private var waiting: [CheckedContinuation<String, Never>] = []

    static func valid(arguments: [String], simulator: Bool) -> Bool {
        let allowed = [flag, "-UITestMode", "-UITestNamespace", "-UITestResetStorage"]
        guard simulator, arguments.filter({ $0 == flag }).count == 1,
              arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
              arguments.filter({ $0 == "-UITestResetStorage" }).count <= 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              !arguments.contains(where: { $0.hasPrefix("-UITest") && !allowed.contains($0) }),
              let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
              let uuid = UUID(uuidString: arguments[index + 1]),
              uuid.uuidString.lowercased() == arguments[index + 1].lowercased() else { return false }
        return true
    }

    static func selected(arguments: [String]) -> ModelConnectionUITestFixture? {
        guard arguments.contains(where: { $0.hasPrefix(flag) }) else { return nil }
        #if targetEnvironment(simulator) || MODEL_CONNECTION_FIXTURE_STANDALONE
        let simulator = true
        #else
        let simulator = false
        #endif
        precondition(valid(arguments: arguments, simulator: simulator), "Invalid isolated connection fixture")
        return shared
    }

    func waitForRelease() async -> String {
        started += 1
        return await withCheckedContinuation { waiting.append($0) }
    }

    func releaseNext() {
        guard !waiting.isEmpty else { return }
        released += 1
        waiting.removeFirst().resume(returning: "fixture reply")
    }

    func attemptSettled() { settled += 1 }
    func attemptCancelled() { cancelled += 1 }
}

struct DelayedModelConnectionUITestClient: ChatModelClient {
    let fixture: ModelConnectionUITestFixture
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        guard messages.count == 1, messages[0].role == "user",
              messages[0].content == "This is a connection test. Reply briefly.",
              configuration.maxOutputTokens == 32,
              configuration.baseURL.absoluteString == "https://model.example.invalid/v1",
              configuration.model == "ui-test-model",
              apiKey == "fixture-only-not-a-real-key" else { throw HTTPChatModelError.invalidConfiguration }
        return await withTaskCancellationHandler {
            await fixture.waitForRelease()
        } onCancel: {
            Task { @MainActor in fixture.attemptCancelled() }
        }
    }
}
#endif
