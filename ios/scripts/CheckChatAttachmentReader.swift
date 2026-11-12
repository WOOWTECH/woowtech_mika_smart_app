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
        expect(read(strip, .photo) == .unreadable("這張圖片太大，沒能讀取"), "over 8192 px a side")
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

        print("{\"assertions\":\(assertions)}")
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
