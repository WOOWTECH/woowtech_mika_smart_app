import AssistantDocuments
import CoreText
import Foundation
import UIKit

public enum DocumentPDFError: Error, Equatable, Sendable {
    case pageLimitExceeded, unrenderableText, outputTooLarge
}

/// Native, local-only PDF drawing; no WebKit, HTML import, network, or UI state.
/// Call render from a dedicated actor, or use renderAsync. Each invocation owns its layout.
public enum DocumentPDFRenderer {
    public static let maximumPages = 256
    public static let maximumOutputBytes = DocumentLimits.maximumOutputBytes

    public static func render(_ report: DocumentReport) throws -> Data {
        try render(report, pageLimit: maximumPages)
    }

    public static func renderAsync(_ report: DocumentReport) async throws -> Data {
        try await DocumentPDFWorker.shared.render(report)
    }

    /// Internal limit override makes the failure path testable without rendering 256 pages.
    static func render(_ report: DocumentReport, pageLimit: Int) throws -> Data {
        try Task.checkCancellation()
        guard (1...maximumPages).contains(pageLimit) else { throw DocumentPDFError.pageLimitExceeded }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: report.title,
                               kCGPDFContextCreator as String: "Assistant Documents"]
        let renderer = UIGraphicsPDFRenderer(bounds: PDFLayout.page, format: format)
        var failure: Error?
        let data = renderer.pdfData { context in
            do {
                try PDFLayout(context: context, language: report.language, pageLimit: pageLimit).draw(report)
            } catch { failure = error }
        }
        if let failure { throw failure }
        try Task.checkCancellation()
        guard data.count <= maximumOutputBytes else { throw DocumentPDFError.outputTooLarge }
        return data
    }
}

private actor DocumentPDFWorker {
    static let shared = DocumentPDFWorker()
    func render(_ report: DocumentReport) throws -> Data { try DocumentPDFRenderer.render(report) }
}

private struct PDFLine {
    let value: CTLine
    let ascent: CGFloat
    let leadingInset: CGFloat
    let width: CGFloat
    let height: CGFloat
}

/// UTF-16 offsets are advanced only by Core Text cluster/line breaks. No substring is dropped.
private struct PDFText {
    private let typesetter: CTTypesetter
    private let string: NSString
    private let fontSize: CGFloat
    private var offset = 0

    init(_ text: String, size: CGFloat, language: String, bold: Bool = false) {
        fontSize = size
        string = text as NSString
        let systemFont = CTFontCreateUIFontForLanguage(.system, size, language as CFString)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let font = bold ? (CTFontCreateCopyWithSymbolicTraits(systemFont, size, nil, .traitBold, .traitBold) ?? systemFont)
            : systemFont
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.09, alpha: 1)
        ]
        typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    mutating func next(width: CGFloat) throws -> PDFLine? {
        try Task.checkCancellation()
        guard offset < string.length else { return nil }
        guard width > 0 else { throw DocumentPDFError.unrenderableText }
        var count = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
        if count <= 0 { count = CTTypesetterSuggestClusterBreak(typesetter, offset, Double(width)) }
        // A single oversized grapheme is kept whole and scaled horizontally when drawn.
        if count <= 0 { count = string.rangeOfComposedCharacterSequence(at: offset).length }
        guard count > 0, count <= string.length - offset else { throw DocumentPDFError.unrenderableText }
        var line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count))
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width) {
            let clusters = CTTypesetterSuggestClusterBreak(typesetter, offset, Double(width))
            if clusters > 0 && clusters < count {
                count = clusters
                line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count))
            }
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        var measuredWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var leadingInset: CGFloat = 0
        // Include actual glyph extents (fallback CJK/emoji/combining marks), not only nominal font metrics.
        let glyphs = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if !glyphs.isNull && !glyphs.isInfinite {
            ascent = max(ascent, glyphs.maxY)
            descent = max(descent, -glyphs.minY)
            leadingInset = max(0, -glyphs.minX)
            measuredWidth = max(measuredWidth, glyphs.maxX) + leadingInset
        }
        let height = max(fontSize * 1.35, ascent + descent + max(0, leading) + 4)
        guard height.isFinite, measuredWidth.isFinite, height > 0 else { throw DocumentPDFError.unrenderableText }
        offset += count
        return PDFLine(value: line, ascent: ascent, leadingInset: leadingInset, width: measuredWidth, height: height)
    }
}

