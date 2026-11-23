import Compression
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stand-in for the app's shared kind (ChatAttachmentModels.swift).
enum ChatAttachmentKind: String, Codable, Sendable { case photo, file }

@main
enum CheckChatAttachmentReader {
    typealias Content = ChatAttachmentReadResult.Content

    static func main() throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ label: String, line: Int = #line) {
            guard condition() else { fail(label, line: line) }
            assertions += 1
        }
        let arguments = ProcessInfo.processInfo.arguments
        let directory = arguments.count > 1 ? URL(fileURLWithPath: arguments[1], isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent("ChatAttachmentReader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func fixture(_ name: String, _ data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        func read(_ url: URL, _ kind: ChatAttachmentKind = .file, type: String? = nil, limit: Int = 4096) -> Content {
            ChatAttachmentReader.read(fileURL: url, kind: kind, contentType: type, textByteLimit: limit).content
        }
        let notText = Content.unreadable("這個檔案不是文字檔，沒能讀取內容")

        // Sizes as Android writes them: nearest KB, and "%.1f" rounding half up.
        let sizes: [(Int64, String)] = [
            (0, "0 B"), (1023, "1023 B"), (1024, "1 KB"), (1023 * 1024, "1023 KB"), (1 << 20, "1.0 MB"),
            (13_107_200, "12.5 MB"), (1536, "2 KB"), (1_310_720, "1.3 MB"), (2 * (1 << 20) - 1, "2.0 MB"),
            (200 << 20, "200.0 MB"), (-1, "0 B"),
        ]
        for (bytes, text) in sizes { expect(ChatAttachmentFormat.byteString(bytes) == text, "byteString(\(bytes))") }

        // UTF-8 text: CRLF becomes LF, and a cut never splits a character.
        let lines = try fixture("notes.txt", Data("第一行\r\n第二行\r\nthird".utf8))
        expect(read(lines) == .text("第一行\n第二行\nthird", truncated: false), "CRLF normalized")
        let chinese = try fixture("chinese.txt", Data("你好世界".utf8))
        expect(read(chinese, limit: 12) == .text("你好世界", truncated: false), "a text at the limit is whole")
        let cut = read(chinese, limit: 7)
        expect(cut == .text("你好", truncated: true), "a cut inside 世 drops it")
        if case .text(let text, _) = cut {
            expect(text.utf8.count <= 7 && String(data: Data(text.utf8), encoding: .utf8) == text, "cut text is valid UTF-8")
        }
        expect(read(chinese, limit: 0) == .text("", truncated: true), "zero limit")
        let emoji = try fixture("emoji.txt", Data("ab👍🏽".utf8))
        expect(read(emoji, limit: 6) == .text("ab", truncated: true), "a cut never splits an emoji")
        let marked = try fixture("bom.txt", Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8))
        expect(read(marked) == .text("hi", truncated: false), "UTF-8 BOM dropped")
        let empty = try fixture("empty.txt", Data())
        expect(read(empty) == .text("", truncated: false), "empty file")
        // 1001 + 4 + 65536 bytes is not a multiple of 3: the bounded read ends inside a 中.
        let long = try fixture("long.md", Data(String(repeating: "中", count: 100_000).utf8))
        expect(read(long, limit: 1001) == .text(String(repeating: "中", count: 333), truncated: true), "long text")

        // Binary data is refused with the exact reason.
        let nul = try fixture("data.txt", Data("abc\u{0}def".utf8))
        expect(read(nul) == notText, "NUL means binary")
        let late = try fixture("late.log", Data((String(repeating: "a", count: 2000) + "\u{0}b").utf8))
        expect(read(late, limit: 100) == notText, "NUL past the limit is still sniffed")
        let big5 = try fixture("big5.txt", Data([0xA4, 0xA4, 0xA4, 0xE5, 0x0A]))
        expect(read(big5) == notText, "Big5 is not UTF-8")

        // UTF-16 with a BOM, bounded by the UTF-8 bytes of the result.
        let little = try fixture("windows.txt", utf16("Hello 世界\r\n第二行", bigEndian: false))
        expect(read(little) == .text("Hello 世界\n第二行", truncated: false), "UTF-16LE")
        let big = try fixture("classic.txt", utf16("Hello 世界\r\n第二行", bigEndian: true))
        expect(read(big) == .text("Hello 世界\n第二行", truncated: false), "UTF-16BE")
        expect(read(little, limit: 8) == .text("Hello ", truncated: true), "UTF-16 cut")
        let wide = try fixture("wide.txt", utf16(String(repeating: "x", count: 300_000), bigEndian: false))
        expect(read(wide, limit: 100_000) == .text(String(repeating: "x", count: 100_000), truncated: true),
               "UTF-16 fills the limit")

        // Photos become a JPEG whose long side is at most 1280, never upscaled.
        let large = directory.appendingPathComponent("large.png")
        write([bitmap(3000, 2000) { fill($0, 3000, 2000, red: 0.2, green: 0.5, blue: 0.8) }], .png, to: large)
        let scaled = picture(read(large, .photo, type: UTType.png.identifier))
        expect(scaled.width == 1280 && (853...854).contains(scaled.height), "3000×2000 → long side 1280")
        expect(scaled.jpeg.starts(with: [0xFF, 0xD8, 0xFF]), "JPEG bytes")
        expect(size(of: scaled.jpeg) == [scaled.width, scaled.height], "reported size matches the JPEG")
        let small = directory.appendingPathComponent("small.png")
        write([bitmap(100, 80) { fill($0, 100, 80, red: 1, green: 0, blue: 0) }], .png, to: small)
        let kept = picture(read(small))   // a file typed only by its extension
        expect(kept.width == 100 && kept.height == 80, "100×80 is not upscaled")

        // Transparent pixels land on white, not black.
        let clear = directory.appendingPathComponent("logo.png")
        write([bitmap(40, 40, alpha: true) { $0.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); $0.fill(CGRect(x: 10, y: 10, width: 20, height: 20)) }],
              .png, to: clear)
        let flattened = picture(read(clear, .photo))
        expect(rgb(of: flattened.jpeg, x: 1, y: 1).allSatisfy { $0 >= 235 }, "transparent corner is white")
        expect(rgb(of: flattened.jpeg, x: 20, y: 20).allSatisfy { $0 <= 30 }, "opaque centre stays black")

        // EXIF orientation is applied; a GIF gives its first frame.
        let rotated = directory.appendingPathComponent("rotated.jpg")
        write([bitmap(300, 200) { fill($0, 300, 200, red: 0, green: 1, blue: 0) }], .jpeg, to: rotated,
              frame: [kCGImagePropertyOrientation: 6])
        let upright = picture(read(rotated, .photo))
        expect(upright.width == 200 && upright.height == 300, "orientation 6 turns 300×200 upright")
        let animated = directory.appendingPathComponent("animated.gif")
        write([bitmap(60, 40) { fill($0, 60, 40, red: 1, green: 0, blue: 0) },
               bitmap(60, 40) { fill($0, 60, 40, red: 0, green: 0, blue: 1) }], .gif, to: animated,
              frame: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]])
        let frame = picture(read(animated, .photo))
        let colour = rgb(of: frame.jpeg, x: 30, y: 20)
        expect(frame.width == 60 && frame.height == 40 && colour[0] >= 200 && colour[2] <= 60, "GIF first frame")

        // Oversized, broken and undrawable pictures.
        let strip = directory.appendingPathComponent("strip.png")
        write([bitmap(9000, 10) { fill($0, 9000, 10, red: 0, green: 0, blue: 0) }], .png, to: strip)
        expect(read(strip, .photo) == .unreadable("這張圖片太大或太長，沒能交給模型；可以裁成幾張再附上"), "over 8192 px a side")
        let broken = try fixture("broken.jpg", Data("not a picture".utf8))
        expect(read(broken, .photo) == .unreadable("這張圖片沒能讀取"), "broken photo")
        let garbage = try fixture("garbage.png", Data([0x00, 0x01, 0x02, 0x03, 0x00]))
        expect(read(garbage) == .unreadable("這張圖片沒能讀取"), "a binary non-picture keeps the picture reason")
        let svg = try fixture("logo.svg", Data(#"<svg xmlns="http://www.w3.org/2000/svg"><text>Hi</text></svg>"#.utf8))
        if case .text(let text, false) = read(svg) {
            expect(text.hasPrefix("<svg") && text.contains("<text>Hi</text>"), "SVG source")
        } else { fail("SVG falls back to its text") }

        // PDFs: page headers, truncation, scans and passwords.
        let onePage = directory.appendingPathComponent("letter.pdf")
        writePDF(["Woowtech 渥屋"], to: onePage)
        if case .text(let text, false) = read(onePage, type: UTType.pdf.identifier) {
            expect(text.hasPrefix("— 第 1 頁 —\n") && text.contains("Woowtech"), "PDF text")
            expect(text.contains("渥屋"), "PDF Chinese text")
        } else { fail("one-page PDF") }
        let pages = directory.appendingPathComponent("pages.pdf")
        writePDF(["Alpha", "", "Gamma"], to: pages)
        expect(read(pages) == .text("— 第 1 頁 —\nAlpha\n\n— 第 3 頁 —\nGamma", truncated: false), "pages joined")
        let first = "— 第 1 頁 —\nAlpha"
        expect(read(pages, limit: first.utf8.count + 3) == .text(first, truncated: true), "PDF stops at the limit")
        let scan = directory.appendingPathComponent("scan.pdf")
        writePDF([""], to: scan)
        expect(read(scan) == .unreadable("這份 PDF 沒有可讀取的文字（可能是掃描檔）"), "PDF without text")
        let locked = directory.appendingPathComponent("locked.pdf")
        writePDF(["Secret"], to: locked, password: "1234")
        expect(read(locked) == .unreadable("這份 PDF 有密碼保護，沒能讀取內容"), "locked PDF")
        let untyped = try fixture("document", try Data(contentsOf: onePage))
        if case .text(let text, _) = read(untyped) { expect(text.contains("Woowtech"), "PDF found by %PDF-") }
        else { fail("PDF without a name extension") }
        let damaged = try fixture("damaged.pdf", Data("%PDF-1.7\nnot really".utf8))
        expect(read(damaged) == .unreadable("這份 PDF 沒能讀取"), "damaged PDF")

        // RTF, by type, by its {\rtf opening, and as an RTFD package.
        let rtf = Data(rtfSource("Hello RTF 渥屋").utf8)
        for url in [try fixture("note.rtf", rtf), try fixture("letter.doc", rtf)] {
            if case .text(let text, false) = read(url) {
                expect(text.contains("Hello RTF 渥屋") && !text.contains(#"\rtf"#), "RTF text")
            } else { fail("RTF") }
        }
        let package = directory.appendingPathComponent("memo.rtfd")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try rtf.write(to: package.appendingPathComponent("TXT.rtf"))
        if case .text(let text, false) = read(package) { expect(text.contains("Hello RTF"), "RTFD package") }
        else { fail("RTFD package") }

        // Missing, oversized and folder attachments.
        expect(read(directory.appendingPathComponent("gone.txt")) == .unreadable("這個附件已經不在了"), "missing file")
        let huge = directory.appendingPathComponent("huge.mov")
        // Sparse: the size is all the guard needs, so no disk space is used.
        FileManager.default.createFile(atPath: huge.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(ChatAttachmentReader.maxFileBytes) + 1)
        try handle.close()
        expect(read(huge) == .unreadable("檔案太大，沒能讀取"), "over 200 MB")
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        expect(read(folder) == notText, "a folder is not text")

        do {
            // Word, PowerPoint and Excel: the words of the zip's XML parts, stored or deflated.
            let w = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#
            let document = "<w:document \(w)><w:body><w:p><w:r><w:t>第一段</w:t></w:r></w:p><w:tbl><w:tr>"
                + "<w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
                + "<w:p><w:r><w:t>末段</w:t><w:tab/><w:t>X</w:t><w:br/><w:t>下一行</w:t></w:r></w:p></w:body></w:document>"
            let docx = try fixture("報告.docx", zip(["[Content_Types].xml": "<Types/>", "word/document.xml": document]))
            expect(read(docx) == .text("第一段\nA1 | B1 | \n末段\tX\n下一行", truncated: false), "docx: paragraphs, a table row, a tab and a break")
            let stored = try fixture("stored.docx", zip(["word/document.xml": document], deflate: false))
            expect(read(stored) == read(docx), "docx: a stored part reads the same")
            if case .text(let cut, let truncated) = read(docx, limit: 10) {
                expect(truncated && cut.utf8.count <= 10, "docx: the text limit holds")
            } else { fail("docx: limited read") }
            let slide = #"<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>標題</a:t></a:r></a:p>"#
                + "<a:p><a:r><a:t>重點一</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"
            let pptx = try fixture("簡報.pptx", zip(["ppt/slides/slide2.xml": slide.replacingOccurrences(of: "標題", with: "第二張"),
                                                     "ppt/slides/slide1.xml": slide]))
            expect(read(pptx) == .text("--- Slide 1 ---\n標題\n重點一\n--- Slide 2 ---\n第二張\n重點一", truncated: false),
                   "pptx: slides in order, a line per paragraph")
            let xlsx = try fixture("價目.xlsx", zip([
                "xl/workbook.xml": #"<workbook><sheets><sheet name="價目" sheetId="1"/></sheets></workbook>"#,
                "xl/sharedStrings.xml": "<sst><si><t>品名</t></si><si><r><t>價</t></r><r><t>格</t></r></si></sst>",
                "xl/worksheets/sheet1.xml": #"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>"#
                    + #"<row r="2"><c r="A2" t="inlineStr"><is><t>茶</t></is></c><c r="C2"><v>30</v></c></row></sheetData></worksheet>"#]))
            expect(read(xlsx) == .text("--- Sheet: 價目 ---\n品名\t價格\n茶\t\t30", truncated: false),
                   "xlsx: shared and inline strings, numbers, each in its own column")
            let other = try fixture("photos.zip", zip(["a.txt": "hello"]))
            expect(read(other) == .unreadable("這是壓縮檔或不支援的格式，沒能讀取內容；請解壓縮，或另存成 PDF、Word 或純文字再附上"), "another zip")
            let broken = try fixture("壞掉.docx", zip(["[Content_Types].xml": "<Types/>"]))
            expect(read(broken) == .unreadable("這份 Office 檔沒能讀取（可能已損壞）"), "docx without its document")
            let ole = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) + Data(repeating: 0, count: 504)
            let locked = try fixture("密碼.docx", ole), old = try fixture("舊版.doc", ole), empty = try fixture("空.txt", Data())
            expect(read(locked) == .unreadable("這份 Office 檔有密碼保護，沒能讀取內容"), "encrypted docx")
            expect(read(old) == .unreadable("這是舊版 Office 格式（.doc、.xls、.ppt），請另存成 .docx、.xlsx、.pptx 或 PDF 再附上"),
                   "a 97-2003 file")
            expect(ChatAttachmentReader.problem(fileURL: empty, kind: .file, contentType: nil) == "這個檔案是空的",
                   "an empty file is refused when added")
            expect(ChatAttachmentReader.problem(fileURL: docx, kind: .file, contentType: nil) == nil, "a readable docx is added")
        }

        print("{\"assertions\":\(assertions)}")
    }

    /// A zip of these parts, deflated (raw DEFLATE, as zip stores it) or stored.
    static func zip(_ parts: [String: String], deflate: Bool = true) -> Data {
        var local = Data(), central = Data()
        func put(_ data: inout Data, _ value: Int, _ width: Int) {
            for index in 0..<width { data.append(UInt8((value >> (8 * index)) & 0xFF)) }
        }
        for (name, text) in parts.sorted(by: { $0.key < $1.key }) {
            let raw = Data(text.utf8)
            var body = raw
            if deflate {
                var output = [UInt8](repeating: 0, count: raw.count + 1024)
                let count = raw.withUnsafeBytes { input in
                    compression_encode_buffer(&output, output.count, input.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
                body = Data(output.prefix(count))
            }
            let nameBytes = Data(name.utf8), offset = local.count, method = deflate ? 8 : 0
            // Local header: signature, version, flags, method, time, date, crc, sizes, name and extra lengths.
            for (value, width) in [(0x0403_4b50, 4), (20, 2), (0, 2), (method, 2), (0, 2), (0, 2), (0, 4),
                                   (body.count, 4), (raw.count, 4), (nameBytes.count, 2), (0, 2)] {
                put(&local, value, width)
            }
            local.append(nameBytes)
            local.append(body)
            // Central entry: as above, plus comment, disk, attributes and the local header's offset.
            for (value, width) in [(0x0201_4b50, 4), (20, 2), (20, 2), (0, 2), (method, 2), (0, 2), (0, 2), (0, 4),
                                   (body.count, 4), (raw.count, 4), (nameBytes.count, 2), (0, 2), (0, 2), (0, 2), (0, 2),
                                   (0, 4), (offset, 4)] {
                put(&central, value, width)
            }
            central.append(nameBytes)
        }
        var end = Data()
        for (value, width) in [(0x0605_4b50, 4), (0, 2), (0, 2), (parts.count, 2), (parts.count, 2),
                               (central.count, 4), (local.count, 4), (0, 2)] {
            put(&end, value, width)
        }
        return local + central + end
    }

    static func fail(_ label: String, line: Int = #line) -> Never {
        FileHandle.standardError.write(Data("FAIL line \(line): \(label)\n".utf8))
        exit(1)
    }

    static func picture(_ content: Content, line: Int = #line) -> (jpeg: Data, width: Int, height: Int) {
        guard case .image(let jpeg, let width, let height) = content else { fail("expected a picture: \(content)", line: line) }
        return (jpeg, width, height)
    }

    static func utf16(_ text: String, bigEndian: Bool) -> Data {
        let bom: [UInt8] = bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]
        return Data(bom + text.utf16.flatMap { unit -> [UInt8] in
            let high = UInt8(unit >> 8), low = UInt8(unit & 0xFF)
            return bigEndian ? [high, low] : [low, high]
        })
    }

    /// Word-style RTF: each non-ASCII scalar is a decimal Unicode escape with a "?" fallback.
    static func rtfSource(_ text: String) -> String {
        let body = text.unicodeScalars.map { $0.isASCII ? String($0) : "\\" + "u" + String($0.value) + "?" }.joined()
        return #"{\rtf1\ansi\ansicpg1252\uc1{\fonttbl\f0\fswiss Helvetica;}\f0\pard "# + body + #"\par}"#
    }

    static func bitmap(_ width: Int, _ height: Int, alpha: Bool = false, _ draw: (CGContext) -> Void) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: info.rawValue) else { fail("bitmap context") }
        draw(context)
        guard let image = context.makeImage() else { fail("bitmap image") }
        return image
    }

    static func fill(_ context: CGContext, _ width: Int, _ height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) {
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func write(_ images: [CGImage], _ type: UTType, to url: URL, frame: [CFString: Any]? = nil) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)
        else { fail("image destination") }
        for image in images { CGImageDestinationAddImage(destination, image, frame.map { $0 as CFDictionary }) }
        guard CGImageDestinationFinalize(destination) else { fail("image write") }
    }

    static func size(of jpeg: Data) -> [Int] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return [image.width, image.height]
    }

    /// Red, green and blue at a point counted from the top-left corner.
    static func rgb(of jpeg: Data, x: Int, y: Int) -> [Int] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return [] }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4   // the bitmap's first row is the picture's top row
        return (0..<3).map { Int(pixels[offset + $0]) }
    }

    static func writePDF(_ pages: [String], to url: URL, password: String? = nil) {
        var box = CGRect(x: 0, y: 0, width: 320, height: 240)
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextOwnerPassword] = password + "-owner"
            info[kCGPDFContextUserPassword] = password
        }
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { fail("PDF context") }
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for text in pages {
            context.beginPDFPage(nil)
            if !text.isEmpty {
                let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 24, y: 120)
                CTLineDraw(CTLineCreateWithAttributedString(string as CFAttributedString), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }
}
