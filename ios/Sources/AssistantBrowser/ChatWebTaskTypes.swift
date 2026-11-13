import AssistantModels
import Foundation

public enum ChatWebScrollDirection: String, Equatable, Sendable { case down, up }

public enum ChatWebWaitCondition: String, Equatable, Sendable {
    case textPresent = "text_present", textAbsent = "text_absent", urlContains = "url_contains"
}

public enum ChatWebCommandError: Error, Equatable, Sendable { case invalidCommand }

/// One step a model asks for in a web task started from chat. A structured
/// text protocol, one JSON object per reply; names follow the Play build's web
/// tools so prompts stay comparable. Read-only in this phase: no clicking,
/// typing, scripts, downloads or uploads.
public enum ChatWebCommand: Equatable, Sendable {
    case navigate(url: String)
    case readPage(url: String?, offset: Int, maxChars: Int)
    case openLink(id: Int)
    case find(text: String)
    case scroll(ChatWebScrollDirection)
    case back
    case waitFor(ChatWebWaitCondition, value: String, seconds: Int)
    case endNotDone(reason: String)
    case finish(answer: String, sources: [Int])

    public static let defaultReadCharacters = 12_000
    public static let maximumReadCharacters = 30_000
    public static let maximumAnswerCharacters = 24_000
    public static let maximumWaitSeconds = 15
    /// The two commands that start a web task from an ordinary chat reply.
    public static let entryActions: Set<String> = ["web_navigate", "web_read_page"]

    public var action: String {
        switch self {
        case .navigate: return "web_navigate"
        case .readPage: return "web_read_page"
        case .openLink: return "web_open_link"
        case .find: return "web_find"
        case .scroll: return "web_scroll"
        case .back: return "web_back"
        case .waitFor: return "web_wait_for"
        case .endNotDone: return "end_not_done"
        case .finish: return "finish"
        }
    }

    /// A reply that may start a web task: web_navigate, or web_read_page with a URL.
    public static func parseEntry(_ text: String) throws -> ChatWebCommand {
        let command = try parse(text)
        switch command {
        case .navigate: return command
        case .readPage(let url, _, _) where url != nil: return command
        default: throw ChatWebCommandError.invalidCommand
        }
    }

