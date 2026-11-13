import AssistantModels
import Foundation

private struct CheckFailure: Error { let message: String }

@main struct CheckModelConnectionDelayedFixture {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            count += 1
            guard condition() else { throw CheckFailure(message: message) }
        }
        func wait(_ condition: @escaping @MainActor () -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw CheckFailure(message: "fixture deadline")
        }
        let uuid = UUID().uuidString
        let flag = ModelConnectionUITestFixture.flag
        let args = ["-UITestMode", "-UITestNamespace", uuid, flag]
        try check(ModelConnectionUITestFixture.valid(arguments: args, simulator: true), "isolated simulator flags accepted")
        try check(!ModelConnectionUITestFixture.valid(arguments: args, simulator: false), "physical device denied")
        try check(!ModelConnectionUITestFixture.valid(arguments: [flag], simulator: true), "missing namespace rejected")
        try check(!ModelConnectionUITestFixture.valid(arguments: ["-UITestMode", "-UITestNamespace", "bad", flag], simulator: true), "invalid namespace rejected")
        try check(!ModelConnectionUITestFixture.valid(arguments: args + ["-LiveModelUITest"], simulator: true), "live mode rejected")
        try check(!ModelConnectionUITestFixture.valid(arguments: args + [flag], simulator: true), "duplicate flag rejected")
        try check(!ModelConnectionUITestFixture.valid(arguments: args + ["-UITestChatStreaming"], simulator: true), "conflicting fixture rejected")
        try check(ModelConnectionUITestFixture.selected(arguments: []) == nil, "fixture disabled by default")

        let fixture = ModelConnectionUITestFixture()
        let client = DelayedModelConnectionUITestClient(fixture: fixture)
        let config = ModelConfiguration(baseURL: URL(string: "https://model.example.invalid/v1")!, model: "ui-test-model")
        let model = ModelConnectionCheck(timeoutNanoseconds: 1_000_000_000)
        model.onFixtureAttemptSettled = { fixture.attemptSettled() }
        model.start(client: client, configuration: config, apiKey: "different-synthetic-key")
        try await wait { model.state == .failed(.configuration) }
        try check(fixture.started == 0 && fixture.settled == 1, "unexpected credentials are rejected without recording them")
        let wrong = ModelConfiguration(baseURL: URL(string: "https://other.example.invalid/v1")!, model: "ui-test-model")
        model.start(client: client, configuration: wrong, apiKey: "fixture-only-not-a-real-key")
        try await wait { fixture.settled == 2 }
        try check(model.state == .failed(.configuration) && fixture.started == 0, "unexpected destination is rejected")
        model.start(client: client, configuration: config, apiKey: "fixture-only-not-a-real-key")
        try await wait { fixture.started == 1 }
        try check(model.state == .testing && fixture.released == 0 && fixture.settled == 2, "fixture actually waits")
        model.reset()
        try await wait { fixture.cancelled == 1 }
        try check(fixture.released == 0 && fixture.settled == 2, "cancellation is observed before release")
        fixture.releaseNext()
        try await wait { fixture.settled == 3 }
        try check(fixture.released == 1 && model.state == .untested, "released stale result is processed and ignored")
        fixture.releaseNext()
        try check(fixture.released == 1, "empty release has no effect")

        model.start(client: client, configuration: config, apiKey: "fixture-only-not-a-real-key")
        try await wait { fixture.started == 2 }
        fixture.releaseNext()
        try await wait { fixture.settled == 4 }
        try check(model.state == .passed && fixture.released == 2, "current result reaches normal completion")

        // The captured settled observer survives loss of the view's model.
        var disposed: ModelConnectionCheck? = ModelConnectionCheck(timeoutNanoseconds: 1_000_000_000)
        disposed?.onFixtureAttemptSettled = { fixture.attemptSettled() }
        disposed?.start(client: client, configuration: config, apiKey: "fixture-only-not-a-real-key")
        try await wait { fixture.started == 3 }
        disposed?.reset(); disposed = nil
        try await wait { fixture.cancelled == 2 }
        fixture.releaseNext()
        try await wait { fixture.settled == 5 }
        try check(fixture.released == 3, "settled proof survives leaving the view")
        print("PASS delayed connection fixture: \(count) assertions; synthetic client only")
    }
}
