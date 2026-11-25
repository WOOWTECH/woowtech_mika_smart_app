import Foundation

public enum DocumentCreationFormat: String, CaseIterable, Equatable, Sendable {
    case pdf, docx, xlsx, pptx, zip
}

/// Stable failure cases. Each becomes a code and an instruction for the model
/// (DocumentCreationResult); content is never included.
public enum DocumentCreationError: Error, Equatable, Sendable {
    case invalidCommand, invalidFormat, invalidFileName, invalidTitle, invalidText
    case emptyContent, tooLarge, tooManySheets, tooManyRows, tooManyColumns, tooManyCells, cellTooLong
    case tooManySlides, tooManyBullets, slideTextTooLong
    case tooManyEntries, invalidEntryName, duplicateEntryName, unknownFile
    /// The Markdown of a PDF or Word file did not make a document (DocumentReport).
    case content(DocumentError)
}

/// Bounds for one file_create command and the file it makes.
public enum DocumentCreationLimits {
    /// One whole command, like the chat's other commands (ChatSkillCommand).
    public static let maximumCommandBytes = 256 * 1_024
    /// Every format, like the exported documents.
    public static let maximumOutputBytes = DocumentLimits.maximumOutputBytes
    public static let maximumFileNameCharacters = 120
    public static let maximumTitleCharacters = 200
    public static let maximumSheets = 16
    /// Per sheet, and columns per row, like an exported table.
    public static let maximumRows = DocumentLimits.maximumRows
    public static let maximumColumns = DocumentLimits.maximumColumns
    /// Across the workbook.
    public static let maximumCells = DocumentLimits.maximumCells
    /// Excel's own limit for one cell.
    public static let maximumCellCharacters = 32_767
    public static let maximumSlides = 50
    public static let maximumBullets = 12
    public static let maximumSlideTextCharacters = 500
    public static let maximumEntries = 32
    /// What one ZIP bundles before compression.
    public static let maximumArchiveInputBytes = 64 * 1_048_576
}

public enum DocumentZipSource: Equatable, Sendable {
    /// A UTF-8 text file written from the command.
    case text(String)
    /// A file made earlier in the conversation, by the name its result gave.
    case file(String)
}

public struct DocumentZipItem: Equatable, Sendable {
    public let name: String
    public let source: DocumentZipSource
}