    /// Exactly one JSON object with exactly the keys of one command. Duplicate
    /// keys are refused. A single surrounding Markdown code fence is tolerated.
    public static func parse(_ reply: String) throws -> ChatWebCommand {
        let body = unfenced(reply)
        guard body.utf8.count <= 64 * 1024, let fields = try? RawCommandEnvelope.fields(in: body),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)) else {
            throw ChatWebCommandError.invalidCommand
        }
        let keys = Set(fields.keys)
        func only(_ allowed: Set<String>, requiring required: Set<String> = []) throws {
            guard keys.isSubset(of: allowed.union(["action"])), required.isSubset(of: keys) else {
                throw ChatWebCommandError.invalidCommand
            }
        }
        func checked(_ value: String?, max: Int) throws -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf16.count <= max else { throw ChatWebCommandError.invalidCommand }
            return value
        }
        switch envelope.action {
        case "web_navigate":
            try only(["url"], requiring: ["url"])
            return .navigate(url: try checked(envelope.url, max: ChatWebTaskPolicy.maximumURLBytes))
        case "web_read_page":
            try only(["url", "offset", "maxChars"])
            let url = try envelope.url.map { try checked($0, max: ChatWebTaskPolicy.maximumURLBytes) }
            let offset = envelope.offset ?? 0
            let maxChars = envelope.maxChars ?? defaultReadCharacters
            guard (0...10_000_000).contains(offset), (1_000...maximumReadCharacters).contains(maxChars) else {
                throw ChatWebCommandError.invalidCommand
            }
            return .readPage(url: url, offset: offset, maxChars: maxChars)
        case "web_open_link":
            try only(["linkID"], requiring: ["linkID"])
            guard let id = envelope.linkID, (1...ChatWebPageReading.maximumLinks).contains(id) else {
                throw ChatWebCommandError.invalidCommand
            }
            return .openLink(id: id)
        case "web_find":
            try only(["text"], requiring: ["text"])
            return .find(text: try checked(envelope.text, max: 120))
        case "web_scroll":
            try only(["direction"])
            guard let direction = ChatWebScrollDirection(rawValue: envelope.direction ?? "down") else {
                throw ChatWebCommandError.invalidCommand
            }
            return .scroll(direction)
        case "web_back":
            try only([])
            return .back
        case "web_wait_for":
            try only(["condition", "value", "seconds"], requiring: ["condition", "value"])
            guard let condition = ChatWebWaitCondition(rawValue: envelope.condition ?? ""),
                  (1...maximumWaitSeconds).contains(envelope.seconds ?? 10) else { throw ChatWebCommandError.invalidCommand }
            return .waitFor(condition, value: try checked(envelope.value, max: 200), seconds: envelope.seconds ?? 10)
        case "end_not_done":
            try only(["reason"], requiring: ["reason"])
            return .endNotDone(reason: try checked(envelope.reason, max: 2_000))
        case "finish":
            try only(["answer", "sources"], requiring: ["answer"])
            let sources = envelope.sources ?? []
            guard sources.count <= 20, sources.allSatisfy({ $0 > 0 }) else { throw ChatWebCommandError.invalidCommand }
            return .finish(answer: try checked(envelope.answer, max: maximumAnswerCharacters), sources: sources)
        default:
            throw ChatWebCommandError.invalidCommand
        }
    }

    /// Removes one surrounding ``` or ```json fence and outer whitespace.
    public static func unfenced(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count >= 6 else { return trimmed }
        var inner = trimmed.dropFirst(3).dropLast(3)
        if let newline = inner.firstIndex(of: "\n") {
            let label = inner[..<newline].trimmingCharacters(in: .whitespaces)
            if label.isEmpty || label.lowercased() == "json" { inner = inner[inner.index(after: newline)...] }
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Envelope: Decodable {
        let action: String
        let url: String?
        let offset: Int?
        let maxChars: Int?
        let linkID: Int?
        let text: String?
        let direction: String?
        let condition: String?
        let value: String?
        let seconds: Int?
        let reason: String?
        let answer: String?
        let sources: [Int]?
    }
}

/// What the task tab reports after a page has loaded.
public struct ChatWebLoad: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let httpStatus: Int?
    /// False when the page was still loading when the wait ran out.
    public let settled: Bool
    public init(url: URL, title: String, httpStatus: Int?, settled: Bool) {
        self.url = url; self.title = String(title.prefix(200)); self.httpStatus = httpStatus; self.settled = settled
    }
}

public struct ChatWebCapturedLink: Equatable, Sendable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

/// The rendered text of the whole page (not only what is on screen), its
/// links, and signs of a sign-in or a CAPTCHA. Field values are never read.
public struct ChatWebPageCapture: Equatable, Sendable {
    public static let maximumCharacters = 300_000
    public let url: URL
    public let title: String
    public let text: String
    public let truncated: Bool
    public let links: [ChatWebCapturedLink]
    public let hasPasswordField: Bool
    public let hasCaptcha: Bool
    public let omittedRegions: Int
    public init(url: URL, title: String, text: String, truncated: Bool = false, links: [ChatWebCapturedLink],
                hasPasswordField: Bool = false, hasCaptcha: Bool = false, omittedRegions: Int = 0) {
        self.url = url; self.title = String(title.prefix(200))
        let bounded = text.count > Self.maximumCharacters
        self.text = bounded ? String(text.prefix(Self.maximumCharacters)) : text
        self.truncated = truncated || bounded
        self.links = links; self.hasPasswordField = hasPasswordField; self.hasCaptcha = hasCaptcha
        self.omittedRegions = omittedRegions
    }
}

