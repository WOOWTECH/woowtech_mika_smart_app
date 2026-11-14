import Foundation
import WebKit
import AssistantBrowser
import AssistantModels
#if canImport(UIKit)
import UIKit
#endif

/// What a chat web task needs from the browser: its website data (shared,
/// owner decision 2026-11-13) and the search engine the user chose.
struct ChatWebTaskEnvironment {
    let dataStore: WKWebsiteDataStore
    let searchTemplate: String
    /// Debug fixtures only.
    var fixtureOrigin: URL?
    /// Debug fixtures only: no 4–12 s waits between pages of one site.
    var skipsPacing = false
}

/// One running web task from chat: the tab, the runner, and what the task
/// card and the small preview show. iOS does not keep it running in the
/// background: it pauses between steps and continues when the app is back.
@MainActor final class ChatWebTaskSession: ObservableObject, Identifiable {
    enum Phase: Equatable { case running, paused, finished }
    let id = UUID()
    let startedAt = Date()
    let tab: ChatWebTaskTab
    @Published private(set) var steps: [ChatWebStep] = []
    @Published private(set) var activity: ChatWebActivity = .thinking
    @Published private(set) var phase = Phase.running
    /// Nil until the user chooses: then the small view shows except on small
    /// screens and accessibility text sizes (Android hides it there too).
    @Published var showsPreview: Bool? = nil
    @Published var isExpanded = false
    /// A step that spends money waiting for 允許這一次 or 拒絕 (Android's card).
    @Published private(set) var pendingConsent: ChatWebConsentGate.Request?
    /// The page handed to the user (需要你處理), and whether they have it now.
    @Published private(set) var pendingHandover: ChatWebHandover?
    @Published private(set) var isUserControlled = false
    /// A question waiting for the user's answer (需要你回答).
    @Published private(set) var pendingQuestion: (prompt: String, options: [String])?
    private var handoverContinuation: CheckedContinuation<ChatWebHandover.Outcome, Never>?
    private var questionContinuation: CheckedContinuation<String?, Never>?
    private var waitToken: UUID?
    private var consentContinuation: CheckedContinuation<Bool, Never>?
    private var consentToken: UUID?
    private let runner: ChatWebTaskRunner
    private let pause = ChatWebTaskPause()
    private var work: Task<ChatWebTaskResult, Never>?
    #if canImport(UIKit)
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    #endif

    init(client: any ChatModelClient, configuration: ModelConfiguration, apiKey: String,
         environment: ChatWebTaskEnvironment) {
        tab = ChatWebTaskTab(dataStore: environment.dataStore, fixtureOrigin: environment.fixtureOrigin)
        let skips = environment.skipsPacing
        runner = ChatWebTaskRunner(client: client, executor: tab, configuration: configuration, apiKey: apiKey,
                                   settings: .init(searchTemplate: environment.searchTemplate, fixtureOrigin: environment.fixtureOrigin),
                                   pause: pause,
                                   sleep: { seconds in
                                       guard !skips else { return }
                                       try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                                   })
        runner.onSteps = { [weak self] in self?.steps = $0 }
        runner.onActivity = { [weak self] in self?.activity = $0 }
        runner.confirm = { [weak self] request in await self?.askConsent(request) ?? false }
        runner.handOver = { [weak self] request in await self?.waitForHandover(request) ?? .noAnswer }
        runner.ask = { [weak self] prompt, options in await self?.waitForAnswer(prompt, options) ?? nil }
    }

