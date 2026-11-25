import Foundation

public struct PresentationSlide: Equatable, Sendable {
    public let title: String
    public let bullets: [String]
    public init(title: String, bullets: [String]) { self.title = title; self.bullets = bullets }
}

/// A PowerPoint deck (.pptx), 16:9, each slide a title and bullet points. The
/// package is the smallest PowerPoint opens without repair: one master, one
/// "Title and Content" layout and a plain theme, kept here as fixed text; the
/// slides take their places and bullets from them.
public enum PresentationWriter {
    static let namespaces = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="\#(OfficePackage.officeRelationships)" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#

    public static func pptx(title: String, slides: [PresentationSlide], modified: Date = Date()) throws -> Data {
        guard !slides.isEmpty, slides.count <= DocumentCreationLimits.maximumSlides else { throw DocumentCreationError.tooManySlides }
        let main = "application/vnd.openxmlformats-officedocument.presentationml"
        let relation = OfficePackage.officeRelationships + "/"
        var overrides: [(part: String, type: String)] = [
            ("/ppt/presentation.xml", main + ".presentation.main+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", main + ".slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", main + ".slideLayout+xml"),
        ]
        overrides += slides.indices.map { ("/ppt/slides/slide\($0 + 1).xml", main + ".slide+xml") }
        overrides += [("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
                      ("/ppt/presProps.xml", main + ".presProps+xml"), ("/ppt/viewProps.xml", main + ".viewProps+xml"),
                      ("/ppt/tableStyles.xml", main + ".tableStyles+xml"), ("/docProps/core.xml", OfficePackage.coreType)]
        var relationships: [(id: String, type: String, target: String)] = [("rId1", relation + "slideMaster", "slideMasters/slideMaster1.xml")]
        relationships += slides.indices.map { ("rId\($0 + 2)", relation + "slide", "slides/slide\($0 + 1).xml") }
        let next = slides.count + 2
        relationships += [("rId\(next)", relation + "presProps", "presProps.xml"), ("rId\(next + 1)", relation + "viewProps", "viewProps.xml"),
                          ("rId\(next + 2)", relation + "theme", "theme/theme1.xml"), ("rId\(next + 3)", relation + "tableStyles", "tableStyles.xml")]
        let presentation = OfficePackage.declaration + "<p:presentation \(namespaces) saveSubsetFonts=\"1\">"
            + #"<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>"#
            + slides.indices.map { #"<p:sldId id="\#(256 + $0)" r:id="rId\#($0 + 2)"/>"# }.joined()
            + #"</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#
        var parts: [(name: String, xml: String)] = [
            ("[Content_Types].xml", OfficePackage.contentTypes(overrides)),
            ("_rels/.rels", OfficePackage.rootRelationships(main: "ppt/presentation.xml")),
            ("ppt/presentation.xml", presentation),
            ("ppt/_rels/presentation.xml.rels", OfficePackage.relationships(relationships)),
            ("ppt/slideMasters/slideMaster1.xml", master),
            ("ppt/slideMasters/_rels/slideMaster1.xml.rels", OfficePackage.relationships([
                ("rId1", relation + "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", relation + "theme", "../theme/theme1.xml")])),
            ("ppt/slideLayouts/slideLayout1.xml", layout),
            ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", OfficePackage.relationships([
                ("rId1", relation + "slideMaster", "../slideMasters/slideMaster1.xml")])),
        ]
        for (index, slide) in slides.enumerated() {
            try Task.checkCancellation()
            parts.append((name: "ppt/slides/slide\(index + 1).xml", xml: try self.slide(slide)))
            parts.append((name: "ppt/slides/_rels/slide\(index + 1).xml.rels", xml: OfficePackage.relationships([
                ("rId1", relation + "slideLayout", "../slideLayouts/slideLayout1.xml")])))
        }
        parts += [("ppt/theme/theme1.xml", theme),
                  ("ppt/presProps.xml", OfficePackage.declaration + "<p:presentationPr \(namespaces)/>"),
                  ("ppt/viewProps.xml", OfficePackage.declaration + "<p:viewPr \(namespaces)/>"),
                  ("ppt/tableStyles.xml", OfficePackage.declaration
                    + #"<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>"#),
                  ("docProps/core.xml", try OfficePackage.coreProperties(title: title, created: modified))]
        return try OfficePackage.package(parts, modified: modified)
    }

    static func slide(_ slide: PresentationSlide) throws -> String {
        // Sizes in hundredths of a point; the boxes are the master's, less their insets.
        let titleSize = fittedSize([slide.title], width: 813, height: 97, largest: 4_000, smallest: 2_000, gap: 0)
        var xml = OfficePackage.declaration + "<p:sld \(namespaces)><p:cSld><p:spTree>" + group
            + placeholder(id: 2, name: "Title 1", kind: #"type="title""#,
                          paragraphs: [try paragraph(slide.title, size: titleSize < 4_000 ? titleSize : nil)])
        if !slide.bullets.isEmpty {
            let size = fittedSize(slide.bullets, width: 795, height: 335, largest: 2_400, smallest: 1_200, gap: 10)
            xml += placeholder(id: 3, name: "Content Placeholder 2", kind: #"idx="1""#,
                               paragraphs: try slide.bullets.map { try paragraph($0, size: size < 2_400 ? size : nil) })
        }
        return xml + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
    }

