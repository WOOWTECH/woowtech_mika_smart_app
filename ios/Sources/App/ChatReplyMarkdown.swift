import Foundation
import SwiftUI

/// Display-only formatting for assistant answers. The model's original bytes
/// remain in ChatEntry, the archive, and the streaming preview. This renderer
/// never loads a URL, evaluates HTML, creates an image, or runs code.
enum ChatReplyMarkdown {
    enum Fallback: Equatable {
        case tooLarge, rawHTML, image, extendedAttribute, unsafeLink, unclosedFence, invalidMarkdown
    }

    enum Mode: Equatable {
        case formatted
        case verbatim(Fallback)
    }

    struct Result {
        let text: AttributedString
        let mode: Mode
        var visibleText: String { String(text.characters) }
    }

    static let maximumUTF8Bytes = 64 * 1024
    static let maximumLines = 512
    static let maximumStreamingUTF8Bytes = 8 * 1024
    private static let maximumLineUTF8Bytes = 8 * 1024

    static func render(_ source: String, streaming: Bool = false) -> AttributedString {
        parse(source, streaming: streaming).text
    }

    static func parse(_ source: String, streaming: Bool = false) -> Result {
        func raw(_ reason: Fallback) -> Result {
            Result(text: AttributedString(source), mode: .verbatim(reason))
        }

        // The native Text has no image or HTML renderer. Showing the source
        // verbatim also preserves destinations that an inline parser might hide.
        let byteLimit = streaming ? maximumStreamingUTF8Bytes : maximumUTF8Bytes
        guard source.utf8.prefix(byteLimit + 1).count <= byteLimit else {
            return raw(.tooLarge)
        }
        guard !source.contains("<") || !source.contains(">") else { return raw(.rawHTML) }
        guard !source.contains("![") else { return raw(.image) }
        guard !source.contains("^[") else { return raw(.extendedAttribute) }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count <= maximumLines,
              lines.allSatisfy({ $0.utf8.count <= maximumLineUTF8Bytes }) else { return raw(.tooLarge) }

        var output: [AttributedString] = []
        var fence: Fence?
        var inTable = false
        do {
            for index in lines.indices {
                let line = lines[index]
                if let currentFence = fence {
                    if isClosingFence(line, for: currentFence) { fence = nil; continue }
                    output.append(code(line))
                    continue
                }
                if isFenceCandidate(line) {
                    guard let opening = openingFence(line) else { return raw(.invalidMarkdown) }
                    fence = opening
                    continue
                }
                if inTable {
                    if !line.isEmpty && line.contains("|") {
                        output.append(code(line))
                        continue
                    }
                    inTable = false
                }
                if lines.indices.contains(index + 1), isTableDivider(lines[index + 1], for: line) {
                    inTable = true
                    output.append(code(line))
                    continue
                }
                if line.hasPrefix("    ") {
                    // Indented code and unsupported list continuations stay
                    // literal; they must not gain an accidental Markdown link.
                    output.append(code(line))
                } else if isRule(line) {
                    var rule = AttributedString("────────────")
                    rule.foregroundColor = .secondary
                    output.append(rule)
                } else if let heading = heading(line) {
                    var title = try inline(heading.text)
                    title.font = .system(size: heading.level == 1 ? 20 : heading.level == 2 ? 18 : 16,
                                         weight: .semibold)
                    output.append(title)
                } else if let quotation = quote(line) {
                    var marker = AttributedString("│ ")
                    marker.foregroundColor = .secondary
                    output.append(marker + (try inline(quotation)))
                } else if let list = listItem(line) {
                    var marker = AttributedString(String(repeating: "  ", count: list.depth) + list.marker)
                    marker.foregroundColor = .secondary
                    output.append(marker + (try inline(list.text)))
                } else {
                    output.append(try inline(line))
                }
            }
        } catch ParseError.unsafeLink {
            return raw(.unsafeLink)
        } catch {
            return raw(.invalidMarkdown)
        }
        guard fence == nil else { return raw(.unclosedFence) }
        guard !output.isEmpty || source.isEmpty else { return raw(.invalidMarkdown) }
        var joined = AttributedString()
        for (index, part) in output.enumerated() {
            if index != 0 { joined += AttributedString("\n") }
            joined += part
        }
        return Result(text: joined, mode: .formatted)
    }

    private enum ParseError: Error { case unsafeLink }

    private static func inline(_ source: String) throws -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        let result = try AttributedString(markdown: source, options: options, baseURL: nil)
        for run in result.runs {
            if let destination = run.link, !allowedLink(destination) { throw ParseError.unsafeLink }
        }
        return result
    }

    private static func allowedLink(_ destination: URL) -> Bool {
        guard let scheme = destination.scheme?.lowercased() else { return false }
        switch scheme {
        case "https", "http":
            return destination.host?.isEmpty == false && destination.user == nil && destination.password == nil
        case "mailto", "tel":
            return destination.absoluteString.count > scheme.count + 1
        default:
            return false
        }
    }

    private struct Fence {
        let character: Character
        let length: Int
    }

    private static func isFenceCandidate(_ line: String) -> Bool {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return false }
        let rest = line.dropFirst(indentation)
        guard let marker = rest.first, marker == "`" || marker == "~" else { return false }
        return rest.prefix(while: { $0 == marker }).count >= 3
    }

    private static func openingFence(_ line: String) -> Fence? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let length = rest.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        if character == "`", rest.dropFirst(length).contains("`") { return nil }
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard info.count <= 40,
              info.allSatisfy({ $0.isLetter || $0.isNumber || "_+.-".contains($0) }) else { return nil }
        return Fence(character: character, length: length)
    }

    private static func isClosingFence(_ line: String, for fence: Fence) -> Bool {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return false }
        let rest = line.dropFirst(indentation)
        let length = rest.prefix(while: { $0 == fence.character }).count
        return length >= fence.length && rest.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        let level = rest.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), rest.dropFirst(level).first == " " else { return nil }
        return (level, String(rest.dropFirst(level + 1)))
    }

    private static func quote(_ line: String) -> String? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        guard rest.first == ">" else { return nil }
        var content = rest.dropFirst()
        if content.first == " " { content = content.dropFirst() }
        return String(content)
    }

    private static func listItem(_ line: String) -> (depth: Int, marker: String, text: String)? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 6 else { return nil }
        let rest = line.dropFirst(indentation)
        let depth = indentation / 2
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            return (depth, depth.isMultiple(of: 2) ? "• " : "◦ ", String(rest.dropFirst(2)))
        }
        let digits = rest.prefix(while: { $0.isNumber })
        guard (1...4).contains(digits.count),
              let delimiter = rest.dropFirst(digits.count).first, delimiter == "." || delimiter == ")",
              rest.dropFirst(digits.count + 1).first == " " else { return nil }
        return (depth, String(digits) + ". ", String(rest.dropFirst(digits.count + 2)))
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, "-*_".contains(marker) else { return false }
        let marks = trimmed.filter { !$0.isWhitespace }
        return marks.count >= 3 && marks.allSatisfy { $0 == marker }
    }

    private static func isTableDivider(_ divider: String, for header: String) -> Bool {
        guard header.contains("|"), divider.contains("|") else { return false }
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let headings = cells(header), rules = cells(divider)
        return headings.count == rules.count && !rules.isEmpty && rules.allSatisfy { cell in
            let center = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return center.count >= 3 && center.allSatisfy { $0 == "-" }
        }
    }

    private static func code(_ source: String) -> AttributedString {
        var text = AttributedString(source)
        text.font = .system(.body, design: .monospaced)
        return text
    }
}
