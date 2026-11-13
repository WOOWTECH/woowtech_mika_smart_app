import Foundation

// The Play build's skill catalog for ordinary chat (core/knowledge/GuideCatalog.kt,
// core/agent/GuideRecommender.kt @964d7bec): the bundled skills plus the user's
// personal skills that are in use (trial or active). A personal skill with a
// bundled name replaces it. Read-only reference text: nothing here grants a tool,
// runs a script or authorizes an action.

public struct ChatSkillItem: Equatable, Sendable {
    public static let bundledKind = "skill"
    public static let personalKind = "personal"
    public static let mainFile = "SKILL.md"
    public let kind: String
    public let name: String
    public let display: String
    public let description: String
    public let aliases: [String]
    public let terms: [String]
    /// Readable files: the main SKILL.md first, then the attachments.
    public let files: [String]
}

public enum ChatSkillView: Equatable, Sendable {
    /// version is set only for the main file of a personal skill; skill_save
    /// needs it to change that skill.
    case found(item: ChatSkillItem, file: String, content: String, truncated: Bool, version: String?)
    case failed(error: String, message: String)
}

public struct ChatSkillCatalog: Sendable {
    public static let viewLimit = 12_000
    public static let findLimit = 10
    public static let indexHeader = "All skills you have, one line each (when one fits this task, read its full text with skill_read before acting on it):"
    /// Play's UNAVAILABLE_TOOLS_NOTE; the device has no sandbox, so no script runs.
    public static let unavailableToolsNote = "(Note: scripts mentioned in the text and tools this device does not have are not available; use only the tools in your tool list.)"

    private struct Bundled: Sendable {
        let item: ChatSkillItem
        let body: String
        let attachments: [String: String]
    }
    private struct Personal: Sendable {
        let item: ChatSkillItem
        let body: String?
        let version: String
    }
    private let bundled: [Bundled]
    private let personal: [Personal]

    public init(bundled catalog: BundledSkillCatalog?, skills: SkillsState) {
        bundled = (catalog?.entries ?? []).map(Self.bundledSkill)
        personal = skills.installed.filter(\.isEnabled).map(Self.personalSkill)
    }

    /// Bundled names cannot be used by an imported or saved personal skill.
    public var builtinNames: Set<String> { Set(bundled.map(\.item.name)) }

    /// Personal skills are read fresh by the caller for every catalog: accepting
    /// or turning one off happens at any time.
    public var items: [ChatSkillItem] {
        let mine = personal.map(\.item)
        let names = Set(mine.map(\.name))
        return mine + bundled.map(\.item).filter { !names.contains($0.name) }
    }

    /// Scoring like Play: name, display or alias equal > contains (or wholly in
    /// the query) > search term > description; each whitespace-separated word
    /// scores separately and at least one must match.
    public func find(_ query: String, limit: Int = findLimit) -> [ChatSkillItem] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let scored = items.enumerated().compactMap { offset, item -> (Int, Int, ChatSkillItem)? in
            let score = Self.score(item, tokens: tokens)
            return score > 0 ? (score, offset, item) : nil
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.prefix(limit).map(\.2)
    }

    /// The index written once at the start of a chat request: every skill, one
    /// line each, bundled first, then personal, each sorted by name.
    public func index() -> String? {
        let all = items.sorted { lhs, rhs in
            let lb = lhs.kind != ChatSkillItem.bundledKind, rb = rhs.kind != ChatSkillItem.bundledKind
            return lb != rb ? !lb : lhs.name < rhs.name
        }
        guard !all.isEmpty else { return nil }
        return ([Self.indexHeader] + all.map { "- \($0.kind):\($0.name)(\($0.display)):\($0.description)" })
            .joined(separator: "\n")
    }

    /// name may be skill:<name>, personal:<name> or a bare name.
    public func view(_ name: String, file: String? = nil) -> ChatSkillView {
        let requested = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = requested.split(separator: ":", maxSplits: 1).first.map(String.init)
        let kind = requested.contains(":") && [ChatSkillItem.bundledKind, ChatSkillItem.personalKind].contains(prefix ?? "")
            ? prefix : nil
        let id = kind == nil ? requested : String(requested.dropFirst((kind ?? "").count + 1))
        guard let item = items.first(where: { $0.name == id && (kind == nil || $0.kind == kind) }) else {
            return .failed(error: "skill_not_found", message: "No skill named '\(requested)'. Use skill_search to find it.")
        }
        let main = item.files[0]
        var path = file?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.isEmpty { path = main }
        if path.hasPrefix("./") { path.removeFirst(2) }
        if item.kind == ChatSkillItem.personalKind {
            guard path == ChatSkillItem.mainFile else {
                return .failed(error: "file_not_found", message: "Personal skill \(item.name) has only \(ChatSkillItem.mainFile).")
            }
            guard let entry = personal.first(where: { $0.item.name == item.name }), let body = entry.body else {
                return .failed(error: "personal_skill_invalid", message: "The user's personal skill '\(item.name)' is damaged and cannot be read; do not rely on it. The user can fix or delete it in 記憶與資料 › 技能 (Memory & Data › Skills).")
            }
            let cut = body.count > Self.viewLimit
            return .found(item: item, file: ChatSkillItem.mainFile,
                          content: cut ? String(body.prefix(Self.viewLimit)) + "\n…(truncated)" : body,
                          truncated: cut, version: entry.version)
        }
        guard item.files.contains(path) else {
            return .failed(error: "file_not_found",
                           message: "No file '\(path)' in \(item.kind):\(item.name). Available: \(item.files.joined(separator: ", ")).")
        }
        guard let entry = bundled.first(where: { $0.item.name == item.name }),
              let text = path == main ? entry.body : entry.attachments[path] else {
            return .failed(error: "file_not_found", message: "File '\(path)' could not be read.")
        }
        let cut = text.count > Self.viewLimit
        let shown = cut ? String(text.prefix(Self.viewLimit)) + "\n…(truncated; use file_path to view the other files)" : text
        return .found(item: item, file: path, content: Self.unavailableToolsNote + "\n" + shown, truncated: cut, version: nil)
    }