/// A step the task tab could not complete. These go back to the model as a
/// result, like a failed tool call on Android; only cancellation ends a task.
public enum ChatWebExecutionError: Error, Equatable, Sendable {
    case blocked(ChatWebTaskPolicy.Reason)
    case signInRequired
    case navigationFailed(String)
    case navigationTimedOut
    case pageUnavailable
    case readTimedOut
    /// The web content process ended or the app left the foreground; the
    /// read-only step can be done again.
    case interrupted

    public var code: String {
        switch self {
        case .blocked(let reason): return "blocked_url:" + reason.rawValue
        case .signInRequired: return "needs_sign_in"
        case .navigationFailed(let detail): return "navigation_failed:" + detail
        case .navigationTimedOut: return "navigation_timeout"
        case .pageUnavailable: return "page_unavailable"
        case .readTimedOut: return "read_timeout"
        case .interrupted: return "interrupted"
        }
    }
}

/// The task tab. It applies ChatWebTaskPolicy again to every main-frame
/// navigation, including redirects, so a model URL cannot bypass it.
@MainActor public protocol ChatWebTaskExecuting: AnyObject {
    var currentURL: URL? { get }
    func load(_ url: URL) async throws -> ChatWebLoad
    func capture() async throws -> ChatWebPageCapture
    /// True when the page moved.
    func scroll(_ direction: ChatWebScrollDirection) async throws -> Bool
    /// Nil when there is no earlier page.
    func goBack() async throws -> ChatWebLoad?
    /// True when the condition was met within the time.
    func waitFor(_ condition: ChatWebWaitCondition, value: String, seconds: Int) async throws -> Bool
}

/// One line in the task card and in 「檢視過程」. No page text is kept.
public struct ChatWebStep: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case open, read, find, scroll, back, wait }
    public let id: Int
    public let kind: Kind
    public let site: String
    public let title: String
    public let url: URL?
    public let succeeded: Bool
    public init(id: Int, kind: Kind, site: String, title: String, url: URL?, succeeded: Bool) {
        self.id = id; self.kind = kind; self.site = site; self.title = String(title.prefix(120))
        self.url = url; self.succeeded = succeeded
    }
}

/// A page the task actually read; `id` is the n of "page-n" given to the model.
public struct ChatWebSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    /// ChatWebTaskPolicy.displayURL of the page.
    public let url: URL
    public let site: String
    public init(id: Int, title: String, url: URL, site: String) {
        self.id = id; self.title = String(title.prefix(120)); self.url = url; self.site = site
    }
}

/// What the task is doing now, for the card's one-line status.
public enum ChatWebActivity: Equatable, Sendable {
    case thinking
    case opening(site: String)
    case reading(site: String)
    case finding(site: String)
    case scrolling(site: String)
    case goingBack
    case waiting(site: String)
    /// Like a person who finishes a page before turning it (Android PagePacing).
    case pacing(site: String)
}

/// Used on the main actor; `error` is the immutable model error of a failed task.
public struct ChatWebTaskResult: @unchecked Sendable {
    public enum Status: String, Equatable, Sendable { case succeeded, notDone, stopped, failed }
    /// Why the host ended a task the model did not finish.
    public enum Stop: String, Equatable, Sendable {
        case repeating, tooManyFailures, invalidCommands, modelFailed
    }
    public let status: Status
    public let answer: String?
    /// The model's own end_not_done reason.
    public let reason: String?
    public let stop: Stop?
    /// The model error behind a failed task, for its fixed explanation.
    public let error: Error?
    /// Up to six pages the answer used, chosen from pages actually read.
    public let sources: [ChatWebSource]
    public let pagesRead: [ChatWebSource]
    public let steps: [ChatWebStep]
    public let modelCalls: Int
}

/// Pages the model can read in one go and the links it can open by number.
public enum ChatWebPageReading {
    public static let maximumLinks = 50
}
