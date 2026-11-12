import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// What a model receives for one stored attachment.
struct ChatAttachmentReadResult: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case image(jpeg: Data, pixelWidth: Int, pixelHeight: Int)
        case text(String, truncated: Bool)
        case unreadable(String)   // user-facing zh-Hant reason, e.g. "這個檔案不是文字檔，沒能讀取內容"
    }
    let content: Content
}

/// Reads attachments on the device, where Android hands the copied file to its
/// sandbox's read_file. Synchronous and free of UI state, so callers run it off
/// the main actor; it never logs names or contents.
enum ChatAttachmentReader {
    /// Nested so it cannot collide with another file's `ChatAttachmentText`:
    /// a top-level private enum still clashes with an internal one of that name.
    enum ChatAttachmentText {
        static let imageTooLarge = "這張圖片太大，沒能讀取"
        static let imageFailed = "這張圖片沒能讀取"
        static let pdfLocked = "這份 PDF 有密碼保護，沒能讀取內容"
        static let pdfNoText = "這份 PDF 沒有可讀取的文字（可能是掃描檔）"
        static let pdfFailed = "這份 PDF 沒能讀取"
        static let notText = "這個檔案不是文字檔，沒能讀取內容"
        static let fileTooLarge = "檔案太大，沒能讀取"
        static let fileFailed = "這個檔案沒能讀取"
        static let missing = "這個附件已經不在了"
    }

    /// The store refuses larger files first (Android `200L shl 20`).
    static let maxFileBytes: Int64 = 200 << 20
    /// Long side of the JPEG a vision model gets, like Android's read_file.
    static let imageMaxPixelSize = 1280
    static let maxImageBytes = 5 << 20
    /// Checked before decoding: even a thumbnail of a huge PNG decodes every pixel.
    private static let maxDecodedSide = 8192
    private static let maxDecodedPixels = 80_000_000
    /// Read past the text limit, so a binary file that opens like text is still caught.
    private static let sniffBytes = 64 << 10

    /// Reads the app's own stored copy. Never throws: failures become `.unreadable` with a short reason.
    /// `textByteLimit` bounds UTF-8 bytes of returned text (cut at a character boundary; `truncated` = true when cut).
    static func read(fileURL: URL, kind: ChatAttachmentKind, contentType: String?, textByteLimit: Int) -> ChatAttachmentReadResult {
        // Bounded so the read-window arithmetic below cannot overflow.
        let limit = min(max(0, textByteLimit), Int(Int32.max))
        return ChatAttachmentReadResult(content: content(of: fileURL, kind: kind, contentType: contentType, limit: limit))
    }

    private static func content(of url: URL, kind: ChatAttachmentKind, contentType: String?,
                                limit: Int) -> ChatAttachmentReadResult.Content {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .unreadable(ChatAttachmentText.missing)
        }
        let folder = isDirectory.boolValue
        let named = url.pathExtension.isEmpty ? nil
            : UTType(filenameExtension: url.pathExtension.lowercased(), conformingTo: folder ? .package : .data)
        let types = [contentType.flatMap { UTType($0) }, named].compactMap { $0 }
        func conforms(_ type: UTType) -> Bool { types.contains { $0.conforms(to: type) } }

        // An RTFD document is a package; no other folder has content to read.
        if folder {
            guard conforms(.rtfd) else { return .unreadable(ChatAttachmentText.notText) }
            return richText(url, type: .rtfd, limit: limit) ?? .unreadable(ChatAttachmentText.fileFailed)
        }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value else {
            return .unreadable(ChatAttachmentText.fileFailed)
        }
        guard size <= maxFileBytes else { return .unreadable(ChatAttachmentText.fileTooLarge) }
        guard let head = leadingBytes(of: url) else { return .unreadable(ChatAttachmentText.fileFailed) }