    private static func score(_ item: ChatSkillItem, tokens: [String]) -> Int {
        let names = ([item.name, item.display] + item.aliases).map { $0.lowercased() }
        let terms = item.terms.map { $0.lowercased() }
        let description = item.description.lowercased()
        return tokens.reduce(0) { total, token in
            let points: Int
            if names.contains(token) { points = 100 }
            // A Chinese goal is usually one word: a name inside the sentence counts too.
            else if names.contains(where: { $0.contains(token) || ($0.count >= 2 && token.contains($0)) }) { points = 60 }
            else if terms.contains(token) { points = 50 }
            else if terms.contains(where: { $0.contains(token) }) { points = 40 }
            else if description.contains(token) { points = 20 }
            else { points = 0 }
            return total + points
        }
    }

    private static func bundledSkill(_ entry: SkillCatalogEntry) -> Bundled {
        let (meta, body) = ChatSkillFrontMatter.parse(entry.original.content)
        let name = meta.string("name") ?? entry.id
        let prefix = "core/src/main/resources/skills/" + entry.id + "/"
        var attachments: [String: String] = [:]
        var files = [ChatSkillItem.mainFile]
        for asset in entry.assets where asset.path.hasPrefix(prefix) {
            let relative = String(asset.path.dropFirst(prefix.count))
            files.append(relative)
            attachments[relative] = ChatSkillFrontMatter.parse(asset.content).body
        }
        let item = ChatSkillItem(kind: ChatSkillItem.bundledKind, name: name,
                                 display: meta.string("display").flatMap { $0.isEmpty ? nil : $0 } ?? name,
                                 description: meta.string("description") ?? "",
                                 aliases: meta.list("aliases"), terms: meta.list("terms"), files: files)
        return Bundled(item: item, body: body, attachments: attachments)
    }

    private static func personalSkill(_ skill: PersonalSkill) -> Personal {
        let fields = skill.document.frontMatter
        func one(_ key: String) -> String? { fields[key]?.stringValue }
        func many(_ key: String) -> [String] { (fields[key]?.strings ?? []).filter { !$0.isEmpty } }
        let trial = skill.status == .trial
        let item = ChatSkillItem(kind: ChatSkillItem.personalKind, name: skill.name,
                                 display: one("display").flatMap { $0.isEmpty ? nil : $0 } ?? skill.name,
                                 description: (trial ? "[unverified: check the result when trying it] " : "") + (one("description") ?? ""),
                                 aliases: many("aliases"), terms: many("apps") + many("domains"),
                                 files: [ChatSkillItem.mainFile])
        let body = ChatSkillFrontMatter.parse(skill.markdown).body
        let valid = one("name") == skill.name && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = trial ? "[Unverified personal skill draft: use it only as a trial; the result must be checked.]\n" + body : body
        return Personal(item: item, body: valid ? shown : nil, version: skill.version)
    }
}

/// Play's FrontMatter.parse (core/knowledge/FrontMatter.kt): scalars and inline
/// lists, quotes removed; the body is the text after the closing line, trimmed.
/// Text without front matter is returned unchanged.
public enum ChatSkillFrontMatter {
    public struct Fields: Equatable, Sendable {
        public let values: [String: [String]]
        public let scalars: Set<String>
        public func string(_ key: String) -> String? { scalars.contains(key) ? values[key]?.first : nil }
        public func list(_ key: String) -> [String] { values[key] ?? [] }
    }

    public static func parse(_ markdown: String) -> (fields: Fields, body: String) {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let empty = Fields(values: [:], scalars: [])
        guard text.hasPrefix("---\n") else { return (empty, text) }
        let lines = text.components(separatedBy: "\n")
        // Play compares the line with trailing whitespace removed.
        guard let end = lines.indices.dropFirst().first(where: {
            lines[$0].hasPrefix("---") && lines[$0].dropFirst(3).allSatisfy(\.isWhitespace)
        }) else { return (empty, text) }
        var values: [String: [String]] = [:], scalars: Set<String> = []
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":"), colon > line.startIndex else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("[") && raw.hasSuffix("]") && raw.count >= 2 {
                values[key] = split(String(raw.dropFirst().dropLast())).map(unquote).filter { !$0.isEmpty }
                scalars.remove(key)
            } else {
                values[key] = [unquote(raw)]
                scalars.insert(key)
            }
        }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (Fields(values: values, scalars: scalars), body)
    }

    // Commas inside quotes do not separate items.
    private static func split(_ text: String) -> [String] {
        var out: [String] = [], current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character; current.append(character)
            } else if character == "," {
                out.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        out.append(current)
        return out
    }

    private static func unquote(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// skill_save could not replace an existing personal skill: the request did
/// not carry the version skill_read returned for it.
public enum SkillChatSaveError: String, Error, Equatable, Sendable {
    case exists
}

public struct SkillChatSaveReceipt: Equatable, Sendable {
    public let name: String
    /// created or updated, as Play's skill_save reports.
    public let action: String
    public let status: SkillStatus
    public let version: String
}
