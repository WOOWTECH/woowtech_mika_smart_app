import Foundation

/// Manual browsing accepts ordinary query strings, fragments and login endpoints.
/// Research/DOM planners keep their separate, narrower WebsiteOrigin policy.
public enum BrowserManualNavigationPolicy {
    public static func resolve(address: String) -> URL? {
        guard address.utf8.count <= 8192,
              case let .allow(url) = BrowserPolicy.evaluate(address: address),
              allows(url) else { return nil }
        return url
    }

    public static func allows(_ url: URL) -> Bool {
        guard url.baseURL == nil, url.scheme?.lowercased() == "https",
              url.absoluteString.utf8.count <= 8192 else { return false }
        if case .allow = BrowserPolicy.evaluate(url) { return true }
        return false
    }

    /// Session/callback URLs stay in WebKit's current page, never in the library.
    /// This is a conservative known-secret filter, not a guarantee that every URL
    /// is public. The library is separately encrypted and never model context.
    public static func libraryURL(_ url: URL) -> URL? {
        guard allows(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let sensitive = ["code", "token", "key", "secret", "password", "passwd", "credential", "signature", "session", "authorization", "assertion", "samlresponse", "apikey", "accesstoken", "refreshtoken", "idtoken", "sessionid", "clientsecret"]
        guard !(parts.queryItems ?? []).contains(where: { item in
            let name = item.name.lowercased().replacingOccurrences(of: "-", with: "_")
            return sensitive.contains { name == $0 || name.hasSuffix("_" + $0) || name.hasPrefix($0 + "_") }
        }) else { return nil }
        let components = url.path.lowercased().split(separator: "/")
        guard !components.contains(where: { ["callback", "oauth", "authorize", "webhook"].contains(String($0)) }) else { return nil }
        parts.fragment = nil
        return parts.url
    }
}

public struct BrowserSavedPage: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public var title: String
    public let date: Date
    public var edited: Bool
    public init(id: UUID = UUID(), url: URL, title: String, date: Date = .now, edited: Bool = false) {
        self.id = id; self.url = url; self.title = String(title.prefix(256)); self.date = date; self.edited = edited
    }
}

public enum BrowserLibraryError: Error, Equatable { case invalidURL, invalidState, tabLimit, notFound, invalidTitle }

/// Mika PageBookmarks/RecentPages behavior: fragment-insensitive keys, newest
/// first, 300 bookmarks and 500 history entries, user-renamed titles retained.
/// iOS adds bounded tab restoration and fail-closed encrypted persistence.
public struct BrowserLibraryState: Codable, Equatable, Sendable {
    public static let maximumTabs = 20
    public private(set) var version = 1
    public private(set) var tabs: [BrowserTab]
    public private(set) var selectedID: UUID
    public private(set) var bookmarks: [BrowserSavedPage] = []
    public private(set) var history: [BrowserSavedPage] = []
    public private(set) var userSiteModes = BrowserUserSiteModes()
    public private(set) var searchSettings = BrowserSearchSettings()
    /// Play's 網站登入 list for the person's own browsing (see BrowserSignInSite).
    public private(set) var signInSites: [BrowserSignInSite] = []
    public static let maximumSignInSites = 200

    public init() {
        let tab = BrowserTab(title: "新分頁")
        tabs = [tab]; selectedID = tab.id
    }

    private enum CodingKeys: String, CodingKey {
        case version, tabs, selectedID, bookmarks, history, userSiteModes, searchSettings, signInSites
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        tabs = try values.decode([BrowserTab].self, forKey: .tabs)
        selectedID = try values.decode(UUID.self, forKey: .selectedID)
        bookmarks = try values.decode([BrowserSavedPage].self, forKey: .bookmarks)
        history = try values.decode([BrowserSavedPage].self, forKey: .history)
        // Additive v1 migration: only an absent field defaults to mobile. A
        // present malformed/null field must not silently erase saved choices.
        userSiteModes = values.contains(.userSiteModes)
            ? try values.decode(BrowserUserSiteModes.self, forKey: .userSiteModes) : .init()
        searchSettings = values.contains(.searchSettings)
            ? try values.decode(BrowserSearchSettings.self, forKey: .searchSettings) : .init()
        signInSites = values.contains(.signInSites)
            ? try values.decode([BrowserSignInSite].self, forKey: .signInSites) : []
    }

