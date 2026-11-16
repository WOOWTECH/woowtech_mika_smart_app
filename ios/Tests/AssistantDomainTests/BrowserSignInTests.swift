import XCTest
@testable import AssistantBrowser

/// Play's LoginProbe guess and SiteRegistry list for the person's own browsing.
final class BrowserSignInTests: XCTestCase {
    private func signals(_ account: [String], password: Bool = false, avatars: Int = 0,
                         url: String = "https://shop.example.com/") -> BrowserSignInSignals {
        BrowserSignInSignals(url: url, passwordVisible: password, account: account, avatars: avatars)
    }

    func testClassifiesSignOutAccountAndSignInEntries() {
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["會員中心", "登出"])), .signedIn)
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["登出測試帳號"])), .signedIn)
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["My account"])), .signedIn)
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["登入"])), .signedOut)
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["Sign in"])), .signedOut)
        XCTAssertEqual(BrowserSignInProbe.classify(signals([], password: true)), .signedOut)
        // An avatar only rules out "signed out"; it never decides "signed in".
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["登入"], avatars: 1)), .unknown)
        XCTAssertEqual(BrowserSignInProbe.classify(signals([])), .unknown)
        // Not sign-out links: full-screen exit, account-deletion help.
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["退出全屏"])), .unknown)
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["帳號註銷說明"])), .unknown)
        // A sign-in or single sign-on address decides nothing.
        XCTAssertEqual(BrowserSignInProbe.classify(signals(["登出"], url: "https://example.com/login")), .unknown)
    }

    func testSignInAddressesAreWholePathSegments() {
        for address in ["https://a.example/login", "https://a.example/login.php", "https://a.example/user-login",
                        "https://a.example/oauth2/authorize?x=1", "https://a.example/sso/"] {
            XCTAssertTrue(BrowserSignInProbe.isSignInAddress(address), address)
        }
        for address in ["https://a.example/search?q=login", "http://127.0.0.1:8080/login-fixture/x/protected",
                        "https://a.example/blog/loginless-design", nil] {
            XCTAssertFalse(BrowserSignInProbe.isSignInAddress(address), address ?? "nil")
        }
    }

    func testParsesOnlyTheProbeShape() {
        let parsed = BrowserSignInProbe.parse(#"{"url":"https://a.example/","pw":true,"account":["登入"],"avatars":0}"#)
        XCTAssertEqual(parsed, signals(["登入"], password: true, url: "https://a.example/"))
        XCTAssertNil(BrowserSignInProbe.parse("not json"))
        XCTAssertNil(BrowserSignInProbe.parse(String(repeating: "a", count: 70_000)))
    }

    func testListAddsOnlySignedInSitesAndKeepsStateCurrent() throws {
        var state = BrowserLibraryState()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try state.observeSignIn(host: "news.example.com", signedIn: false, at: day)
        XCTAssertTrue(state.signInSites.isEmpty, "A site that only looks signed out is not listed.")
        try state.observeSignIn(host: "WWW.Shop.Example.com", signedIn: true, at: day)
        try state.observeSignIn(host: "mail.example.org", signedIn: true, at: day.addingTimeInterval(60))
        XCTAssertEqual(state.signInSites.map(\.host), ["shop.example.com", "mail.example.org"])
        try state.observeSignIn(host: "shop.example.com", signedIn: false, at: day.addingTimeInterval(120))
        XCTAssertEqual(state.signInList.map(\.host), ["mail.example.org", "shop.example.com"],
                       "Signed-in sites come first, then the most recently visited.")
        XCTAssertEqual(state.signInSites.first?.signedIn, false)
        state.touchSignInSite(host: "mail.example.org", at: day.addingTimeInterval(180))
        XCTAssertEqual(state.signInList.first?.lastVisit, day.addingTimeInterval(180))
        XCTAssertThrowsError(try state.observeSignIn(host: "not a host", signedIn: true))

        let restored = try JSONDecoder().decode(BrowserLibraryState.self, from: JSONEncoder().encode(state))
        try restored.validate()
        XCTAssertEqual(restored, state)

        state.removeSignInSites(coveredByRecordNamed: "example.org")
        XCTAssertEqual(state.signInSites.map(\.host), ["shop.example.com"])
        state.removeSignInSite(host: "www.shop.example.com")
        XCTAssertTrue(state.signInSites.isEmpty)
        try state.observeSignIn(host: "127.0.0.1", signedIn: true)
        state.clearSignInSites()
        XCTAssertTrue(state.signInSites.isEmpty)
    }

    func testOlderLibraryWithoutTheListStillLoads() throws {
        var state = BrowserLibraryState()
        try state.bookmark(url: URL(string: "https://example.com/")!, title: "Saved")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "signInSites")
        let legacy = try JSONDecoder().decode(BrowserLibraryState.self, from: JSONSerialization.data(withJSONObject: object))
        try legacy.validate()
        XCTAssertTrue(legacy.signInSites.isEmpty)
        XCTAssertEqual(legacy.bookmarks.map(\.url), state.bookmarks.map(\.url))
    }
}