private final class PDFLayout {
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // ISO A4 points
    private static let margin: CGFloat = 42.52 // 15 mm
    private static let cellPadding: CGFloat = 6
    private let context: UIGraphicsPDFRendererContext
    private let language: String
    private let pageLimit: Int
    private var pageCount = 0
    private var y = PDFLayout.margin
    private var bottom: CGFloat { Self.page.height - Self.margin }
    private var width: CGFloat { Self.page.width - 2 * Self.margin }
    private var bodyHeight: CGFloat { bottom - Self.margin }
    private var cg: CGContext { context.cgContext }

    init(context: UIGraphicsPDFRendererContext, language: String, pageLimit: Int) {
        self.context = context
        self.language = language
        self.pageLimit = pageLimit
    }

    func draw(_ report: DocumentReport) throws {
        try beginPage()
        try paragraph(report.title, size: 23, bold: true, gap: 16)
        for section in report.sections {
            try Task.checkCancellation()
            switch section {
            case .heading(let level, let text):
                try paragraph(text, size: max(12, 22 - CGFloat(level) * 2), bold: true, gap: 10)
            case .paragraph(let text):
                try paragraph(text, size: 11, gap: 10)
            case .list(let items, let ordered):
                for (index, item) in items.enumerated() {
                    try paragraph((ordered ? "\(index + 1). " : "• ") + item, size: 11, gap: 5)
                }
                y += 5
            case .table(let table):
                try drawTable(table)
            }
        }
    }

    private func beginPage() throws {
        try Task.checkCancellation()
        guard pageCount < pageLimit else { throw DocumentPDFError.pageLimitExceeded }
        context.beginPage()
        pageCount += 1
        y = Self.margin
        var footer = PDFText(String(pageCount), size: 9, language: language)
        if let line = try footer.next(width: width) {
            paint(line, x: Self.margin, top: bottom + 12, availableWidth: width)
        }
    }

    private func paragraph(_ text: String, size: CGFloat, bold: Bool = false, gap: CGFloat) throws {
        var flow = PDFText(text, size: size, language: language, bold: bold)
        while let line = try flow.next(width: width) {
            guard line.height <= bodyHeight else { throw DocumentPDFError.unrenderableText }
            if y + line.height > bottom { try beginPage() }
            paint(line, x: Self.margin, top: y, availableWidth: width)
            y += line.height
        }
        y += gap
    }

    private func lines(_ text: String, width: CGFloat, bold: Bool = false) throws -> [PDFLine] {
        var flow = PDFText(text, size: 10, language: language, bold: bold)
        var result: [PDFLine] = []
        var height: CGFloat = 0
        while let line = try flow.next(width: width) {
            height += line.height
            guard height <= CGFloat(pageLimit) * bodyHeight else { throw DocumentPDFError.pageLimitExceeded }
            result.append(line)
        }
        return result
    }

    private func drawTable(_ table: DocumentTable) throws {
        // At most four readable columns per panel. Every column/row remains in the PDF.
        for start in stride(from: 0, to: table.columns.count, by: 4) {
            let end = min(start + 4, table.columns.count)
            let wide = table.columns.count > 4
            // Row numbers retain cross-panel row associations when different cells wrap differently.
            let count = end - start + (wide ? 1 : 0)
            let cellWidth = width / CGFloat(count)
            let textWidth = cellWidth - 2 * Self.cellPadding
            if wide {
                let label = language.hasPrefix("zh") ? "欄" : "Columns"
                try paragraph("\(label) \(start + 1)–\(end)", size: 11, bold: true, gap: 8)
            }
            var header = try table.columns[start..<end].map { try lines($0, width: textWidth, bold: true) }
            if wide { header.insert(try lines("#", width: textWidth, bold: true), at: 0) }
            var headerHeight = rowHeight(header)
            // An arbitrarily long header cannot be repeated verbatim and still leave room for rows.
            // Preserve it in full as a numbered key, then repeat its short identifiers on each page.
            if headerHeight > bodyHeight / 3 {
                for column in start..<end {
                    try paragraph("[\(column + 1)] " + table.columns[column], size: 10, bold: true, gap: 6)
                }
                header = try (start..<end).map { try lines("[\($0 + 1)]", width: textWidth, bold: true) }
                if wide { header.insert(try lines("#", width: textWidth, bold: true), at: 0) }
                headerHeight = rowHeight(header)
            }
            if y + headerHeight + 28 > bottom { try beginPage() }
            drawWholeRow(header, height: headerHeight, header: true)
            for (rowIndex, row) in table.rows.enumerated() {
                try Task.checkCancellation()
                var cells = try row[start..<end].map { try lines($0, width: textWidth) }
                if wide { cells.insert(try lines(String(rowIndex + 1), width: textWidth), at: 0) }
                try drawBodyRow(cells, header: header, headerHeight: headerHeight, repeatRowNumber: wide)
            }
            y += 12
        }
    }