    /// Like Android: the page waits 15 minutes for the user (Takeover.kt).
    private func waitForHandover(_ request: ChatWebHandover) async -> ChatWebHandover.Outcome {
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                handoverContinuation?.resume(returning: .noAnswer)
                handoverContinuation = continuation; waitToken = token; pendingHandover = request
                expire(token) { $0.endHandover(.noAnswer) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in if self?.waitToken == token { self?.endHandover(.noAnswer) } }
        }
    }

    private func waitForAnswer(_ prompt: String, _ options: [String]) async -> String? {
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                questionContinuation?.resume(returning: nil)
                questionContinuation = continuation; waitToken = token; pendingQuestion = (prompt, options)
                expire(token) { $0.answer(nil) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in if self?.waitToken == token { self?.answer(nil) } }
        }
    }

    private func expire(_ token: UUID, _ end: @escaping @MainActor (ChatWebTaskSession) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900 * 1_000_000_000)
            guard let self, self.waitToken == token else { return }
            end(self)
        }
    }

    /// 我來處理: the page becomes the user's, full size, until they hand it back.
    func takeOver() {
        guard pendingHandover != nil else { return }
        isUserControlled = true; tab.userControlled = true
        showsPreview = true; isExpanded = true
    }

    /// 處理好了, 我自己做完了 or 跳過.
    func endHandover(_ outcome: ChatWebHandover.Outcome) {
        let continuation = handoverContinuation
        handoverContinuation = nil; waitToken = nil; pendingHandover = nil
        isUserControlled = false; tab.userControlled = false
        if outcome != .noAnswer { isExpanded = false }
        continuation?.resume(returning: outcome)
    }

    func answer(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let continuation = questionContinuation
        questionContinuation = nil; waitToken = nil; pendingQuestion = nil
        continuation?.resume(returning: trimmed?.isEmpty == false ? trimmed : nil)
    }

    /// Like Android: only the card can allow; no answer in 15 minutes, a stop
    /// or a cancelled task counts as a refusal.
    private func askConsent(_ request: ChatWebConsentGate.Request) async -> Bool {
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                consentContinuation?.resume(returning: false)
                consentContinuation = continuation
                consentToken = token
                pendingConsent = request
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 900 * 1_000_000_000)
                    guard let self, self.consentToken == token else { return }
                    self.answerConsent(false)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.consentToken == token else { return }
                self.answerConsent(false)
            }
        }
    }

    func answerConsent(_ allowed: Bool) {
        let continuation = consentContinuation
        consentContinuation = nil; consentToken = nil; pendingConsent = nil
        continuation?.resume(returning: allowed)
    }

    /// Runs to the end. Stopping ends only this task's own work, so the chat
    /// can still write the stopped round into the conversation.
    func run(conversation: [ModelMessage], entry: ChatWebCommand, entryRaw: String) async -> ChatWebTaskResult {
        let task = Task { @MainActor [runner] in
            await runner.run(conversation: conversation, entry: entry, entryRaw: entryRaw)
        }
        work = task
        var result = await task.value
        if result.status == .stopped {
            activity = .summarizing
            result.stopSummary = await runner.stopSummary(for: result, conversation: conversation)
        }
        finish()
        return result
    }

    func stop() { work?.cancel() }

    var isRunning: Bool { phase != .finished }
    /// 允許這一次, 我來處理 or 需要你回答 is waiting.
    var waitsForUser: Bool { pendingConsent != nil || pendingHandover != nil || pendingQuestion != nil }

    /// .inactive (Control Center, a call banner, the app switcher) does not
    /// pause; .background pauses between steps until the app is active again.
    func scenePhaseChanged(isActive: Bool, isBackground: Bool) {
        guard phase != .finished else { return }
        if isBackground {
            pause.pause(); phase = .paused
            beginBackgroundTime()
        } else if isActive {
            pause.resume(); phase = .running
            endBackgroundTime()
        }
    }

    private func finish() {
        phase = .finished
        pause.resume()
        endBackgroundTime()
    }

    /// Asks iOS for a little time so the step under way can end cleanly.
    private func beginBackgroundTime() {
        #if canImport(UIKit)
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "chat-web-task") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundTime() }
        }
        #endif
    }

    private func endBackgroundTime() {
        #if canImport(UIKit)
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        #endif
    }
}

/// The text a finished, stopped or failed web task leaves in the conversation.
/// Sources are Markdown links, so later rounds know where the answer came from.
enum ChatWebTaskTranscript {
    static func text(for result: ChatWebTaskResult, localizer: AppLocalizer) -> String {
        switch result.status {
        case .succeeded:
            let answer = (result.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return answer + list(localizer.text(.chatWebSourcesHeading), result.sources)
        case .notDone, .failed:
            let reason: String
            if let own = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty { reason = own }
            else {
                switch result.stop {
                case .repeating: reason = localizer.text(.chatWebStopRepeating)
                case .tooManyFailures: reason = localizer.text(.chatWebStopFailures)
                case .invalidCommands: reason = localizer.text(.chatWebStopInvalidCommands)
                case .modelFailed, nil: reason = localizer.text(.chatWebStopModelFailed)
                }
            }
            return "**" + localizer.text(.chatWebNotDone) + "**\n\n" + reason
                + list(localizer.text(.chatWebPagesReadHeading), result.pagesRead)
        case .stopped:
            let summary = result.stopSummary.map { "\n\n" + $0 } ?? ""
            return localizer.text(.chatWebStopped) + summary + list(localizer.text(.chatWebPagesReadHeading), result.pagesRead)
        }
    }

    private static func list(_ heading: String, _ pages: [ChatWebSource]) -> String {
        guard !pages.isEmpty else { return "" }
        let lines = pages.prefix(12).enumerated().map { index, page in
            "\(index + 1). [\(escaped(page.title))](\(linkTarget(page.url))) — \(page.site)"
        }
        return "\n\n" + heading + "\n" + lines.joined(separator: "\n")
    }

    private static func escaped(_ title: String) -> String {
        var text = ""
        for character in title.replacingOccurrences(of: "\n", with: " ") {
            if "[]\\*_`<>".contains(character) { text.append("\\") }
            text.append(character)
        }
        return text.isEmpty ? "—" : text
    }

    private static func linkTarget(_ url: URL) -> String {
        url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
    }
}
