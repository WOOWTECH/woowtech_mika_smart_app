import CoreGraphics
import Foundation
import ImageIO

/// Bounds the raster before forcing a complete decode into an RGBA bitmap.
/// This checks integrity and resource use, not the semantic content of a photo.
public struct ImageIOAttachmentValidator: ChatAttachmentImageValidating {
    public static let maximumDimension = 8192
    public static let maximumPixels = 20_000_000
    public static let maximumDecodedBytes = 80_000_000
    public init() {}

    public func validate(data: Data, mimeType: String) throws {
        // Require complete container trailers rather than accepting ImageIO's
        // sometimes permissive recovery of truncated sources. This deliberately
        // rejects files with arbitrary bytes after JPEG EOI or PNG IEND.
        let trailer: [UInt8] = mimeType == "image/png"
            ? [0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]
            : [0xff, 0xd9]
        guard mimeType == "image/png" || mimeType == "image/jpeg",
              data.suffix(trailer.count).elementsEqual(trailer),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let actualType = CGImageSourceGetType(source) as String?,
              actualType == (mimeType == "image/png" ? "public.png" : "public.jpeg"),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw ChatAttachmentImportError.invalidFormat }
        guard width <= Self.maximumDimension, height <= Self.maximumDimension,
              width <= Self.maximumPixels / height else { throw ChatAttachmentImportError.imageTooLarge }
        let options = [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options), image.width == width, image.height == height,
              image.bytesPerRow > 0, image.bytesPerRow <= Self.maximumDecodedBytes / height else {
            throw ChatAttachmentImportError.invalidFormat
        }
        // ImageIO may create an image object lazily. Reading the provider's
        // entire decoded buffer before drawing forces pixel decompression.
        guard let pixels = image.dataProvider?.data,
              CFDataGetLength(pixels) >= image.bytesPerRow * height,
              CFDataGetLength(pixels) <= Self.maximumDecodedBytes,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ChatAttachmentImportError.invalidFormat
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard context.data != nil, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw ChatAttachmentImportError.invalidFormat
        }
    }
}
