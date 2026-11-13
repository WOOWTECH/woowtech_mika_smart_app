#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `-UITestAttachments` puts a generated photo and a short note in the tray,
/// so UI tests exercise the real tray, send and transcript without the system
/// pickers or any of the user's own files.
enum ChatAttachmentUITestFixture {
    static func pickedFiles() -> [ChatPickedFile] {
        [photo(), note()].compactMap { $0 }
    }

    private static func folder() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImports/" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { return nil }
        return url
    }

    private static func photo() -> ChatPickedFile? {
        guard let folder = folder(),
              let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.25, green: 0.41, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        guard let image = context.makeImage() else { return nil }
        let url = folder.appendingPathComponent("fixture-photo.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ChatPickedFile(temporaryURL: url, suggestedName: "fixture-photo.png", contentType: UTType.png.identifier, dedupeKey: nil)
    }

    private static func note() -> ChatPickedFile? {
        guard let folder = folder() else { return nil }
        let url = folder.appendingPathComponent("fixture-notes.txt")
        do { try Data("fixture note: 茶 hello".utf8).write(to: url) } catch { return nil }
        return ChatPickedFile(temporaryURL: url, suggestedName: "fixture-notes.txt", contentType: UTType.plainText.identifier, dedupeKey: nil)
    }
}
#endif
