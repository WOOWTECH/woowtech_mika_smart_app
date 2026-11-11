import XCTest
@testable import AssistantBrowser

final class BrowserLibraryTests: XCTestCase {
    func testManualAddressRejectsMalformedPortsWithoutChangingTheDestination() {
        for authority in ["example.com:", "example.com:999999999999999999999999", "example.com:0", "example.com:65536", "[2606:4700::1111]:", "[2606:4700::1111]:999999999999999999999999"] {
            XCTAssertNil(BrowserManualNavigationPolicy.resolve(address: "https://\(authority)/"))
        }
        for address in ["https://example.com/path?next=host:999999999999999999999999#part", "https://example.com:443/", "https://example.com:00080/", "https://[2606:4700::1111]:65535/"] {
            XCTAssertEqual(BrowserManualNavigationPolicy.resolve(address: address), URL(string: address))
        }
        // Modern Foundation converts these hosts to IDNA; older parsers can
        // reject them. Raw port validation must preserve existing host handling.
        for address in ["https://bücher.de/", "https://例子.tw/"] {
            if let parsed = URL(string: address) {
                XCTAssertEqual(BrowserManualNavigationPolicy.resolve(address: address), parsed)
            } else {
                XCTAssertNil(BrowserManualNavigationPolicy.resolve(address: address))
            }
        }
    }

    func testManualNavigationDoesNotRelaxResearchPolicy() throws {
        for address in ["https://example.com/login?return=%2Faccount", "https://example.com/#section", "https://example.com/checkout"] {
            let url = URL(string: address)!
            XCTAssertTrue(BrowserManualNavigationPolicy.allows(url))
        }
        for address in ["http://example.com", "https://user:pass@example.com", "https://127.0.0.1", "https://10.0.0.1", "file:///tmp/a", "javascript:alert(1)"] {
            XCTAssertFalse(BrowserManualNavigationPolicy.allows(URL(string: address)!))
        }
        XCTAssertThrowsError(try WebsiteOrigin(url: URL(string: "https://example.com/?q=search")!))
        XCTAssertThrowsError(try WebsiteOrigin(url: URL(string: "https://example.com/checkout")!))
    }

    func testTabsSelectionClosingAndRestore() throws {
        var state = BrowserLibraryState()
        let first = state.selectedID
        let second = try state.addTab(url: URL(string: "https://example.com/second")!)
        try state.select(first)
        try state.close(second)
        XCTAssertEqual(state.selectedID, first)
        try state.close(first)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertNotEqual(state.selectedID, first)
        for _ in 1..<BrowserLibraryState.maximumTabs { _ = try state.addTab() }
        XCTAssertThrowsError(try state.addTab())
        let restored = try JSONDecoder().decode(BrowserLibraryState.self, from: JSONEncoder().encode(state))
        try restored.validate()
        XCTAssertEqual(restored, state)
    }

