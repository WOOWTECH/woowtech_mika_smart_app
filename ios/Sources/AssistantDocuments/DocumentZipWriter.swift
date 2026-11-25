import Compression
import Foundation

/// A small ZIP writer for the files the assistant creates: a ZIP of the
/// person's files, and the Word, Excel and PowerPoint packages, which are ZIP
/// files of XML. Local headers with the sizes known up front (no data
/// descriptors), a central directory and its end record; raw deflate through
/// the Compression framework, or the bytes stored when deflate does not make
/// them smaller. No ZIP64, encryption, comments or extra fields.
public struct DocumentZipWriter {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data }
    }

    /// Far below the formats' 4 GiB and 65,535-entry limits without ZIP64.
    public static let maximumEntries = 4_096
    public static let maximumInputBytes = 256 * 1_048_576

    private var entries: [Entry] = []
    private var names: Set<String> = []
    private var inputBytes = 0
    private let modified: Date

    /// `modified` is every entry's time, in the device's time zone like other ZIP tools.
    public init(modified: Date = Date()) { self.modified = modified }

    /// A relative name with "/" between folders: never absolute, empty, "." or
    /// "..", and each name once.
    public mutating func add(_ name: String, _ data: Data) throws {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, name.utf8.count <= 1_024, !name.contains("\\"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw DocumentCreationError.invalidEntryName
        }
        guard !names.contains(name) else { throw DocumentCreationError.duplicateEntryName }
        guard entries.count < Self.maximumEntries else { throw DocumentCreationError.tooManyEntries }
        guard data.count <= Self.maximumInputBytes - inputBytes else { throw DocumentCreationError.tooLarge }
        names.insert(name)
        entries.append(Entry(name: name, data: data))
        inputBytes += data.count
    }

    public func archive() throws -> Data {
        var output = Data(), directory = Data()
        let (time, date) = Self.dosTime(modified)
        for entry in entries {
            try Task.checkCancellation()
            let name = Data(entry.name.utf8)
            let crc = DocumentCRC32.checksum(entry.data)
            let deflated = Self.deflate(entry.data)
            let body = deflated ?? entry.data
            let offset = output.count
            guard offset <= Int(UInt32.max) - 30 - name.count - body.count else { throw DocumentCreationError.tooLarge }
            // Bit 11: the name is UTF-8.
            let flags: UInt16 = entry.name.utf8.contains(where: { $0 >= 0x80 }) ? 0x0800 : 0
            let method: UInt16 = deflated == nil ? 0 : 8
            output.appendLE(UInt32(0x0403_4B50))
            output.appendLE(UInt16(20)); output.appendLE(flags); output.appendLE(method)
            output.appendLE(time); output.appendLE(date); output.appendLE(crc)
            output.appendLE(UInt32(body.count)); output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0))
            output.append(name); output.append(body)
            // Made by Unix 2.0, so the external attributes give a regular file, rw-r--r--.
            directory.appendLE(UInt32(0x0201_4B50))
            directory.appendLE(UInt16(0x0314)); directory.appendLE(UInt16(20))
            directory.appendLE(flags); directory.appendLE(method)
            directory.appendLE(time); directory.appendLE(date); directory.appendLE(crc)
            directory.appendLE(UInt32(body.count)); directory.appendLE(UInt32(entry.data.count))
            directory.appendLE(UInt16(name.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0o100644) << 16); directory.appendLE(UInt32(offset))
            directory.append(name)
        }
        guard output.count <= Int(UInt32.max) - directory.count - 22 else { throw DocumentCreationError.tooLarge }
        let start = output.count
        output.append(directory)
        output.appendLE(UInt32(0x0605_4B50))
        output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(directory.count)); output.appendLE(UInt32(start))
        output.appendLE(UInt16(0))
        return output
    }

    /// Raw deflate (RFC 1951), which is what COMPRESSION_ZLIB writes; nil when
    /// it fails or saves nothing, and the entry is stored instead.
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        var output = Data(count: data.count)
        let written = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written
        return output
    }

    /// MS-DOS time and date; years before 1980 cannot be written and become 1980.
    static func dosTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

/// CRC-32 (ISO-HDLC, the ZIP one), by table.
enum DocumentCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { bytes in
                for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8(value >> 8))
    }
    mutating func appendLE(_ value: UInt32) {
        appendLE(UInt16(value & 0xFFFF)); appendLE(UInt16(value >> 16))
    }
}