/// One file_create command: its format, the file's name with the format's
/// extension, the title written into the file, and what goes in it.
public struct DocumentCreationCommand: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case markdown(String)
        case sheets([SpreadsheetSheet])
        case slides([PresentationSlide])
        case entries([DocumentZipItem])
    }
    public static let action = "file_create"
    public let format: DocumentCreationFormat
    public let fileName: String
    public let title: String
    public let content: Content

    /// Exactly one command, a single surrounding code fence tolerated. Unknown
    /// keys, missing ones and the wrong types are refused, never guessed.
    public static func parse(_ text: String) throws -> DocumentCreationCommand {
        let body = unfenced(text)
        guard body.utf8.count <= DocumentCreationLimits.maximumCommandBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              Set(object.keys) == ["action", "arguments"], object["action"] as? String == action,
              let arguments = object["arguments"] as? [String: Any] else { throw DocumentCreationError.invalidCommand }
        guard let raw = arguments["format"] as? String,
              let format = DocumentCreationFormat(rawValue: raw.lowercased()) else { throw DocumentCreationError.invalidFormat }
        let content: String
        switch format {
        case .pdf, .docx: content = "markdown"
        case .xlsx: content = "sheets"
        case .pptx: content = "slides"
        case .zip: content = "entries"
        }
        let keys = Set(arguments.keys)
        guard keys.isSuperset(of: ["format", "file_name", content]),
              keys.isSubset(of: ["format", "file_name", "title", content]) else { throw DocumentCreationError.invalidCommand }
        guard let requested = arguments["file_name"] as? String,
              requested.count <= DocumentCreationLimits.maximumFileNameCharacters,
              !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentCreationError.invalidFileName }
        let fileName = DocumentFileName.sanitized(requested, extension: format.rawValue)
        let title: String
        if let given = arguments["title"] {
            guard let text = given as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= DocumentCreationLimits.maximumTitleCharacters,
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw DocumentCreationError.invalidTitle
            }
            title = text.trimmingCharacters(in: .whitespaces)
        } else {
            title = (fileName as NSString).deletingPathExtension
        }
        let parsed: Content
        switch format {
        case .pdf, .docx:
            guard let markdown = arguments["markdown"] as? String else { throw DocumentCreationError.invalidCommand }
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentCreationError.emptyContent }
            parsed = .markdown(markdown)
        case .xlsx: parsed = .sheets(try sheets(arguments["sheets"]))
        case .pptx: parsed = .slides(try slides(arguments["slides"]))
        case .zip: parsed = .entries(try entries(arguments["entries"]))
        }
        return DocumentCreationCommand(format: format, fileName: fileName, title: title, content: parsed)
    }

    private static func sheets(_ value: Any?) throws -> [SpreadsheetSheet] {
        guard let list = value as? [Any] else { throw DocumentCreationError.invalidCommand }
        guard !list.isEmpty else { throw DocumentCreationError.emptyContent }
        guard list.count <= DocumentCreationLimits.maximumSheets else { throw DocumentCreationError.tooManySheets }
        var cells = 0
        return try list.enumerated().map { index, item in
            guard let sheet = item as? [String: Any], Set(sheet.keys).isSubset(of: ["name", "rows"]),
                  let rows = sheet["rows"] as? [Any] else { throw DocumentCreationError.invalidCommand }
            let name: String
            if let given = sheet["name"] {
                guard let text = given as? String, text.count <= 100 else { throw DocumentCreationError.invalidCommand }
                name = text
            } else { name = "Sheet\(index + 1)" }
            guard rows.count <= DocumentCreationLimits.maximumRows else { throw DocumentCreationError.tooManyRows }
            let parsed: [[SpreadsheetCell]] = try rows.map { row in
                guard let values = row as? [Any] else { throw DocumentCreationError.invalidCommand }
                guard values.count <= DocumentCreationLimits.maximumColumns else { throw DocumentCreationError.tooManyColumns }
                cells += values.count
                guard cells <= DocumentCreationLimits.maximumCells else { throw DocumentCreationError.tooManyCells }
                return try values.map(cell)
            }
            return SpreadsheetSheet(name: name, rows: parsed)
        }
    }

    /// A JSON number is a number, true and false booleans, null an empty cell.
    private static func cell(_ value: Any) throws -> SpreadsheetCell {
        if value is NSNull { return .empty }
        if let text = value as? String {
            guard text.count <= DocumentCreationLimits.maximumCellCharacters else { throw DocumentCreationError.cellTooLong }
            guard OfficePackage.isXMLText(text) else { throw DocumentCreationError.invalidText }
            return text.isEmpty ? .empty : .text(text)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            guard number.doubleValue.isFinite else { throw DocumentCreationError.invalidCommand }
            return .number(number.doubleValue)
        }
        throw DocumentCreationError.invalidCommand
    }

    private static func slides(_ value: Any?) throws -> [PresentationSlide] {
        guard let list = value as? [Any] else { throw DocumentCreationError.invalidCommand }
        guard !list.isEmpty else { throw DocumentCreationError.emptyContent }
        guard list.count <= DocumentCreationLimits.maximumSlides else { throw DocumentCreationError.tooManySlides }
        return try list.map { item in
            guard let slide = item as? [String: Any], Set(slide.keys).isSubset(of: ["title", "bullets"]),
                  let title = slide["title"] as? String else { throw DocumentCreationError.invalidCommand }
            let bullets: [String]
            if let given = slide["bullets"] {
                guard let list = given as? [Any] else { throw DocumentCreationError.invalidCommand }
                guard list.count <= DocumentCreationLimits.maximumBullets else { throw DocumentCreationError.tooManyBullets }
                bullets = try list.map { value in
                    guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw DocumentCreationError.invalidCommand
                    }
                    return try slideText(text)
                }
            } else { bullets = [] }
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentCreationError.invalidCommand }
            return PresentationSlide(title: try slideText(title), bullets: bullets)
        }
    }

    private static func slideText(_ text: String) throws -> String {
        guard text.count <= DocumentCreationLimits.maximumSlideTextCharacters else { throw DocumentCreationError.slideTextTooLong }
        guard OfficePackage.isXMLText(text) else { throw DocumentCreationError.invalidText }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entries(_ value: Any?) throws -> [DocumentZipItem] {
        guard let list = value as? [Any] else { throw DocumentCreationError.invalidCommand }
        guard !list.isEmpty else { throw DocumentCreationError.emptyContent }
        guard list.count <= DocumentCreationLimits.maximumEntries else { throw DocumentCreationError.tooManyEntries }
        var taken: Set<String> = []
        return try list.map { item in
            guard let entry = item as? [String: Any], let raw = entry["name"] as? String,
                  Set(entry.keys) == ["name", "text"] || Set(entry.keys) == ["name", "file"] else {
                throw DocumentCreationError.invalidCommand
            }
            guard raw.count <= DocumentCreationLimits.maximumFileNameCharacters,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentCreationError.invalidEntryName }
            // One folder level: a path is flattened into the name.
            let name = DocumentFileName.unique(DocumentFileName.sanitized(raw, extension: nil), taken: taken)
            taken.insert(name.lowercased())
            if let text = entry["text"] as? String {
                guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else { throw DocumentCreationError.invalidText }
                return DocumentZipItem(name: name, source: .text(text))
            }
            guard let file = entry["file"] as? String, !file.isEmpty else { throw DocumentCreationError.invalidCommand }
            return DocumentZipItem(name: name, source: .file(file))
        }
    }

    static func unfenced(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasPrefix("```"), body.hasSuffix("```"), body.count > 6,
              let newline = body.firstIndex(of: "\n") else { return body }
        body = String(body[body.index(after: newline)...].dropLast(3))
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A file's name from model text: NFC, one path component without control,
/// format or reserved characters, at most 80 Unicode scalars and 240 UTF-8
/// bytes before the extension, like an exported document's.
public enum DocumentFileName {
    /// Extensions dropped from a name before the format's own is added.
    static let documentExtensions: Set<String> = ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "zip",
                                                  "csv", "html", "htm", "txt", "md", "json"]

    /// `extension` is the format's, which replaces a document extension the name
    /// already has; nil keeps the name's own (an entry in a ZIP).
    public static func sanitized(_ raw: String, extension ext: String?) -> String {
        let unsafe = CharacterSet.controlCharacters.union(.illegalCharacters).union(.newlines)
            .union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        var name = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = ""
        if ext == nil {
            // Keep an entry's own extension through the length bound.
            let own = (name as NSString).pathExtension
            if !own.isEmpty, own.count <= 10, own.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) {
                kept = "." + own
                name = (name as NSString).deletingPathExtension
            }
        } else if documentExtensions.contains((name as NSString).pathExtension.lowercased()) {
            name = (name as NSString).deletingPathExtension
        }
        var base = "", scalars = 0, bytes = 0
        for character in name {
            let values = character.unicodeScalars
            if values.contains(where: { unsafe.contains($0) || $0.properties.generalCategory == .format }) { continue }
            if scalars + values.count > 80 || bytes + String(character).utf8.count > 240 { break }
            base.append(character)
            scalars += values.count
            bytes += String(character).utf8.count
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = "document" }
        let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        if reserved.contains(String(base.split(separator: ".").first ?? "").uppercased()) { base = "_" + base }
        return base + (ext.map { "." + $0 } ?? kept)
    }

    /// "a.txt", then "a (2).txt"; `taken` holds lowercased names.
    public static func unique(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name.lowercased()) else { return name }
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = base + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }
}