        if conforms(.pdf) || head.starts(with: Data("%PDF-".utf8)) { return pdf(url, limit: limit) }
        if kind == .photo || conforms(.image) {
            let picture = image(url)
            // ImageIO cannot draw every image type; SVG, for one, is text a model can still read.
            if kind == .file, picture == .unreadable(ChatAttachmentText.imageFailed) {
                let text = plainText(url, limit: limit)
                if case .text = text { return text }
            }
            return picture
        }
        let rtfd = conforms(.rtfd) || conforms(.flatRTFD)
        if rtfd || conforms(.rtf) || head.starts(with: Data(#"{\rtf"#.utf8)),
           let text = richText(url, type: rtfd ? .rtfd : .rtf, limit: limit) {
            return text
        }
        // RTF that does not parse is still readable as its source.
        return plainText(url, limit: limit)
    }

    private static func image(_ url: URL) -> ChatAttachmentReadResult.Content {
        let failed = ChatAttachmentReadResult.Content.unreadable(ChatAttachmentText.imageFailed)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return failed }
        // The primary image of a HEIF collection; the first frame of a GIF.
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return failed }
        guard width <= maxDecodedSide, height <= maxDecodedSide, width * height <= maxDecodedPixels else {
            return .unreadable(ChatAttachmentText.imageTooLarge)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            // Never upscale a small picture.
            kCGImageSourceThumbnailMaxPixelSize: min(imageMaxPixelSize, max(width, height)),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary),
              let picture = opaque(thumbnail) else { return failed }
        for quality in [0.8, 0.6] {
            guard let jpeg = jpeg(picture, quality: quality) else { return failed }
            if jpeg.count <= maxImageBytes {
                return .image(jpeg: jpeg, pixelWidth: picture.width, pixelHeight: picture.height)
            }
        }
        return .unreadable(ChatAttachmentText.imageTooLarge)
    }

    /// JPEG has no alpha, and transparent pixels would turn black and hide dark
    /// text on a transparent screenshot; CMYK or Lab pictures also become sRGB.
    private static func opaque(_ image: CGImage) -> CGImage? {
        let model = image.colorSpace?.model
        if [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), model == .rgb || model == .monochrome {
            return image
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    /// Encoding a bare CGImage also leaves the original's EXIF and location behind.
    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func pdf(_ url: URL, limit: Int) -> ChatAttachmentReadResult.Content {
        guard let document = PDFDocument(url: url) else { return .unreadable(ChatAttachmentText.pdfFailed) }
        guard !document.isLocked else { return .unreadable(ChatAttachmentText.pdfLocked) }
        guard document.pageCount > 0 else { return .unreadable(ChatAttachmentText.pdfFailed) }
        var output = ""
        var found = false
        var truncated = false
        for index in 0..<document.pageCount {
            let page = normalizedLineEnds(document.page(at: index)?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Pages without text get no header, so a scan never becomes a column of page numbers.
            guard !page.isEmpty else { continue }
            found = true
            let header = (output.isEmpty ? "" : "\n\n") + "— 第 \(index + 1) 頁 —\n"
            let room = limit - output.utf8.count - header.utf8.count
            let kept = room > 0 ? prefix(page, utf8Limit: room) : ""
            if !kept.isEmpty { output += header + kept }
            if kept.utf8.count < page.utf8.count { truncated = true; break }
        }
        return found ? .text(output, truncated: truncated) : .unreadable(ChatAttachmentText.pdfNoText)
    }

    /// UIFoundation's importer: iOS declares it in UIKit and macOS in AppKit, and
    /// both arrive here through PDFKit. RTF, unlike HTML, imports off the main thread.
    private static func richText(_ url: URL, type: NSAttributedString.DocumentType,
                                 limit: Int) -> ChatAttachmentReadResult.Content? {
        guard let document = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        else { return nil }
        // Embedded pictures leave U+FFFC placeholders that carry no text.
        let text = normalizedLineEnds(document.string.replacingOccurrences(of: "\u{FFFC}", with: ""))
        let kept = prefix(text, utf8Limit: limit)
        return .text(String(kept), truncated: kept.utf8.count < text.utf8.count)
    }

    private static func plainText(_ url: URL, limit: Int) -> ChatAttachmentReadResult.Content {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable(ChatAttachmentText.fileFailed) }
        defer { try? handle.close() }
        // 4 bytes finish a character cut at the limit; the sniff looks further for binary.
        let window = limit + 4 + sniffBytes
        guard var data = try? bytes(from: handle, upTo: window) else { return .unreadable(ChatAttachmentText.fileFailed) }
        let bigEndian: Bool? = data.starts(with: [0xFE, 0xFF]) ? true : data.starts(with: [0xFF, 0xFE]) ? false : nil
        if bigEndian != nil, data.count == window {
            // UTF-16 spends two bytes on each ASCII character.
            guard let more = try? bytes(from: handle, upTo: limit) else { return .unreadable(ChatAttachmentText.fileFailed) }
            data.append(more)
        }
        guard let next = try? bytes(from: handle, upTo: 1) else { return .unreadable(ChatAttachmentText.fileFailed) }
        let decoded = if let bigEndian { utf16(data.dropFirst(2), bigEndian: bigEndian) } else { utf8(data) }
        guard let decoded else { return .unreadable(ChatAttachmentText.notText) }
        let text = String(decoding: droppingCarriageReturnsBeforeLineFeeds(decoded), as: UTF8.self)
        let kept = prefix(text, utf8Limit: limit)
        return .text(String(kept), truncated: kept.utf8.count < text.utf8.count || !next.isEmpty)
    }

    /// Valid UTF-8 without NUL, minus a BOM and a final character the bounded read may have cut.
    private static func utf8(_ data: Data) -> [UInt8]? {
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        guard !bytes.contains(0) else { return nil }
        bytes.removeLast(incompleteTailCount(bytes))
        let invalid = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF8.self, stoppingOnError: true) { _ in }
        return invalid ? nil : bytes
    }

    /// UTF-16 (after its BOM) as UTF-8; NUL, which UTF-32 read as UTF-16 produces, is not text.
    private static func utf16(_ payload: Data, bigEndian: Bool) -> [UInt8]? {
        var units: [UInt16] = []
        units.reserveCapacity(payload.count / 2)
        var index = payload.startIndex
        while index + 1 < payload.endIndex {
            let first = UInt16(payload[index]), second = UInt16(payload[index + 1])
            units.append(bigEndian ? first << 8 | second : second << 8 | first)
            index += 2
        }
        // The bounded read can end inside a surrogate pair.
        if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(units.count * 3)
        let invalid = transcode(units.makeIterator(), from: UTF16.self, to: UTF8.self, stoppingOnError: true) {
            bytes.append($0)
        }
        return invalid || bytes.contains(0) ? nil : bytes
    }

    /// Length of a multi-byte sequence left unfinished at the end.
    private static func incompleteTailCount(_ bytes: [UInt8]) -> Int {
        var start = bytes.count
        while start > 0, bytes.count - start < 4 {
            start -= 1
            let byte = bytes[start]
            guard byte & 0xC0 == 0x80 else {
                let length: Int
                switch byte {
                case 0xC2...0xDF: length = 2
                case 0xE0...0xEF: length = 3
                case 0xF0...0xF4: length = 4
                default: return 0   // ASCII is complete; an invalid lead byte fails validation
                }
                return bytes.count - start < length ? bytes.count - start : 0
            }
        }
        return 0
    }

    /// CR and LF never occur inside a multi-byte UTF-8 sequence, so bytes are safe to edit.
    private static func droppingCarriageReturnsBeforeLineFeeds(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.contains(0x0D) else { return bytes }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        for (index, byte) in bytes.enumerated()
        where !(byte == 0x0D && index + 1 < bytes.count && bytes[index + 1] == 0x0A) {
            result.append(byte)
        }
        return result
    }

    /// PDF and RTF importers can hand back CRLF or bare CR line ends.
    private static func normalizedLineEnds(_ text: String) -> String {
        guard text.utf8.contains(0x0D) else { return text }
        // "\r\n" is a single Character, so this never splits one.
        return String(text.lazy.map { $0 == "\r\n" || $0 == "\r" ? "\n" : $0 })
    }

    /// The longest prefix within `limit` UTF-8 bytes that ends on a Character
    /// boundary, so a cut never splits a letter, an emoji or an accent.
    private static func prefix(_ text: String, utf8Limit limit: Int) -> Substring {
        let utf8 = text.utf8
        guard utf8.count > limit else { return text[...] }
        var end = utf8.index(utf8.startIndex, offsetBy: limit)
        while end > text.startIndex, end.samePosition(in: text) == nil { end = utf8.index(before: end) }
        return text[..<end]
    }

    private static func leadingBytes(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? bytes(from: handle, upTo: 8)
    }

    private static func bytes(from handle: FileHandle, upTo count: Int) throws -> Data {
        var data = Data()
        while data.count < count, let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty {
            data.append(chunk)
        }
        return data
    }
}

/// Sizes as Android writes them on attachment cards and message lines.
enum ChatAttachmentFormat {
    static func byteString(_ n: Int64) -> String {
        let bytes = max(0, n)
        if bytes < 1024 { return "\(bytes) B" }
        // Android rounds to the nearest KB: (bytes + 512) / 1024.
        if bytes < 1 << 20 { return "\((bytes + 512) / 1024) KB" }
        // Android's "%.1f" rounds half up; integer tenths keep that exact and locale-free.
        let mebibyte: Int64 = 1 << 20
        let tenths = bytes / mebibyte * 10 + (bytes % mebibyte * 10 + mebibyte / 2) / mebibyte
        return "\(tenths / 10).\(tenths % 10) MB"
    }
}
