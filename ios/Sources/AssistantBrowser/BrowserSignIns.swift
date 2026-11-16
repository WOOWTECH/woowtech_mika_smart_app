import Foundation

/// What a page shows about the person's sign-in (Play's LoginState).
public enum BrowserSignInState: String, Equatable, Sendable {
    case signedIn, signedOut, unknown
}

/// A site the person signed in to in the built-in browser: Play's SiteRegistry
/// entry for the person's own browsing. [signedIn] is what the last look at a
/// page on it showed; the entry stays when it later looks signed out.
public struct BrowserSignInSite: Codable, Equatable, Sendable, Identifiable {
    public let host: String
    public var lastVisit: Date
    public var signedIn: Bool
    public var id: String { host }

    public init(host: String, lastVisit: Date, signedIn: Bool) {
        self.host = host; self.lastVisit = lastVisit; self.signedIn = signedIn
    }

    /// Lowercased host without www. or a trailing dot; nil when it does not
    /// look like a host name or address. Never a path, port or credential.
    public static func key(_ host: String) -> String? {
        var key = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while key.hasSuffix(".") { key.removeLast() }
        if key.hasPrefix("www.") { key.removeFirst(4) }
        if key.hasPrefix("["), key.hasSuffix("]") { key = String(key.dropFirst().dropLast()) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.:")
        guard !key.isEmpty, key.utf8.count <= 253, !key.hasPrefix("."),
              key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return key
    }

    /// WebKit names a website-data record after the registrable domain, so
    /// removing the record named [recordName] also signs this site out.
    public func isCovered(byRecordNamed recordName: String) -> Bool {
        guard let name = Self.key(recordName) else { return false }
        return host == name || host.hasSuffix("." + name)
    }
}

/// The signs a page shows of the person's sign-in, read only from its top
/// account area (header, navigation, banner, or the top of the page).
public struct BrowserSignInSignals: Decodable, Equatable, Sendable {
    public let url: String?
    public let passwordVisible: Bool
    public let account: [String]
    public let avatars: Int

    public init(url: String?, passwordVisible: Bool, account: [String], avatars: Int) {
        self.url = url; self.passwordVisible = passwordVisible; self.account = account; self.avatars = avatars
    }

    private enum CodingKeys: String, CodingKey { case url, passwordVisible = "pw", account, avatars }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        passwordVisible = try values.decodeIfPresent(Bool.self, forKey: .passwordVisible) ?? false
        account = Array((try values.decodeIfPresent([String].self, forKey: .account) ?? []).prefix(60))
        avatars = try values.decodeIfPresent(Int.self, forKey: .avatars) ?? 0
    }
}