    private func rowHeight(_ cells: [[PDFLine]]) -> CGFloat {
        max(14, cells.map { $0.reduce(CGFloat.zero) { $0 + $1.height } }.max() ?? 0) + 2 * Self.cellPadding
    }

    private func drawWholeRow(_ cells: [[PDFLine]], height: CGFloat, header: Bool) {
        let cellWidth = width / CGFloat(cells.count)
        for (index, lines) in cells.enumerated() {
            let x = Self.margin + CGFloat(index) * cellWidth
            border(x: x, height: height, width: cellWidth, header: header)
            var top = y + Self.cellPadding
            for line in lines {
                paint(line, x: x + Self.cellPadding, top: top, availableWidth: cellWidth - 2 * Self.cellPadding)
                top += line.height
            }
        }
        y += height
    }

    private func drawBodyRow(_ cells: [[PDFLine]], header: [[PDFLine]], headerHeight: CGFloat,
                             repeatRowNumber: Bool) throws {
        let cellWidth = width / CGFloat(cells.count)
        var offsets = Array(repeating: 0, count: cells.count)
        var firstFragment = true
        repeat {
            try Task.checkCancellation()
            let remaining = bottom - y - 2 * Self.cellPadding
            let numberHeight = repeatRowNumber ? cells[0].reduce(CGFloat.zero) { $0 + $1.height } : 0
            let nextHeight = max(14, max(numberHeight, cells.enumerated().compactMap { index, lines -> CGFloat? in
                offsets[index] < lines.count ? lines[offsets[index]].height : nil
            }.max() ?? 14))
            if remaining < nextHeight {
                try beginPage()
                drawWholeRow(header, height: headerHeight, header: true)
            }
            let available = bottom - y - 2 * Self.cellPadding
            var fragments = Array(repeating: [PDFLine](), count: cells.count)
            let oldOffsets = offsets
            for index in cells.indices {
                var used: CGFloat = 0
                while offsets[index] < cells[index].count {
                    let line = cells[index][offsets[index]]
                    guard line.height <= bodyHeight - headerHeight - 2 * Self.cellPadding else {
                        throw DocumentPDFError.unrenderableText
                    }
                    if used + line.height > available { break }
                    fragments[index].append(line)
                    used += line.height
                    offsets[index] += 1
                }
            }
            let isEmptyRow = cells.allSatisfy(\.isEmpty)
            guard offsets != oldOffsets || (firstFragment && isEmptyRow) else {
                throw DocumentPDFError.unrenderableText // explicit progress invariant
            }
            if repeatRowNumber && fragments[0].isEmpty { fragments[0] = cells[0] }
            let height = rowHeight(fragments)
            guard y + height <= bottom + 0.01 else { throw DocumentPDFError.unrenderableText }
            // Include the row's grid on every fragment, even when some columns finished earlier.
            for (index, fragment) in fragments.enumerated() {
                let x = Self.margin + CGFloat(index) * cellWidth
                border(x: x, height: height, width: cellWidth, header: false)
                var top = y + Self.cellPadding
                for line in fragment {
                    paint(line, x: x + Self.cellPadding, top: top, availableWidth: cellWidth - 2 * Self.cellPadding)
                    top += line.height
                }
            }
            y += height
            firstFragment = false
        } while cells.indices.contains(where: { offsets[$0] < cells[$0].count })
    }

    private func border(x: CGFloat, height: CGFloat, width: CGFloat, header: Bool) {
        cg.saveGState()
        let rect = CGRect(x: x, y: y, width: width, height: height)
        if header {
            cg.setFillColor(CGColor(gray: 0.94, alpha: 1))
            cg.fill(rect)
        }
        cg.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
        cg.setLineWidth(0.5)
        cg.stroke(rect)
        cg.restoreGState()
    }

    private func paint(_ line: PDFLine, x: CGFloat, top: CGFloat, availableWidth: CGFloat) {
        cg.saveGState()
        cg.textMatrix = .identity
        let scale = line.width > availableWidth ? availableWidth / line.width : 1
        cg.translateBy(x: x + line.leadingInset * scale, y: top + 2 + line.ascent)
        cg.scaleBy(x: scale, y: -1)
        cg.textPosition = .zero
        CTLineDraw(line.value, cg)
        cg.restoreGState()
    }
}