    func testClosingPageKeepsTabIdentityBookmarksHistoryAndOtherPage() throws {
        var state = BrowserLibraryState()
        let firstID = state.selectedID
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.org/second")!
        try state.visit(tab: firstID, url: firstURL, title: "First")
        try state.bookmark(url: firstURL, title: "Saved")
        let secondID = try state.addTab()
        try state.visit(tab: secondID, url: secondURL, title: "Second")
        let history = state.history, bookmarks = state.bookmarks
        try state.clearPage(in: secondID)
        XCTAssertEqual(state.selectedID, secondID)
        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.tabs.first(where: { $0.id == secondID })?.url)
        XCTAssertEqual(state.tabs.first(where: { $0.id == secondID })?.title, "新分頁")
        XCTAssertEqual(state.tabs.first(where: { $0.id == firstID })?.url, firstURL)
        XCTAssertEqual(state.history, history)
        XCTAssertEqual(state.bookmarks, bookmarks)
        XCTAssertThrowsError(try state.clearPage(in: UUID()))
        try state.validate()
        XCTAssertEqual(try JSONDecoder().decode(BrowserLibraryState.self,
                          from: JSONEncoder().encode(state)), state)
    }

    func testBookmarksDeduplicateFragmentsAndPreserveUserTitles() throws {
        var state = BrowserLibraryState()
        let url = URL(string: "https://example.com/page?q=one#first")!
        try state.bookmark(url: url, title: "Original")
        let id = try XCTUnwrap(state.bookmarks.first?.id)
        try state.renameBookmark(id, title: "My title")
        try state.visit(tab: state.selectedID, url: URL(string: "https://example.com/page?q=one#second")!, title: "Website title")
        XCTAssertEqual(state.bookmarks.first?.title, "My title")
        XCTAssertEqual(state.history.first?.url.absoluteString, "https://example.com/page?q=one")
        XCTAssertThrowsError(try state.renameBookmark(id, title: "  "))
        try state.bookmark(url: URL(string: "https://example.com/page?q=one#third")!, title: "Re-added")
        XCTAssertEqual(state.bookmarks.count, 1)
        state.removeBookmark(state.bookmarks[0].id)
        XCTAssertTrue(state.bookmarks.isEmpty)
    }

    func testHistoryCapacityOrderAndSeparateClear() throws {
        var state = BrowserLibraryState()
        let bookmarked = URL(string: "https://example.com/bookmark")!
        try state.bookmark(url: bookmarked, title: "Keep")
        for i in 0..<520 {
            try state.visit(tab: state.selectedID, url: URL(string: "https://example.com/\(i)")!, title: "Page \(i)")
        }
        XCTAssertEqual(state.history.count, 500)
        XCTAssertEqual(state.history.first?.title, "Page 519")
        try state.visit(tab: state.selectedID, url: state.history[10].url, title: "Revisit")
        XCTAssertEqual(state.history.count, 500)
        XCTAssertEqual(state.history.first?.title, "Revisit")
        state.clearHistory()
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.bookmarks.count, 1)
        XCTAssertNotNil(state.tabs.first?.url)
        try state.validate()
    }

    func testCallbackSecretsNotRetainedOrBookmarked() throws {
        var state = BrowserLibraryState()
        let safe = URL(string: "https://example.com/home")!
        try state.visit(tab: state.selectedID, url: safe, title: "Home")
        for address in ["https://example.com/?code=secret", "https://example.com/?access_token=secret", "https://example.com/?apiKey=secret", "https://example.com/?accessToken=secret", "https://example.com/?clientSecret=secret", "https://example.com/webhook/secret", "https://example.com/oauth/callback"] {
            let url = URL(string: address)!
            XCTAssertTrue(BrowserManualNavigationPolicy.allows(url))
            XCTAssertNil(BrowserManualNavigationPolicy.libraryURL(url))
            XCTAssertThrowsError(try state.bookmark(url: url, title: "No"))
            try state.visit(tab: state.selectedID, url: url, title: "Private")
            XCTAssertNil(state.tabs.first?.url)
            XCTAssertEqual(state.tabs.first?.title, "網站登入頁面")
            XCTAssertEqual(state.history.count, 1)
        }
        let bytes = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("secret"))
        try state.validate()
    }

    func testExternalOpenRequiresTheCompletedVisiblePublicPage() {
        let page = URL(string: "https://example.com/article?q=one#section")!
        func destination(_ loaded: URL? = page, displayed: URL? = page,
                         loading: Bool = false, pending: Bool = false,
                         automated: Bool = false, busy: Bool = false,
                         available: Bool = true) -> URL? {
            BrowserExternalOpenPolicy.destination(
                loadedURL: loaded, displayedURL: displayed, isLoading: loading,
                navigationPending: pending, isAutomated: automated,
                isBusy: busy, isPageAvailable: available
            )
        }
        XCTAssertEqual(destination(), page,
                       "A safe hash route must identify the same document in the external App")
        let hashRoute = URL(string: "https://example.com/article#/docs/42")!
        XCTAssertEqual(destination(hashRoute, displayed: hashRoute), hashRoute)
        let upperRoute = URL(string: "https://example.com/article#/DOCS/42")!
        XCTAssertEqual(destination(upperRoute, displayed: upperRoute), upperRoute)
        let escapedSearch = URL(string: "https://example.com/article?q=hello%20world#/docs/42")!
        XCTAssertEqual(destination(escapedSearch, displayed: escapedSearch), escapedSearch)
        let anchor = URL(string: "https://example.com/article#overview")!
        XCTAssertEqual(destination(anchor, displayed: anchor), anchor)
        let bareHost = URL(string: "https://example.com")!
        XCTAssertEqual(destination(bareHost, displayed: bareHost), bareHost)
        let escapedPublicPath = URL(string: "https://example.com/public%20guide#/docs/42")!
        XCTAssertEqual(destination(escapedPublicPath, displayed: escapedPublicPath), escapedPublicPath)
        XCTAssertNil(destination(nil))
        XCTAssertNil(destination(displayed: nil))
        XCTAssertNil(destination(displayed: URL(string: "https://example.com/other")!))
        XCTAssertNil(destination(loading: true))
        XCTAssertNil(destination(pending: true))
        XCTAssertNil(destination(automated: true))
        XCTAssertNil(destination(busy: true))
        XCTAssertNil(destination(available: false))
        for address in [
            "https://example.com/?code=private",
            "https://example.com/?access_token=private",
            "https://example.com/?jwt=private",
            "https://example.com/?AUTH=private",
            "https://example.com/?%6Awt=private",
            "https://example.com/?%2561uth=private",
            "https://example.com/?authKey=private",
            "https://example.com/?j%2577t=private",
            "https://example.com/oauth/callback",
            "https://example.com/authToken/fixture",
            "https://example.com/session/fixture",
            "https://example.com/reset/fixture",
            "https://example.com/AUTH_token/fixture",
            "https://example.com/%61uthToken/fixture",
            "https://example.com/%2561uthToken/fixture",
            "https://example.com/%73ession/fixture",
            "https://example.com/%2572eset/fixture",
            "https://example.com/%2FauthToken/fixture",
            "https://example.com/%EF%BC%A1uthToken/fixture",
            "https://user:private@example.com/",
            "http://example.com/",
            "https://127.0.0.1/",
            "https://example.com/article#JWT=private",
            "https://example.com/article#JWT",
            "https://example.com/article#/?AUTH=private",
            "https://example.com/article#/%6Awt=private",
            "https://example.com/article#/%2561uth=private",
            "https://example.com/article#/Auth/private",
            "https://example.com/article#/docs/authToken",
            "https://example.com/article#/docs/0123456789abcdef0123456789abcdef",
            "https://example.com/article#/docs/AbCDefGhIjKlMnOpQrStUvWxYz-_",
            "https://example.com/article#/docs/a1b2c3d4e5f6g7h8",
            "https://example.com/article#/docs/42%2Ftoken"
        ] {
            let url = URL(string: address)!
            XCTAssertNil(destination(url, displayed: url), address)
        }
        for key in ["jwt", "auth"] {
            let oldLibraryURL = URL(string: "https://example.com/?\(key)=private")!
            XCTAssertNotNil(BrowserManualNavigationPolicy.libraryURL(oldLibraryURL),
                            "Legacy storage validation is intentionally unchanged; external handoff is stricter")
            XCTAssertNil(destination(oldLibraryURL, displayed: oldLibraryURL))
        }
        let oldPath = URL(string: "https://example.com/authToken/fixture")!
        XCTAssertNotNil(BrowserManualNavigationPolicy.libraryURL(oldPath),
                        "Legacy library validation cannot be tightened without a storage migration")
        XCTAssertNil(destination(oldPath, displayed: oldPath))
    }

    func testCorruptLibraryIsRejectedInsteadOfReset() throws {
        let state = BrowserLibraryState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["version"] = 999
        let decoded = try JSONDecoder().decode(BrowserLibraryState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try decoded.validate())
        json["version"] = 1; json["tabs"] = [Any]()
        let empty = try JSONDecoder().decode(BrowserLibraryState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try empty.validate())
    }
}