public enum DocumentCreation {
    /// The file's bytes. `pdf` draws a report (the App's renderer); `file`
    /// gives a file made earlier in the conversation by the name its result gave.
    public static func make(_ command: DocumentCreationCommand, language: String, modified: Date = Date(),
                            pdf: (DocumentReport) throws -> Data, file: (String) -> Data?) throws -> Data {
        let data: Data
        switch command.content {
        case .markdown(let source):
            let report: DocumentReport
            do { report = try DocumentReport.parseMarkdown(source: source, title: command.title, language: language) }
            catch let error as DocumentError { throw DocumentCreationError.content(error) }
            data = command.format == .pdf ? try pdf(report) : try WordDocumentWriter.docx(report, modified: modified)
        case .sheets(let sheets):
            data = try SpreadsheetWriter.xlsx(title: command.title, sheets: sheets, modified: modified)
        case .slides(let slides):
            data = try PresentationWriter.pptx(title: command.title, slides: slides, modified: modified)
        case .entries(let items):
            var zip = DocumentZipWriter(modified: modified)
            var total = 0
            for item in items {
                try Task.checkCancellation()
                let bytes: Data
                switch item.source {
                case .text(let text): bytes = Data(text.utf8)
                case .file(let name):
                    guard let found = file(name) else { throw DocumentCreationError.unknownFile }
                    bytes = found
                }
                total += bytes.count
                guard total <= DocumentCreationLimits.maximumArchiveInputBytes else { throw DocumentCreationError.tooLarge }
                try zip.add(item.name, bytes)
            }
            data = try zip.archive()
        }
        guard !data.isEmpty, data.count <= DocumentCreationLimits.maximumOutputBytes else { throw DocumentCreationError.tooLarge }
        return data
    }
}

