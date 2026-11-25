import Foundation

/// What the Word, Excel and PowerPoint writers share: XML text, and the parts
/// every Office Open XML package has. Each package is a ZIP (DocumentZipWriter)
/// whose first entry is [Content_Types].xml.
enum OfficePackage {
    static let declaration = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
    static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let officeRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    /// Text for an element or an attribute. XML 1.0 cannot carry NUL and the
    /// other C0 controls but tab, line feed and carriage return; such text is
    /// refused, never stripped.
    static func escaped(_ text: String) throws -> String {
        guard isXMLText(text) else { throw DocumentCreationError.invalidText }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func isXMLText(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            (scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13)
                || scalar.value == 127 || scalar.value == 0xFFFE || scalar.value == 0xFFFF
        }
    }

    /// One line ending, so a carriage return never reaches a part as text.
    static func lines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func contentTypes(_ overrides: [(part: String, type: String)]) -> String {
        declaration + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + overrides.map { #"<Override PartName="\#($0.part)" ContentType="\#($0.type)"/>"# }.joined()
            + "</Types>"
    }

    /// Targets are package paths written by the writers, never model text.
    static func relationships(_ items: [(id: String, type: String, target: String)]) -> String {
        declaration + #"<Relationships xmlns="\#(packageRelationships)">"#
            + items.map { #"<Relationship Id="\#($0.id)" Type="\#($0.type)" Target="\#($0.target)"/>"# }.joined()
            + "</Relationships>"
    }

    /// The package's root relationships: the main part, then the core properties.
    static func rootRelationships(main: String) -> String {
        relationships([("rId1", officeRelationships + "/officeDocument", main),
                       ("rId2", packageRelationships + "/metadata/core-properties", "docProps/core.xml")])
    }

    static let coreType = "application/vnd.openxmlformats-package.core-properties+xml"

    /// The title and the time the file was made.
    static func coreProperties(title: String, created: Date) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let time = formatter.string(from: created)
        return declaration + #"<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">"#
            + "<dc:title>" + (try escaped(title)) + "</dc:title>"
            + #"<dcterms:created xsi:type="dcterms:W3CDTF">\#(time)</dcterms:created>"#
            + #"<dcterms:modified xsi:type="dcterms:W3CDTF">\#(time)</dcterms:modified>"#
            + "</cp:coreProperties>"
    }

    /// Writes the parts in order; [Content_Types].xml comes first by convention.
    static func package(_ parts: [(name: String, xml: String)], modified: Date) throws -> Data {
        var zip = DocumentZipWriter(modified: modified)
        for part in parts {
            try Task.checkCancellation()
            try zip.add(part.name, Data(part.xml.utf8))
        }
        let data = try zip.archive()
        guard data.count <= DocumentCreationLimits.maximumOutputBytes else { throw DocumentCreationError.tooLarge }
        return data
    }
}

/// Text built a piece at a time within the output limit, like DocumentOutput.
struct OfficeXMLOutput {
    private(set) var value = ""
    private var bytes = 0

    init(_ start: String = "") { value = start; bytes = start.utf8.count }

    mutating func append(_ text: String) throws {
        let count = text.utf8.count
        // The parts are compressed later; the XML itself may be a few times the file.
        guard count <= 4 * DocumentCreationLimits.maximumOutputBytes - bytes else { throw DocumentCreationError.tooLarge }
        value += text
        bytes += count
    }
}
