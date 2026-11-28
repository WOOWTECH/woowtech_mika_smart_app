import XCTest
@testable import AssistantPersistence

/// The same cases as Android woow.26 `BotPushPreviewTest`, plus the iOS reads through a stubbed URL loading system.
final class BotPushPreviewTests: XCTestCase {
    private let bots = Data(#"""
    {"bots":[{"id":"bot_1","name":"Podman QA","threadId":"t"},{"id":"bot_2","name":7}],
     "groups":[{"id":"room_1","name":"Research room"}],"sections":[]}
    """#.utf8)

    func testNameComesFromBotsOrRoomsOnly() {
        XCTAssertEqual(BotPushPreviewText.name(bots, botID: "bot_1"), "Podman QA")
        XCTAssertEqual(BotPushPreviewText.name(bots, botID: "room_1"), "Research room")
        XCTAssertNil(BotPushPreviewText.name(bots, botID: "bot_2"))
        XCTAssertNil(BotPushPreviewText.name(bots, botID: "missing"))
        XCTAssertNil(BotPushPreviewText.name(Data("not json".utf8), botID: "bot_1"))
        XCTAssertNil(BotPushPreviewText.name(Data(#"{"bots":{}}"#.utf8), botID: "bot_1"))
        let long = BotPushPreviewText.name(Data(#"{"bots":[{"id":"b","name":"\#(String(repeating: "n", count: 200))"}]}"#.utf8), botID: "b")!
        XCTAssertEqual(long.utf16.count, BotPushPreviewText.nameMax)
        XCTAssertEqual(BotPushPreviewText.name(Data(#"{"bots":[{"id":"b","name":"A‮\n B"}]}"#.utf8), botID: "b"), "A B")
    }

    func testExcerptIsTheReplyAfterTheLastUserMessage() {
        let thread = Data(#"""
        {"messages":[
          {"role":"bot","kind":"text","text":"Earlier answer"},
          {"role":"user","kind":"text","text":"Question"},
          {"role":"bot","kind":"activity","text":""},
          {"role":"bot","kind":"text","text":"## Result\n**Done**: see [the file](https://x.example/f)."},
          {"role":"bot","kind":"text","text":"Second   part"}],"hasMore":true}
        """#.utf8)
        XCTAssertEqual(BotPushPreviewText.excerpt(thread), "Result\nDone: see the file.\nSecond part")
    }

    func testExcerptFallsBackToTheLastBotTextAndRejectsEmptyOrMalformed() {
        XCTAssertEqual(BotPushPreviewText.excerpt(Data(#"{"messages":[{"role":"bot","text":"Hi"},{"role":"user","text":"Q"}]}"#.utf8)), "Hi")
        XCTAssertNil(BotPushPreviewText.excerpt(Data(#"{"messages":[{"role":"user","text":"Q"}]}"#.utf8)))
        XCTAssertNil(BotPushPreviewText.excerpt(Data(#"{"messages":[]}"#.utf8)))
        XCTAssertNil(BotPushPreviewText.excerpt(Data(#"{"messages":"x"}"#.utf8)))
        XCTAssertNil(BotPushPreviewText.excerpt(Data("<html>".utf8)))
    }

    func testCleanBoundsLengthWithoutSplittingCharacters() {
        let text = BotPushPreviewText.clean(String(repeating: "a", count: 398) + "😀😀", max: 400, singleLine: false)
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(text.utf16.count, 400)
        XCTAssertFalse(UTF16.isLeadSurrogate(Array(text.dropLast().utf16).last!))
        XCTAssertEqual(BotPushPreviewText.clean("```kotlin\nx\n```\n\n\n> y", max: 400, singleLine: true), "x y")
    }

    func testOnlyTheTwoFixedPreviewPathsAreAllowed() {
        XCTAssertTrue(BotPushPreviewText.isPreviewPath("/api/bots?messages=1"))
        XCTAssertTrue(BotPushPreviewText.isPreviewPath(BotPushPreviewText.messagesPath("thread_1:a.b-c")!))
        XCTAssertNil(BotPushPreviewText.messagesPath("../x"))
        for path in ["/api/bots", "/api/bots?messages=200", "/api/threads/../messages?limit=8", "/api/threads/a/messages?limit=200",
                     "/api/threads/a/messages?limit=8&before=x", "/api/threads/a/b/messages?limit=8", "/api/threads//messages?limit=8"] {
            XCTAssertFalse(BotPushPreviewText.isPreviewPath(path), path)
        }
    }

    func testBodyPrefixesQuestionsAndFailuresAndPlaceholdersFollowTheReason() {
        XCTAssertEqual(BotPushPreviewText.body(excerpt: "OK", reason: "finished", english: false), "OK")
        XCTAssertEqual(BotPushPreviewText.body(excerpt: "OK", reason: "failed", english: false), "未能完成：OK")
        XCTAssertEqual(BotPushPreviewText.body(excerpt: "OK", reason: "permission", english: true), "Needs you: OK")
        XCTAssertEqual(BotPushPreviewText.body(excerpt: "OK", reason: "attention", english: false), "需要處理：OK")
        XCTAssertEqual(BotPushPreviewText.category(reason: "permission"), "woowtechbot.attention")
        XCTAssertEqual(BotPushPreviewText.generic(reason: "failed", english: false), "機器人未能完成，請開啟查看。")
    }

    func testCredentialsAcceptOnlyAnHTTPSOriginAndBoundedHeaders() throws {
        let id = UUID()
        XCTAssertNoThrow(try BotPushPreviewCredential(serviceId: id, origin: "https://bot.example.com", cookie: "c=1", sessionId: "s1", locale: "en"))
        for (origin, cookie, session, locale) in [("http://bot.example.com", "c=1", "s", "en"), ("https://bot.example.com/x", "c=1", "s", "en"),
                                                  ("https://bot.example.com", "", "s", "en"), ("https://bot.example.com", "c=1\r\nX: y", "s", "en"),
                                                  ("https://bot.example.com", "c=1", "s\n", "en"), ("https://bot.example.com", "c=1", "s", "fr")] {
            XCTAssertThrowsError(try BotPushPreviewCredential(serviceId: id, origin: origin, cookie: cookie, sessionId: session, locale: locale), origin)
        }
    }

    func testPreviewReadsBothPartsWithTheSessionAndKeepsWhatAnswered() async throws {
        let credential = try BotPushPreviewCredential(serviceId: UUID(), origin: "https://bot.example.com", cookie: "c=1", sessionId: "s1", locale: "zh-TW")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        Stub.answers = ["/api/bots?messages=1": (200, bots),
                        "/api/threads/thread_1/messages?limit=8": (200, Data(#"{"messages":[{"role":"user","text":"Q"},{"role":"bot","text":"Answer"}]}"#.utf8))]
        Stub.seen = []
        let full = await BotPushPreviewFetch.preview(credential, botID: "bot_1", threadID: "thread_1", configuration: configuration)
        XCTAssertEqual(full, BotPushPreview(botName: "Podman QA", excerpt: "Answer"))
        XCTAssertEqual(Set(Stub.seen.map(\.path)), ["/api/bots?messages=1", "/api/threads/thread_1/messages?limit=8"])
        for request in Stub.seen {
            XCTAssertEqual(request.cookie, "c=1"); XCTAssertEqual(request.origin, "https://bot.example.com"); XCTAssertEqual(request.session, "s1")
        }
        Stub.answers["/api/threads/thread_1/messages?limit=8"] = (500, Data())
        let nameOnly = await BotPushPreviewFetch.preview(credential, botID: "bot_1", threadID: "thread_1", configuration: configuration)
        XCTAssertEqual(nameOnly, BotPushPreview(botName: "Podman QA", excerpt: nil))
        let none = await BotPushPreviewFetch.preview(credential, botID: "missing", threadID: "thread_1", configuration: configuration)
        XCTAssertNil(none)
        let invalid = await BotPushPreviewFetch.preview(credential, botID: "../x", threadID: "thread_1", configuration: configuration)
        XCTAssertNil(invalid)
        Stub.answers["/api/bots?messages=1"] = (200, Data(repeating: 32, count: BotPushPreviewFetch.limit + 1))
        let oversize = await BotPushPreviewFetch.preview(credential, botID: "bot_1", threadID: "thread_1", configuration: configuration)
        XCTAssertNil(oversize)
    }
}

/// Answers the two preview reads in memory and records what each request carried.
private final class Stub: URLProtocol {
    struct Seen { let path: String; let cookie: String?; let origin: String?; let session: String? }
    nonisolated(unsafe) static var answers: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var seen: [Seen] = []
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let path = url.path + (url.query.map { "?" + $0 } ?? "")
        Self.lock.lock()
        Self.seen.append(Seen(path: path, cookie: request.value(forHTTPHeaderField: "Cookie"),
                              origin: request.value(forHTTPHeaderField: "Origin"), session: request.value(forHTTPHeaderField: "X-Woowtech-Session-Id")))
        let answer = Self.answers[path] ?? (404, Data())
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