/// What file_create returns to the model, as the chat's other tool results:
/// {"ok":true,...} or {"ok":false,"error","message","recoverable"}.
public enum DocumentCreationResult {
    public static func created(fileName: String, format: DocumentCreationFormat, bytes: Int) -> String {
        json(["ok": true, "file_name": fileName, "format": format.rawValue, "bytes": bytes,
              "note": "The file is shown under your answer as a card to preview, save to Files or share. Nothing is saved or shared until the user taps there. Name the file in your answer; do not repeat its content."])
    }

    public static func failed(_ error: Error) -> String {
        let (code, message) = explanation(error)
        return json(["ok": false, "error": code, "message": "No file was made: " + message, "recoverable": true])
    }

    /// The host refused the command before it ran, for a reason of its own.
    public static func refused(_ code: String, _ message: String) -> String {
        json(["ok": false, "error": code, "message": message, "recoverable": false])
    }

    static func explanation(_ error: Error) -> (String, String) {
        let limits = DocumentCreationLimits.self
        switch error as? DocumentCreationError {
        case .invalidCommand?: return ("invalid_arguments", "the arguments do not match file_create for this format. Use exactly the keys shown for it.")
        case .invalidFormat?: return ("invalid_format", "format must be pdf, docx, xlsx, pptx or zip.")
        case .invalidFileName?: return ("invalid_file_name", "file_name must be 1-\(limits.maximumFileNameCharacters) characters.")
        case .invalidTitle?: return ("invalid_title", "title must be one line of at most \(limits.maximumTitleCharacters) characters.")
        case .invalidText?: return ("invalid_text", "the text has control characters a file cannot hold.")
        case .emptyContent?: return ("empty", "there is nothing to put in the file.")
        case .tooLarge?: return ("too_large", "the file would be larger than \(limits.maximumOutputBytes / 1_048_576) MB. Make it shorter or split it into several files.")
        case .tooManySheets?: return ("too_many_sheets", "a workbook has at most \(limits.maximumSheets) sheets.")
        case .tooManyRows?: return ("too_many_rows", "a sheet has at most \(limits.maximumRows) rows.")
        case .tooManyColumns?: return ("too_many_columns", "a row has at most \(limits.maximumColumns) cells.")
        case .tooManyCells?: return ("too_many_cells", "a workbook has at most \(limits.maximumCells) cells.")
        case .cellTooLong?: return ("cell_too_long", "a cell holds at most \(limits.maximumCellCharacters) characters.")
        case .tooManySlides?: return ("too_many_slides", "a deck has at most \(limits.maximumSlides) slides.")
        case .tooManyBullets?: return ("too_many_bullets", "a slide has at most \(limits.maximumBullets) bullets.")
        case .slideTextTooLong?: return ("slide_text_too_long", "a slide title or bullet has at most \(limits.maximumSlideTextCharacters) characters.")
        case .tooManyEntries?: return ("too_many_entries", "a ZIP holds at most \(limits.maximumEntries) files.")
        case .invalidEntryName?, .duplicateEntryName?: return ("invalid_entry_name", "each entry needs its own file name.")
        case .unknownFile?: return ("unknown_file", "a file entry must name a file made earlier in this conversation by the file_name its result gave, and the user must not have removed it.")
        case .content(let reason)?:
            switch reason {
            case .invalidTable: return ("invalid_table", "every table row needs as many cells as its header, and a --- row under the header.")
            case .tooManyTables, .tooManyColumns, .tooManyRows, .tooManyCells, .tooManySections, .tooManyListItems, .sourceTooLarge, .outputTooLarge:
                return ("too_large", "the document is longer than a file can be here. Make it shorter or split it.")
            default: return ("invalid_markdown", "the markdown did not make a document. Check headings, lists and tables.")
            }
        case nil: return ("failed", "the file could not be made on this device.")
        }
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{\"ok\":false}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// How file_create is offered to the model. It replaces the fixed sentences
/// that once opened the export screen: any way of asking for a file works.
public enum DocumentCreationPrompts {
    static let commands = """
    {"action":"file_create","arguments":{"format":"pdf","file_name":"name","title":"optional title","markdown":"the whole document"}}
    pdf or docx: markdown with # headings, paragraphs, **bold**, *italic*, - or 1. lists and | tables | with a | --- | row under the header. No images or links.
    {"action":"file_create","arguments":{"format":"xlsx","file_name":"name","sheets":[{"name":"Sheet1","rows":[["Item","Qty"],["Apple",3]]}]}}
    xlsx: up to 16 sheets, the first row of each its header. Numbers as JSON numbers; IDs, phone numbers and anything with leading zeros as strings; null for an empty cell.
    {"action":"file_create","arguments":{"format":"pptx","file_name":"name","slides":[{"title":"Slide title","bullets":["point","point"]}]}}
    pptx: up to 50 slides, each a title and up to 12 short bullets.
    {"action":"file_create","arguments":{"format":"zip","file_name":"name","entries":[{"name":"notes.txt","text":"…"},{"name":"Report.pdf","file":"Report.pdf"}]}}
    zip: up to 32 entries, each a text file (text) or a file you made earlier in this conversation (file: the file_name its result gave). Make those files first.
    file_name has no folder; the format sets its extension. Write the content in the language of the user's request.
    Only an ok result means the file was made: then answer briefly and name the file; do not repeat its content. Nothing is saved or sent until the user taps 存到檔案 (Save to Files) or 分享 (Share) on its card, so never say it was saved or sent. On a failure say it was not made and why, or correct the arguments once.
    """

    /// How the offer in an ordinary chat begins.
    public static let lead = "Files: when the user asks for a file (a PDF, Word .docx, Excel .xlsx, PowerPoint .pptx or ZIP), make it with file_create instead of writing its content into your answer. Reply with exactly this JSON object and nothing else; the host makes the file on this device and shows it under your answer as a card the user can preview, save to Files or share."

    /// Offered in an ordinary chat request, beside the skill tools.
    public static let offer = lead + "\n" + commands

    /// Offered inside a step that already runs the host's commands (the skill tools step, the MCP step).
    public static let inStep = "You may also make a file when the user asks for one (a PDF, Word, Excel, PowerPoint or ZIP file): reply with exactly one file_create object; the host makes the file and shows it to the user as a card.\n" + commands
}