    public mutating func setManualSiteMode(_ mode: BrowserManualSiteMode, for host: String) throws {
        try userSiteModes.set(mode, for: host)
    }

    public mutating func selectSearchEngine(_ id: String) throws { try searchSettings.select(id) }
    public mutating func addSearchEngine(_ engine: BrowserSearchEngine) throws { try searchSettings.add(engine) }
    public mutating func removeSearchEngine(_ id: String) { searchSettings.remove(id) }

    public func validate() throws {
        try userSiteModes.validate()
        try searchSettings.validate()
        guard version == 1, !tabs.isEmpty, tabs.count <= Self.maximumTabs,
              Set(tabs.map(\.id)).count == tabs.count, tabs.contains(where: { $0.id == selectedID }),
              bookmarks.count <= 300, history.count <= 500 else { throw BrowserLibraryError.invalidState }
        for tab in tabs {
            guard tab.title.count <= 256, tab.lastVisitedAt.timeIntervalSince1970.isFinite,
                  tab.url == nil || BrowserManualNavigationPolicy.libraryURL(tab.url!) == tab.url else { throw BrowserLibraryError.invalidState }
        }
        guard signInSites.count <= Self.maximumSignInSites,
              Set(signInSites.map(\.host)).count == signInSites.count,
              signInSites.allSatisfy({ BrowserSignInSite.key($0.host) == $0.host && $0.lastVisit.timeIntervalSince1970.isFinite })
        else { throw BrowserLibraryError.invalidState }
        for entries in [bookmarks, history] {
            guard Set(entries.map(\.id)).count == entries.count,
                  Set(entries.map(\.url)).count == entries.count else { throw BrowserLibraryError.invalidState }
            for entry in entries {
                guard entry.title.count <= 256, entry.date.timeIntervalSince1970.isFinite,
                      BrowserManualNavigationPolicy.libraryURL(entry.url) == entry.url else { throw BrowserLibraryError.invalidState }
            }
        }
    }

