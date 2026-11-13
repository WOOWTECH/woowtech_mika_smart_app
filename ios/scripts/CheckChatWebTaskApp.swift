import AppKit
import Foundation
import WebKit
import AssistantBrowser
import AssistantModels
import AssistantMemory
import AssistantPersistence

/// Real WebKit on macOS against loopback pages: the task tab's rules, the
/// runner on real pages, and (Debug) the whole chat path with the Debug model
/// fixture. No external site, model provider, Keychain or user data.
@MainActor enum ChatWebTaskAppChecks {
    struct Failure: Error, CustomStringConvertible { let name: String; var description: String { name } }
    private static var count = 0
    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure(name: name) }
        count += 1
    }

    static func run(server: URL) async throws -> Int {
        try await tabRules(server)
        try await runnerOnRealPages(server)
        #if DEBUG
        try await chatEndToEnd()
        #endif
        return count
    }

    /// WebKit lays out and scrolls only pages that are in a window, as on iOS.
    @MainActor final class Mount {
        let window: NSWindow
        init(_ view: WKWebView) {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 844), styleMask: [.borderless],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFront(nil)
        }
        func close() { window.contentView = nil; window.close() }
    }

    static func tabRules(_ server: URL) async throws {
        let tab = ChatWebTaskTab(dataStore: .nonPersistent(), fixtureOrigin: server)
        let mount = Mount(tab.webView)
        defer { mount.close() }
        func url(_ path: String) -> URL { URL(string: server.absoluteString + path)! }
        let search = try await tab.load(url("/jobs/search?keyword=iOS"))
        try check(search.httpStatus == 200 && search.title.contains("iOS") && search.settled, "query-string page loads")
        let page = try await tab.capture()
        try check(page.text.contains("共 6 筆職缺") && page.text.contains("月薪"), "whole page text read")
        try check(page.links.first?.url.path == "/jobs/job/1" && page.links.count >= 9, "main-content links come first")
        let navigation = page.links.firstIndex { $0.title == "網站首頁" } ?? -1
        try check(navigation > 5, "menu links follow the results")
        try check(!page.hasPasswordField && !page.hasCaptcha, "ordinary page signals")
        do { _ = try await tab.load(url("/go-logout")); throw Failure(name: "redirect to log out was followed") }
        catch let error as ChatWebExecutionError { try check(error == .blocked(.accountAction), "redirect to log out stopped") }
        do { _ = try await tab.load(url("/account/login")); throw Failure(name: "sign-in page opened") }
        catch let error as ChatWebExecutionError { try check(error == .signInRequired, "sign-in page left to the user") }
        do { _ = try await tab.load(URL(string: "https://192.168.0.1/")!); throw Failure(name: "private address opened") }
        catch let error as ChatWebExecutionError { try check(error == .blocked(.notPublic), "private address refused") }
        do { _ = try await tab.load(url("/download")); throw Failure(name: "download started") }
        catch let error as ChatWebExecutionError { try check(error == .navigationFailed("download"), "downloads refused") }
        _ = try await tab.load(url("/dialog"))
        try check(tab.lastDialog == "fixture alert", "page dialogs close at once")
        _ = try await tab.load(url("/members/signon"))
        try check(try await tab.capture().hasPasswordField, "password field noticed")
        _ = try await tab.load(url("/captcha"))
        try check(try await tab.capture().hasCaptcha, "CAPTCHA noticed")
        _ = try await tab.load(url("/shop/search?keyword=earbuds"))
        try check(!(try await tab.capture().text.contains("型號 8")), "list starts short")
        try check(try await tab.scroll(.down), "scroll moves")
        try check(try await tab.capture().text.contains("型號 8"), "content loaded on scrolling is read")
        _ = try await tab.load(url("/jobs/job/2"))
        try check(try await tab.waitFor(.textPresent, value: "Swift", seconds: 2), "wait: text present")
        try check(!(try await tab.waitFor(.textAbsent, value: "Swift", seconds: 1)), "wait: text not absent")
        try check(try await tab.waitFor(.urlContains, value: "/jobs/job/", seconds: 1), "wait: URL contains")
        let back = try await tab.goBack()
        try check(back?.url.path == "/shop/search", "back to the previous page")
        try check(tab.currentURL?.query == "keyword=earbuds", "back keeps the query")
        tab.close()
    }

    static func runnerOnRealPages(_ server: URL) async throws {
        let tab = ChatWebTaskTab(dataStore: .nonPersistent(), fixtureOrigin: server)
        let mount = Mount(tab.webView)
        defer { mount.close() }
        let entry = #"{"action":"web_read_page","url":"\#(server.absoluteString)/jobs/search?keyword=iOS"}"#
        let model = AppScriptedModel([
            #"{"action":"web_open_link","linkID":1}"#, #"{"action":"web_find","text":"Swift"}"#, #"{"action":"web_back"}"#,
            #"{"action":"web_open_link","linkID":2}"#, #"{"action":"finish","answer":"兩個職缺都要 Swift。","sources":[2,3]}"#])
        let runner = ChatWebTaskRunner(client: model, executor: tab,
                                       configuration: ModelConfiguration(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture"),
                                       apiKey: "dummy", settings: .init(searchTemplate: "https://www.google.com/search?q=%s", fixtureOrigin: server),
                                       sleep: { _ in })
        let result = await runner.run(conversation: [ModelMessage(role: "user", content: "找 iOS 職缺")],
                                      entry: try ChatWebCommand.parseEntry(entry), entryRaw: entry)
        try check(result.status == .succeeded && result.sources.map(\.id) == [2, 3], "real pages: task finished with sources")
        try check(result.sources[0].url.path == "/jobs/job/1" && result.sources[1].url.path == "/jobs/job/2", "sources are the job pages")
        let requests = await model.requests
        try check(requests[2].last?.content.contains("\"total\":") == true, "find ran on the real page")
        try check(requests.allSatisfy { $0[0].content.hasPrefix("You are carrying out") }, "every step uses the task instructions")
        tab.close()
    }

    #if DEBUG
    /// The whole chat path: the ordinary reply's web command, the task tab,
    /// the round written to the encrypted archive, stop, pause and the plain
    /// path, with the Debug model fixture and the Debug loopback website.
    static func chatEndToEnd() async throws {
        guard let fixture = ChatWebTaskFixture.shared else { throw Failure(name: "run with -UITestMode -UITestChatWeb") }
        let origin = try await fixture.start()
        let e = try AppEnvironment()
        defer { e.close() }
        let session = e.session(UITestChatModelClient())
        session.webTaskEnvironment = {
            ChatWebTaskEnvironment(dataStore: .nonPersistent(), searchTemplate: "https://www.google.com/search?q=%s",
                                   fixtureOrigin: origin, skipsPacing: true)
        }
        // Memory on: the reviewed structured flow offers the web entry.
        try check(e.learning.updatePreferences { $0.useMemory = true; $0.autoRemember = false }, "memory on")
        let jobs = "在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較"
        let first = try start(session, jobs)
        try await waitUntil("task card") { session.webTask != nil }
        var mount = Mount(session.webTask!.tab.webView)
        await first.value
        mount.close()
        let reply = session.entries.last?.content ?? ""
        try check(session.entries.map(\.role) == ["user", "assistant"] && reply.hasPrefix("WEB_TASK_JOBS_DONE"), "answer written")
        try check(reply.contains("\n\n來源\n1. [") && reply.contains("/jobs/job/1)"), "sources listed as links")
        try check(session.draft.isEmpty && session.chatError == nil, "draft cleared after the task")
        try check(e.reopen().conversations.first?.turns.last?.assistantText == reply, "round saved in the archive")
        try check(fixture.requestedPaths.contains("GET /jobs/search?keyword=iOS") && fixture.requestedPaths.contains("GET /jobs/job/1"),
                  "the task tab visited the loopback site")
        try await waitUntil("task tab closes after a moment", seconds: 6) { session.webTask == nil }

        // Stop: the round is still written, like Android.
        let stopping = try start(session, "[fixture:web-stop]")
        try await waitUntil("stop task starts") { session.webTask != nil }
        mount = Mount(session.webTask!.tab.webView)
        try await waitUntil("stop task reads its first page") { (session.webTask?.steps.count ?? 0) >= 2 }
        session.cancel()
        await stopping.value
        mount.close()
        let stopped = session.entries.last?.content ?? ""
        try check(stopped.hasPrefix("已停止。") && stopped.contains("已讀的頁面"),
                  "stopped round written with pages read: " + String(stopped.prefix(160)) + " | " + (session.chatError ?? "-"))
        try check(session.entries.count == 4 && !session.isSubmitting, "stop ends the request")

        // Background pause, then the list that grows on scrolling.
        try await waitUntil("previous tab closes", seconds: 6) { session.webTask == nil }
        let shop = try start(session, "在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點")
        try await waitUntil("shop task starts") { session.webTask != nil }
        mount = Mount(session.webTask!.tab.webView)
        session.webTaskScenePhaseChanged(isActive: false, isBackground: true)
        try check(session.webTask?.phase == .paused, "background pauses")
        let pausedSteps = session.webTask?.steps.count ?? -1
        try await Task.sleep(nanoseconds: 1_500_000_000)
        try check((session.webTask?.steps.count ?? -2) <= pausedSteps + 2, "at most the step under way finishes while paused")
        session.webTaskScenePhaseChanged(isActive: false, isBackground: false)
        try check(session.webTask?.phase == .paused, ".inactive changes nothing")
        session.webTaskScenePhaseChanged(isActive: true, isBackground: false)
        await shop.value
        mount.close()
        try check(session.entries.last?.content.hasPrefix("WEB_TASK_SHOP_DONE 8") == true, "resumed task read the grown list")

        // Memory off: the plain reply can start a task too.
        try check(e.learning.updatePreferences { $0.useMemory = false }, "memory off")
        try await waitUntil("previous tab closes", seconds: 6) { session.webTask == nil }
        let news = try start(session, "在內建瀏覽器找一篇最近的 AI 新聞，摘要三個重點")
        try await waitUntil("news task starts") { session.webTask != nil }
        mount = Mount(session.webTask!.tab.webView)
        await news.value
        mount.close()
        try check(session.entries.last?.content.hasPrefix("WEB_TASK_NEWS_DONE") == true, "plain chat starts a web task")
        let plain = try start(session, "你好")
        await plain.value
        try check(session.entries.last?.content == "測試回覆：你好", "ordinary plain chat unchanged")
    }

    private static func start(_ session: ChatSession, _ prompt: String) throws -> Task<Void, Never> {
        session.draft = prompt; session.send()
        guard let task = session.capturedArchiveRequest else { throw Failure(name: "request not started: " + (session.chatError ?? "")) }
        return task
    }
    #endif

    static func waitUntil(_ name: String, seconds: Double = 20, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else { throw Failure(name: "timed out: " + name) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

actor AppScriptedModel: ChatModelClient {
    private var replies: [String]
    private(set) var requests: [[ModelMessage]] = []
    init(_ replies: [String]) { self.replies = replies }
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        requests.append(messages)
        return replies.isEmpty ? #"{"action":"end_not_done","reason":"script ended"}"# : replies.removeFirst()
    }
}

#if DEBUG
private final class AppKeys: LearningKeyStore {
    var values: [String: Data] = [:]
    func read(id: String) throws -> Data? { values[id] }
    func insert(_ key: Data, id: String) throws { values[id] = key }
    func remove(id: String) throws { values.removeValue(forKey: id) }
    func removeAll(except id: String) throws { values = values.filter { $0.key == id } }
}
private final class AppCredentials: ModelCredentialStoring {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func insert(_ key: String, account: String) throws { values[account] = key }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values = [:] }
}
@MainActor private final class AppEnvironment {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("woow-chat-web-" + UUID().uuidString)
    let suite = "woow.chat-web.check." + UUID().uuidString
    let keys = AppKeys(), learningKeys = AppKeys()
    let defaults: UserDefaults
    let repository: ModelSettingsRepository
    let learning: LearningStore
    let archive: ConversationArchiveStore
    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        repository = ModelSettingsRepository(defaults: defaults, credentials: AppCredentials())
        _ = try repository.save(baseURL: "https://model.example.invalid/v1", model: "fixture", newKey: "synthetic-not-a-key")
        try repository.recordConsentForMain() // the user agreed to share content (App Review 5.1.2(i))
        learning = LearningStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("learning.vault"), keys: learningKeys))
        guard learning.updatePreferences({ $0.useMemory = false; $0.autoRemember = false }) else {
            throw ChatWebTaskAppChecks.Failure(name: "isolated learning creation")
        }
        archive = ConversationArchiveStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("archive.vault"), keys: keys))
    }
    func session(_ client: any ChatModelClient) -> ChatSession {
        ChatSession(learning: learning, repository: repository, client: client, archive: archive)
    }
    func reopen() -> ConversationArchiveStore {
        ConversationArchiveStore(vault: EncryptedLearningFile(url: root.appendingPathComponent("archive.vault"), keys: keys))
    }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}
#endif

#if CHAT_WEB_TASK_APP_STANDALONE
@main enum CheckChatWebTaskApp {
    @MainActor static func main() {
        guard let address = CommandLine.arguments.dropFirst().first, let server = URL(string: address) else {
            print("usage: checks <loopback-origin> [-UITestMode -UITestChatWeb]"); exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let count = try await ChatWebTaskAppChecks.run(server: server)
                print(#"{"assertions": \#(count)}"#); fflush(stdout)
                exit(0)
            } catch {
                print("FAIL chat web task app: \(error)"); fflush(stdout)
                exit(1)
            }
        }
        app.run()
    }
}
#endif
