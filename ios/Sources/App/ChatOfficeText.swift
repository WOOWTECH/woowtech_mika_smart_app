import Compression
import Foundation
import UniformTypeIdentifiers

/// The words of a Word, PowerPoint or Excel file (Office Open XML: a zip of XML
/// parts), read on the device for a chat attachment. Only the text is read, never
/// pictures, macros or embedded objects, and every size is bounded, so a zip that
/// expands without end stops at the limits.
enum ChatOfficeText {
    enum Kind: Equatable { case word, slides, sheet }

    /// The largest Office file read, the largest part expanded, and the most parts listed.
    static let maxFileBytes = 50 << 20
    static let maxPartBytes = 32 << 20
    static let maxEntries = 20_000

    static func kind(of url: URL, types: [UTType]) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "docx", "docm", "dotx", "dotm": return .word
        case "pptx", "pptm", "potx", "ppsx": return .slides
        case "xlsx", "xlsm", "xltx": return .sheet
        default: break
        }
        let identifiers = types.map(\.identifier)
        if identifiers.contains(where: { $0.hasPrefix("org.openxmlformats.wordprocessingml") }) { return .word }
        if identifiers.contains(where: { $0.hasPrefix("org.openxmlformats.presentationml") }) { return .slides }
        if identifiers.contains(where: { $0.hasPrefix("org.openxmlformats.spreadsheetml") }) { return .sheet }
        return nil
    }

    /// The document's text within `limit` UTF-8 bytes; nil when it is not a
    /// readable Office file (encrypted, damaged or another zip).
    static func read(_ url: URL, kind: Kind, limit: Int) -> (text: String, truncated: Bool)? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe), let zip = Zip(data) else { return nil }
        let output = Output(limit: limit)
        switch kind {
        case .word:
            guard let part = zip.part("word/document.xml") else { return nil }
            WordText(output: output).parse(part)
        case .slides:
            let slides = zip.names.compactMap { name -> (Int, String)? in
                guard name.hasPrefix("ppt/slides/slide"), name.hasSuffix(".xml"),
                      let number = Int(name.dropFirst("ppt/slides/slide".count).dropLast(".xml".count)) else { return nil }
                return (number, name)
            }.sorted { $0.0 < $1.0 }
            guard !slides.isEmpty else { return nil }
            for (number, name) in slides where !output.full {
                guard let part = zip.part(name) else { continue }
                output.append("--- Slide \(number) ---\n")
                RunText(element: "a:t", paragraph: "a:p", output: output).parse(part)
            }
        case .sheet:
            let shared = zip.part("xl/sharedStrings.xml").map(SharedStrings.parse) ?? []
            let names = zip.part("xl/workbook.xml").map(SheetNames.parse) ?? []
            let sheets = zip.names.compactMap { name -> (Int, String)? in
                guard name.hasPrefix("xl/worksheets/sheet"), name.hasSuffix(".xml"),
                      let number = Int(name.dropFirst("xl/worksheets/sheet".count).dropLast(".xml".count)) else { return nil }
                return (number, name)
            }.sorted { $0.0 < $1.0 }
            guard !sheets.isEmpty else { return nil }
            for (index, sheet) in sheets.enumerated() where !output.full {
                guard let part = zip.part(sheet.1) else { continue }
                output.append("--- Sheet: " + (index < names.count ? names[index] : "\(sheet.0)") + " ---\n")
                SheetText(shared: shared, output: output).parse(part)
            }
        }
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, output.full)
    }

    /// Text gathered up to a byte limit; once full, parsing stops. Shared by the parsers.
    final class Output {
        let limit: Int
        private(set) var text = ""
        private(set) var full = false
        init(limit: Int) { self.limit = max(0, limit) }
        func append(_ piece: String) {
            guard !full else { return }
            let room = limit - text.utf8.count
            if piece.utf8.count <= room { text += piece; return }
            var cut = piece.startIndex
            var used = 0
            for character in piece {
                let size = String(character).utf8.count
                guard used + size <= room else { break }
                used += size
                cut = piece.index(after: cut)
            }
            text += piece[..<cut]
            full = true
        }
    }

    // MARK: Zip

    /// The central directory of a zip, and its parts stored or deflated (no zip64,
    /// no encryption: an encrypted Office file is not a zip at all).
    struct Zip {
        private let data: Data
        private var entries: [String: (method: UInt16, compressed: Int, expanded: Int, offset: Int)] = [:]
        var names: [String] { Array(entries.keys) }

        init?(_ data: Data) {
            self.data = data
            let count = data.count
            guard count >= 22 else { return nil }
            // The end record: 22 bytes, then a comment of at most 64 KB.
            var end = -1
            var position = count - 22
            while position >= max(0, count - 22 - 65_535) {
                if data.u32(position) == 0x0605_4b50 { end = position; break }
                position -= 1
            }
            guard end >= 0 else { return nil }
            let total = Int(data.u16(end + 10)), start = Int(data.u32(end + 16))
            guard total <= ChatOfficeText.maxEntries, start < count else { return nil }
            var cursor = start
            for _ in 0..<total {
                guard cursor + 46 <= count, data.u32(cursor) == 0x0201_4b50 else { return nil }
                let flags = data.u16(cursor + 8), method = data.u16(cursor + 10)
                let compressed = Int(data.u32(cursor + 20)), expanded = Int(data.u32(cursor + 24))
                let nameLength = Int(data.u16(cursor + 28)), extra = Int(data.u16(cursor + 30)), comment = Int(data.u16(cursor + 32))
                let offset = Int(data.u32(cursor + 42))
                guard cursor + 46 + nameLength <= count else { return nil }
                let name = String(decoding: data[data.startIndex + cursor + 46 ..< data.startIndex + cursor + 46 + nameLength], as: UTF8.self)
                // Bit 0: an encrypted part, which cannot be read.
                if flags & 1 == 0 { entries[name] = (method, compressed, expanded, offset) }
                cursor += 46 + nameLength + extra + comment
            }
        }

        func part(_ name: String) -> Data? {
            guard let entry = entries[name], entry.expanded <= ChatOfficeText.maxPartBytes,
                  entry.offset + 30 <= data.count, data.u32(entry.offset) == 0x0403_4b50 else { return nil }
            let begin = entry.offset + 30 + Int(data.u16(entry.offset + 26)) + Int(data.u16(entry.offset + 28))
            guard begin + entry.compressed <= data.count else { return nil }
            let source = data[data.startIndex + begin ..< data.startIndex + begin + entry.compressed]
            switch entry.method {
            case 0: return Data(source)
            case 8:
                guard entry.expanded > 0 else { return Data() }
                guard entry.compressed > 0 else { return nil }
                var output = Data(count: entry.expanded)
                let written = output.withUnsafeMutableBytes { target in
                    source.withUnsafeBytes { input in
                        compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, entry.expanded,
                                                  input.bindMemory(to: UInt8.self).baseAddress!, entry.compressed,
                                                  nil, COMPRESSION_ZLIB)
                    }
                }
                return written > 0 ? output.prefix(written) : nil
            default: return nil
            }
        }
    }

    // MARK: XML

    /// Word's main document: runs of text, tabs and breaks; a paragraph ends a
    /// line, and a table row's cells are joined with " | ".
    final class WordText: NSObject, XMLParserDelegate {
        private let output: Output
        private var inText = false, cellDepth = 0
        init(output: Output) { self.output = output }
        func parse(_ data: Data) { let parser = XMLParser(data: data); parser.delegate = self; parser.parse() }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            switch name {
            case "w:t": inText = true
            case "w:tab": output.append("\t")
            case "w:br", "w:cr": output.append("\n")
            case "w:tc": cellDepth += 1
            default: break
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:t": inText = false
            case "w:p": output.append(cellDepth > 0 ? " " : "\n")
            case "w:tc": cellDepth -= 1; output.append("| ")
            case "w:tr": output.append("\n")
            default: break
            }
            if output.full { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { output.append(string) }
        }
    }

    /// Slides and other DrawingML text: runs inside `element`, a line per `paragraph`.
    final class RunText: NSObject, XMLParserDelegate {
        private let element: String, paragraph: String
        private let output: Output
        private var inText = false
        init(element: String, paragraph: String, output: Output) {
            self.element = element; self.paragraph = paragraph; self.output = output
        }
        func parse(_ data: Data) { let parser = XMLParser(data: data); parser.delegate = self; parser.parse() }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == element { inText = true }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == element { inText = false }
            if name == paragraph { output.append("\n") }
            if output.full { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { output.append(string) } }
    }

    /// Excel's shared strings, in order: each item's text runs joined.
    final class SharedStrings: NSObject, XMLParserDelegate {
        private var strings: [String] = [], current = "", inItem = false, inText = false
        static func parse(_ data: Data) -> [String] {
            let reader = SharedStrings(); let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
            return reader.strings
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "si" { inItem = true; current = "" }
            if name == "t", inItem { inText = true }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "t" { inText = false }
            if name == "si" { inItem = false; strings.append(current) }
            if strings.count >= 1_000_000 { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
    }

    /// The sheet names in the workbook's order.
    final class SheetNames: NSObject, XMLParserDelegate {
        private var names: [String] = []
        static func parse(_ data: Data) -> [String] {
            let reader = SheetNames(); let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
            return reader.names
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "sheet", let sheet = attributes["name"] { names.append(sheet) }
        }
    }

    /// A worksheet as lines of tab-separated cells, each in its own column.
    final class SheetText: NSObject, XMLParserDelegate {
        private let shared: [String]
        private let output: Output
        private var row: [Int: String] = [:], column = 0, type = "", value = "", inValue = false
        init(shared: [String], output: Output) { self.shared = shared; self.output = output }
        func parse(_ data: Data) { let parser = XMLParser(data: data); parser.delegate = self; parser.parse() }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            switch name {
            case "row": row = [:]
            case "c":
                type = attributes["t"] ?? ""; value = ""
                column = attributes["r"].map(Self.column) ?? (row.keys.max().map { $0 + 1 } ?? 0)
            case "v", "t": inValue = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": inValue = false
            case "c":
                let text = type == "s" ? (Int(value).flatMap { $0 < shared.count ? shared[$0] : nil } ?? "") : value
                if !text.isEmpty { row[column] = text }
            case "row":
                if let last = row.keys.max() {
                    output.append((0...last).map { row[$0] ?? "" }.joined(separator: "\t") + "\n")
                }
            default: break
            }
            if output.full { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { value += string } }
        /// "C7" → 2: the letters before the row number, A as 0.
        static func column(_ reference: String) -> Int {
            reference.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }
}