/// Play's LoginProbe, with Traditional Chinese words added. A general guess
/// that knows no particular site:
/// - signed in: the account area shows a sign-out link (the whole text, or
///   starting with it) or an account entry, and no sign-in entry;
/// - signed out: a visible password field, or a sign-in entry with no account
///   entry or avatar;
/// - an address that looks like a sign-in or single sign-on page decides
///   nothing; everything else is unknown.
public enum BrowserSignInProbe {
    /// Read-only page script: reads the DOM, changes nothing and sends nothing.
    /// It walks at most 4000 elements and returns the signals as JSON text.
    public static let script = #"""
    (function(){try{
    var out={url:location.href,pw:false,account:[],avatars:0},budget=4000;
    function vis(e){var r=e.getBoundingClientRect();if(r.width<2||r.height<2)return null;var c=getComputedStyle(e);return c.display!=='none'&&c.visibility!=='hidden'&&+c.opacity>0.05?r:null;}
    function top(e,r){return r.top+scrollY<160||!!e.closest('header,nav,[role=banner],[role=navigation]');}
    var w=document.createTreeWalker(document.body||document.documentElement,NodeFilter.SHOW_ELEMENT),e,n=0;
    while((e=w.nextNode())&&n++<budget){var t=e.tagName,r;
    if(t==='INPUT'){var y=(e.getAttribute('type')||'').toLowerCase();if(y==='password'&&!out.pw&&vis(e))out.pw=true;if(y!=='submit'&&y!=='button')continue;}
    if(t==='A'||t==='BUTTON'||t==='INPUT'||e.getAttribute('role')==='button'||e.getAttribute('role')==='link'||e.getAttribute('role')==='menuitem'){
    if(out.account.length>=60)continue;var s=String(e.innerText||e.value||e.getAttribute('aria-label')||e.getAttribute('title')||'').replace(/\s+/g,' ').trim();
    if(s&&s.length<=24&&(r=vis(e))&&top(e,r))out.account.push(s);continue;}
    if(t==='IMG'&&out.avatars<3){var k=(e.className&&typeof e.className==='string'?e.className:'')+' '+(e.getAttribute('alt')||'')+' '+(e.getAttribute('src')||'');
    if(/avatar|头像|頭像/i.test(k)&&(r=vis(e))&&top(e,r)&&!e.closest('article,li,[class*=comment],[class*=list],[class*=feed]'))out.avatars++;}}
    return JSON.stringify({url:out.url,pw:out.pw,account:out.account,avatars:out.avatars});}catch(x){return null;}})()
    """#

    /// Whole text only: too common to accept as a prefix (退出全屏, 登出時間…).
    static let signOutExact: Set<String> = ["退出", "注销", "註銷", "登出", "logout", "signout"]
    /// The whole text, or the start of it followed by at most four characters.
    static let signOut = ["退出登录", "退出账号", "安全退出", "注销登录", "登出帳號", "登出帳戶", "安全登出", "會員登出",
                          "登出", "log out", "sign out", "log off"]
    /// Texts with these are not sign-out links (help pages, account deletion).
    static let notSignOut = ["说明", "帮助", "须知", "协议", "账号注销", "注销账号", "注销账户",
                             "說明", "幫助", "須知", "協議", "帳號註銷", "註銷帳號", "刪除帳號",
                             "help", "how to", "delete account"]
    static let signIn: Set<String> = ["登录", "登入", "请登录", "立即登录", "登录/注册", "注册/登录", "登录 / 注册", "注册 / 登录",
                                      "請登入", "立即登入", "會員登入", "登入/註冊", "註冊/登入", "登入 / 註冊", "註冊 / 登入",
                                      "log in", "login", "sign in", "signin", "sign in / register", "sign up / log in"]
    static let accountEntry = ["个人中心", "我的账号", "我的账户", "账号设置", "账户设置",
                               "會員中心", "個人中心", "我的帳號", "我的帳戶", "帳號設定", "帳戶設定",
                               "my account", "your account", "account settings"]
    private static let signOutSlack = 4

    public static func parse(_ json: String) -> BrowserSignInSignals? {
        guard json.utf8.count <= 64_000 else { return nil }
        return try? JSONDecoder().decode(BrowserSignInSignals.self, from: Data(json.utf8))
    }

    public static func classify(_ signals: BrowserSignInSignals) -> BrowserSignInState {
        let texts = signals.account.map(normalized)
        let signedOutLink = texts.contains(where: isSignOut)
        let account = texts.contains { text in accountEntry.contains { text == $0 || text.hasPrefix($0) } }
        let signInEntry = texts.contains { signIn.contains($0) }
        // Sign-in, single sign-on and authorization pages are mostly on the way
        // somewhere: decide nothing there.
        if isSignInAddress(signals.url) { return .unknown }
        if signals.passwordVisible && !signedOutLink { return .signedOut }
        if (signedOutLink || account) && !signInEntry && !signals.passwordVisible { return .signedIn }
        if signInEntry && !signedOutLink && !account && signals.avatars == 0 { return .signedOut }
        return .unknown
    }

    /// A path segment that is a sign-in word, alone, after `name-`/`name_`, or
    /// with a file extension (login, user-login, login.php). Query text does not count.
    public static func isSignInAddress(_ raw: String?) -> Bool {
        guard let raw, let path = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.path else { return false }
        let words: Set<String> = ["login", "log-in", "signin", "sign-in", "sign_in", "logon", "passport", "sso",
                                  "oauth", "oauth2", "authorize"]
        for segment in path.lowercased().split(separator: "/") {
            var name = String(segment)
            if let dot = name.firstIndex(of: ".") { name = String(name[..<dot]) }
            if words.contains(name) || words.contains(where: { name.hasSuffix("-" + $0) || name.hasSuffix("_" + $0) }) {
                return true
            }
        }
        return false
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func isSignOut(_ text: String) -> Bool {
        guard !notSignOut.contains(where: { text.contains($0) }) else { return false }
        if signOutExact.contains(text) { return true }
        return signOut.contains { word in
            text == word || (text.hasPrefix(word) && text.count <= word.count + signOutSlack)
        }
    }
}
