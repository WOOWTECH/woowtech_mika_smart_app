import Foundation

extension DocumentReport {
    /// Standalone UTF-8 HTML. All model content is text; no links, images, scripts or network loads.
    public func html() throws -> String {
        var output = DocumentOutput()
        try output.append("""
        <!doctype html>
        <html lang="\(language.documentHTMLEscaped)"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; connect-src 'none'; img-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; style-src 'unsafe-inline'">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title.documentHTMLEscaped)</title>
        <style>
        :root{color-scheme:light}body{font-family:system-ui,sans-serif;color:#17202a;background:#fff;line-height:1.55;max-width:960px;margin:32px auto;padding:0 24px}
        h1,h2,h3,h4,h5,h6,p,li,th,td{white-space:pre-wrap;overflow-wrap:anywhere;tab-size:4}h1,h2,h3,h4,h5,h6{line-height:1.3}
        .table-scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{border:1px solid #c8cdd3;padding:8px;text-align:start;vertical-align:top}th{background:#edf1f5}thead{display:table-header-group}
        @page{size:A4;margin:16mm}@media print{body{margin:0;padding:0;max-width:none}.table-scroll{overflow:visible}h1,h2,h3{break-after:avoid}}
        </style></head><body><h1>\(title.documentHTMLEscaped)</h1>
        """)
        for section in sections {
            try Task.checkCancellation()
            switch section {
            case .heading(let level, let text):
                try output.append("<h\(level)>\(text.documentHTMLEscaped)</h\(level)>\n")
            case .paragraph(let text):
                try output.append("<p>\(text.documentHTMLEscaped)</p>\n")
            case .list(let items, let ordered):
                let tag = ordered ? "ol" : "ul"
                try output.append("<\(tag)>")
                for item in items {
                    try Task.checkCancellation()
                    try output.append("<li>\(item.documentHTMLEscaped)</li>")
                }
                try output.append("</\(tag)>\n")
            case .table(let table):
                try output.append("<div class=\"table-scroll\"><table><thead><tr>")
                for column in table.columns { try output.append("<th scope=\"col\">\(column.documentHTMLEscaped)</th>") }
                try output.append("</tr></thead><tbody>")
                for row in table.rows {
                    try Task.checkCancellation()
                    try output.append("<tr>")
                    for cell in row { try output.append("<td>\(cell.documentHTMLEscaped)</td>") }
                    try output.append("</tr>")
                }
                try output.append("</tbody></table></div>\n")
            }
        }
        try output.append("</body></html>\n")
        return output.value
    }

    /// RFC 4180 records, including a UTF-8 BOM and final CRLF. Every cell is quoted.
    /// An apostrophe is inserted before suspicious cells without deleting any original text.
    public func csv(tableIndex: Int = 0) throws -> String {
        let table = try table(at: tableIndex)
        var output = DocumentOutput()
        try output.append("\u{FEFF}")
        func appendRow(_ row: [String]) throws {
            try Task.checkCancellation()
            for (index, cell) in row.enumerated() {
                if index > 0 { try output.append(",") }
                let normalized = cell.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .replacingOccurrences(of: "\n", with: "\r\n")
                let safe = (cell.documentNeedsFormulaProtection ? "'" : "") + normalized
                try output.append("\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            }
            try output.append("\r\n")
        }
        try appendRow(table.columns)
        for row in table.rows { try appendRow(row) }
        return output.value
    }

    /// Matches precisely the selected CSV export, including header cells, not the whole report.
    public func formulaProtectedCellCount(tableIndex: Int = 0) throws -> Int {
        let table = try table(at: tableIndex)
        var count = table.columns.filter(\.documentNeedsFormulaProtection).count
        for row in table.rows {
            try Task.checkCancellation()
            count += row.filter(\.documentNeedsFormulaProtection).count
        }
        return count
    }

    public static func parseMarkdownAsync(source: String, title: String, language: String) async throws -> Self {
        try await DocumentGenerationWorker.shared.parse(source: source, title: title, language: language)
    }

    public func htmlAsync() async throws -> String {
        try await DocumentGenerationWorker.shared.html(self)
    }

    public func csvAsync(tableIndex: Int = 0) async throws -> String {
        try await DocumentGenerationWorker.shared.csv(self, tableIndex: tableIndex)
    }
}

/// A separate serial executor, never the MainActor. Actor hops retain task cancellation.
private actor DocumentGenerationWorker {
    static let shared = DocumentGenerationWorker()
    func parse(source: String, title: String, language: String) throws -> DocumentReport {
        try DocumentReport.parseMarkdown(source: source, title: title, language: language)
    }
    func html(_ report: DocumentReport) throws -> String { try report.html() }
    func csv(_ report: DocumentReport, tableIndex: Int) throws -> String { try report.csv(tableIndex: tableIndex) }
}

struct DocumentOutput {
    private(set) var value = ""
    private var bytes = 0

    mutating func append(_ text: String) throws {
        let count = text.utf8.count
        guard count <= DocumentLimits.maximumOutputBytes - bytes else { throw DocumentError.outputTooLarge }
        value += text
        bytes += count
    }
}

private extension String {
    var documentHTMLEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    var documentNeedsFormulaProtection: Bool {
        for scalar in unicodeScalars {
            if scalar == "\t" || scalar == "\r" || scalar == "\n" { return true }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0xFEFF { continue }
            return scalar == "=" || scalar == "+" || scalar == "-" || scalar == "@"
        }
        return false
    }
}