    @discardableResult public mutating func addTab(url: URL? = nil) throws -> UUID {
        guard tabs.count < Self.maximumTabs else { throw BrowserLibraryError.tabLimit }
        if let url, BrowserManualNavigationPolicy.libraryURL(url) == nil { throw BrowserLibraryError.invalidURL }
        let tab = BrowserTab(title: "新分頁", url: url.flatMap(BrowserManualNavigationPolicy.libraryURL))
        tabs.append(tab); selectedID = tab.id
        return tab.id
    }
    public mutating func select(_ id: UUID) throws {
        guard tabs.contains(where: { $0.id == id }) else { throw BrowserLibraryError.notFound }
        selectedID = id
    }
    /// Close the document in one tab without deleting its bookmarks, history,
    /// website data, or the tab itself. Persist this before replacing WebKit.
    public mutating func clearPage(in id: UUID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { throw BrowserLibraryError.notFound }
        tabs[index].url = nil
        tabs[index].title = "新分頁"
        tabs[index].lastVisitedAt = .now
    }
    public mutating func close(_ id: UUID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { throw BrowserLibraryError.notFound }
        tabs.remove(at: index)
        if tabs.isEmpty { tabs = [BrowserTab(title: "新分頁")] }
        if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }
    public mutating func visit(tab id: UUID, url: URL, title: String, at date: Date = .now) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { throw BrowserLibraryError.notFound }
        guard BrowserManualNavigationPolicy.allows(url), date.timeIntervalSince1970.isFinite else { throw BrowserLibraryError.invalidURL }
        let retained = BrowserManualNavigationPolicy.libraryURL(url)
        tabs[index].url = retained
        tabs[index].title = retained == nil ? "網站登入頁面" : Self.title(title, fallback: retained!)
        tabs[index].lastVisitedAt = date
        guard let retained else { return }
        history.removeAll { $0.url == retained }
        history.insert(BrowserSavedPage(url: retained, title: Self.title(title, fallback: retained), date: date), at: 0)
        history = Array(history.prefix(500))
        if let bookmark = bookmarks.firstIndex(where: { $0.url == retained && !$0.edited }), !title.isEmpty {
            bookmarks[bookmark].title = Self.title(title, fallback: retained)
        }
    }
    public mutating func bookmark(url: URL, title: String, at date: Date = .now) throws {
        guard let retained = BrowserManualNavigationPolicy.libraryURL(url), date.timeIntervalSince1970.isFinite else { throw BrowserLibraryError.invalidURL }
        bookmarks.removeAll { $0.url == retained }
        bookmarks.insert(BrowserSavedPage(url: retained, title: Self.title(title, fallback: retained), date: date), at: 0)
        bookmarks = Array(bookmarks.prefix(300))
    }
    public mutating func renameBookmark(_ id: UUID, title: String) throws {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 256 else { throw BrowserLibraryError.invalidTitle }
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { throw BrowserLibraryError.notFound }
        bookmarks[index].title = clean; bookmarks[index].edited = true
    }
    /// Play's SiteRegistry.loginObserved for the person's own browsing: a new
    /// site is listed only when a page shows it signed in; a listed site keeps
    /// its entry and records what the page shows now.
    public mutating func observeSignIn(host: String, signedIn: Bool, at date: Date = .now) throws {
        guard let key = BrowserSignInSite.key(host), date.timeIntervalSince1970.isFinite else { throw BrowserLibraryError.invalidURL }
        if let index = signInSites.firstIndex(where: { $0.host == key }) {
            signInSites[index].signedIn = signedIn
            signInSites[index].lastVisit = date
            return
        }
        guard signedIn else { return }
        signInSites.append(BrowserSignInSite(host: key, lastVisit: date, signedIn: true))
        if signInSites.count > Self.maximumSignInSites,
           let oldest = signInSites.indices.min(by: { signInSites[$0].lastVisit < signInSites[$1].lastVisit }) {
            signInSites.remove(at: oldest)
        }
    }
    /// A page of a listed site finished loading.
    public mutating func touchSignInSite(host: String?, at date: Date = .now) {
        guard let host, let key = BrowserSignInSite.key(host), date.timeIntervalSince1970.isFinite,
              let index = signInSites.firstIndex(where: { $0.host == key }) else { return }
        signInSites[index].lastVisit = date
    }
    public mutating func removeSignInSite(host: String) {
        guard let key = BrowserSignInSite.key(host) else { return }
        signInSites.removeAll { $0.host == key }
    }
    /// The website-data record [recordName] was removed: its sites are signed out.
    public mutating func removeSignInSites(coveredByRecordNamed recordName: String) {
        signInSites.removeAll { $0.isCovered(byRecordNamed: recordName) }
    }
    public mutating func clearSignInSites() { signInSites = [] }
    /// Like Play's list: signed-in sites first, then the most recently visited.
    public var signInList: [BrowserSignInSite] {
        signInSites.sorted { first, second in
            first.signedIn != second.signedIn ? first.signedIn : first.lastVisit > second.lastVisit
        }
    }
    public mutating func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id } }
    public mutating func removeHistory(_ id: UUID) { history.removeAll { $0.id == id } }
    public mutating func clearHistory() { history = [] }
    private static func title(_ text: String, fallback url: URL) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? url.host ?? "網頁" : clean).prefix(256))
    }
}