    /// One paragraph; a line break inside it stays a line break.
    static func paragraph(_ text: String, size: Int? = nil) throws -> String {
        let properties = size.map { #"<a:rPr sz="\#($0)"/>"# } ?? ""
        let lines = try OfficePackage.lines(text).components(separatedBy: "\n").map { line in
            line.isEmpty ? "" : "<a:r>" + properties + "<a:t>" + (try OfficePackage.escaped(line)) + "</a:t></a:r>"
        }
        return "<a:p>" + lines.joined(separator: "<a:br/>") + "</a:p>"
    }

    /// The largest size, in steps of 2 points, at which the paragraphs fit a
    /// box `width` by `height` points, estimated from their characters: a wide
    /// character a size across, others about half. Quick Look and Keynote do
    /// not shrink text to fit as PowerPoint can, so a full slide is set smaller.
    static func fittedSize(_ paragraphs: [String], width: Double, height: Double,
                           largest: Int, smallest: Int, gap: Double) -> Int {
        var size = largest
        while size > smallest {
            let points = Double(size) / 100
            let lines = paragraphs.reduce(0) { total, text in
                total + OfficePackage.lines(text).components(separatedBy: "\n").reduce(0) { count, line in
                    let units = line.unicodeScalars.reduce(0.0) { $0 + ($1.value > 0x2E7F ? 1 : 0.55) }
                    return count + max(1, Int((units * points / width).rounded(.up)))
                }
            }
            if Double(lines) * points * 1.1 + Double(paragraphs.count) * gap <= height { break }
            size -= 200
        }
        return size
    }

    static func placeholder(id: Int, name: String, kind: String, paragraphs: [String], frame: String = "") -> String {
        #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="\#(name)"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph \#(kind)/></p:nvPr></p:nvSpPr>"#
            + (frame.isEmpty ? "<p:spPr/>" : "<p:spPr>" + frame + "</p:spPr>")
            + "<p:txBody><a:bodyPr><a:normAutofit/></a:bodyPr><a:lstStyle/>" + paragraphs.joined() + "</p:txBody></p:sp>"
    }

    static let group = #"<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"#
        + #"<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>"#

    static func frame(x: Int, y: Int, width: Int, height: Int) -> String {
        #"<a:xfrm><a:off x="\#(x)" y="\#(y)"/><a:ext cx="\#(width)" cy="\#(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>"#
    }

    /// Where the title and the bullets sit, and how they look: a bullet glyph,
    /// theme fonts and sizes, in black on white.
    static let master = OfficePackage.declaration + "<p:sldMaster \(namespaces)><p:cSld>"
        + #"<p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>"# + group
        + placeholder(id: 2, name: "Title Placeholder 1", kind: #"type="title""#, paragraphs: ["<a:p/>"],
                      frame: frame(x: 838_200, y: 365_125, width: 10_515_600, height: 1_325_563))
        + placeholder(id: 3, name: "Text Placeholder 2", kind: #"type="body" idx="1""#, paragraphs: ["<a:p/>"],
                      frame: frame(x: 838_200, y: 1_825_625, width: 10_515_600, height: 4_351_338))
        + "</p:spTree></p:cSld>"
        + #"<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>"#
        + #"<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles>"#
        + #"<p:titleStyle><a:lvl1pPr algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef><a:buNone/><a:defRPr sz="4000" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/><a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr></p:titleStyle>"#
        + #"<p:bodyStyle><a:lvl1pPr marL="228600" indent="-228600" algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPts val="1000"/></a:spcBef><a:buFont typeface="Arial"/><a:buChar char="•"/><a:defRPr sz="2400" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:bodyStyle>"#
        + #"<p:otherStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr></p:otherStyle></p:txStyles></p:sldMaster>"#

    static let layout = OfficePackage.declaration + "<p:sldLayout \(namespaces) type=\"obj\" preserve=\"1\">"
        + #"<p:cSld name="Title and Content"><p:spTree>"# + group
        + placeholder(id: 2, name: "Title 1", kind: #"type="title""#, paragraphs: ["<a:p/>"])
        + placeholder(id: 3, name: "Content Placeholder 2", kind: #"idx="1""#, paragraphs: ["<a:p/>"])
        + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    /// Office's colors and fonts; three plain fills, lines and effects each, as the schema requires.
    static let theme: String = {
        let colors = [("dk2", "44546A"), ("lt2", "E7E6E6"), ("accent1", "4472C4"), ("accent2", "ED7D31"), ("accent3", "A5A5A5"),
                      ("accent4", "FFC000"), ("accent5", "5B9BD5"), ("accent6", "70AD47"), ("hlink", "0563C1"), ("folHlink", "954F72")]
            .map { #"<a:\#($0.0)><a:srgbClr val="\#($0.1)"/></a:\#($0.0)>"# }.joined()
        let fill = #"<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>"#
        let lines = [6350, 12700, 19050].map { #"<a:ln w="\#($0)" cap="flat" cmpd="sng" algn="ctr">\#(fill)<a:prstDash val="solid"/></a:ln>"# }.joined()
        return OfficePackage.declaration + #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme"><a:themeElements>"#
            + #"<a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>"#
            + colors + "</a:clrScheme>"
            + #"<a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>"#
            + #"<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>"#
            + #"<a:fmtScheme name="Office"><a:fillStyleLst>"# + String(repeating: fill, count: 3) + "</a:fillStyleLst>"
            + "<a:lnStyleLst>" + lines + "</a:lnStyleLst>"
            + "<a:effectStyleLst>" + String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3) + "</a:effectStyleLst>"
            + "<a:bgFillStyleLst>" + String(repeating: fill, count: 3) + "</a:bgFillStyleLst></a:fmtScheme>"
            + "</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }()
}
