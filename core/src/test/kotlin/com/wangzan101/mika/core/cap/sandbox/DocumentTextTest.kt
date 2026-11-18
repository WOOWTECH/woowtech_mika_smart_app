package com.wangzan101.mika.core.cap.sandbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** 只有文件的工作区(商店版)读 PDF、Word、Excel、PowerPoint 的文字层:不跑任何脚本,纯 Kotlin。 */
class DocumentTextTest {
    private fun latin(s: String) = s.toByteArray(Charsets.ISO_8859_1)

    private fun deflate(data: ByteArray): ByteArray {
        val d = Deflater()
        d.setInput(data)
        d.finish()
        val out = ByteArrayOutputStream()
        val buf = ByteArray(4096)
        while (!d.finished()) out.write(buf, 0, d.deflate(buf))
        d.end()
        return out.toByteArray()
    }

    private fun stream(dict: String, data: ByteArray): ByteArray =
        latin("<< $dict /Length ${data.size} >>\nstream\n") + data + latin("\nendstream")

    /** 一份 PDF:(对象号, 内容) 依次写出,最后是 trailer。 */
    private fun pdf(objects: List<Pair<Int, ByteArray>>, trailer: String = "<< /Root 1 0 R >>"): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(latin("%PDF-1.7\n%âãÏÓ\n"))
        for ((num, body) in objects) {
            out.write(latin("$num 0 obj\n"))
            out.write(body)
            out.write(latin("\nendobj\n"))
        }
        out.write(latin("trailer\n$trailer\nstartxref\n0\n%%EOF\n"))
        return out.toByteArray()
    }

    private fun text(r: DocumentText.Result): String {
        assertTrue("expected text, got ${(r as? DocumentText.Result.Unreadable)?.code}", r is DocumentText.Result.Text)
        return (r as DocumentText.Result.Text).text
    }

    @Test fun pdfPagesInPageTreeOrderWithInheritedFonts() {
        val page1 = latin("BT /F1 12 Tf 72 720 Td (Hello, world) Tj 0 -14 Td (Second line) Tj ET")
        val page2 = latin("BT /F1 12 Tf 1 0 0 1 72 720 Tm [(Pa) 20 (ge) -400 (two)] TJ ET")
        val bytes = pdf(listOf(
            1 to latin("<< /Type /Catalog /Pages 2 0 R >>"),
            2 to latin("<< /Type /Pages /Kids [4 0 R 3 0 R] /Count 2 /Resources << /Font << /F1 5 0 R >> >> >>"),
            3 to latin("<< /Type /Page /Parent 2 0 R /Contents 7 0 R >>"),
            4 to latin("<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>"),
            5 to latin("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"),
            6 to stream("", page1),
            7 to stream("/Filter /FlateDecode", deflate(page2)),
        ))
        val r = DocumentText.extract(bytes, DocumentText.Type.Pdf)
        assertEquals("--- page 1 ---\nHello, world\nSecond line\n\n--- page 2 ---\nPage two", text(r))
        assertEquals(2, (r as DocumentText.Result.Text).count)
        assertEquals("pages", r.unit)
    }

    @Test fun pdfChineseTextThroughToUnicodeInAnObjectStream() {
        val cmap = latin("""
            /CIDInit /ProcSet findresource begin
            12 dict begin
            begincmap
            /CMapName /Test-UCS def
            1 begincodespacerange
            <0000> <FFFF>
            endcodespacerange
            2 beginbfchar
            <0001> <4E2D>
            <0002> <6587>
            endbfchar
            1 beginbfrange
            <0010> <0012> <0041>
            endbfrange
            endcmap
            CMapName currentdict /CMap defineresource pop
            end
            end
        """.trimIndent())
        val content = latin("BT /F2 10 Tf 50 700 Td <00010002> Tj 0 -12 Td <001000110012> Tj ET")
        val packed = listOf(
            2 to "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            3 to "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F2 4 0 R >> >> /Contents 5 0 R >>",
            4 to "<< /Type /Font /Subtype /Type0 /BaseFont /NotoSansTC /Encoding /Identity-H /ToUnicode 6 0 R >>",
        )
        val body = StringBuilder()
        val header = StringBuilder()
        for ((num, text) in packed) {
            header.append(num).append(' ').append(body.length).append(' ')
            body.append(text).append('\n')
        }
        val objStm = latin(header.toString()) + latin(body.toString())
        val bytes = pdf(listOf(
            1 to latin("<< /Type /Catalog /Pages 2 0 R >>"),
            5 to stream("/Filter /FlateDecode", deflate(content)),
            6 to stream("", cmap),
            7 to stream("/Type /ObjStm /N 3 /First ${header.length} /Filter /FlateDecode", deflate(objStm)),
        ))
        assertEquals("--- page 1 ---\n中文\nABC", text(DocumentText.extract(bytes, DocumentText.Type.Pdf)))
    }

    @Test fun pdfWithoutTextIsAScanAndEncryptedPdfIsRefused() {
        val image = latin("q 100 0 0 100 0 0 cm /Im1 Do Q")
        fun doc(pages: List<ByteArray>, trailer: String = "<< /Root 1 0 R >>"): ByteArray {
            val kids = pages.indices.joinToString(" ") { "${10 + it} 0 R" }
            val objects = mutableListOf(
                1 to latin("<< /Type /Catalog /Pages 2 0 R >>"),
                2 to latin("<< /Type /Pages /Kids [$kids] /Count ${pages.size} >>"),
                3 to latin("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"),
                4 to stream("/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", byteArrayOf(0)),
            )
            pages.forEachIndexed { i, c ->
                objects += (10 + i) to latin("<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 3 0 R >> /XObject << /Im1 4 0 R >> >> /Contents ${20 + i} 0 R >>")
                objects += (20 + i) to stream("", c)
            }
            return pdf(objects, trailer)
        }
        val scan = DocumentText.extract(doc(listOf(image, image)), DocumentText.Type.Pdf)
        assertEquals("document_no_text", (scan as DocumentText.Result.Unreadable).code)
        val mixed = text(DocumentText.extract(doc(listOf(latin("BT /F1 9 Tf 10 10 Td (Cover) Tj ET"), image)), DocumentText.Type.Pdf))
        assertEquals("--- page 1 ---\nCover\n\n--- page 2 ---\n(no text on this page)", mixed)
        val locked = DocumentText.extract(doc(listOf(image), "<< /Root 1 0 R /Encrypt 9 0 R >>"), DocumentText.Type.Pdf)
        assertEquals("document_encrypted", (locked as DocumentText.Result.Unreadable).code)
    }

    private fun zip(vararg entries: Pair<String, String>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            for ((name, text) in entries) {
                z.putNextEntry(ZipEntry(name))
                z.write(text.toByteArray(Charsets.UTF_8))
                z.closeEntry()
            }
        }
        return out.toByteArray()
    }

    @Test fun wordParagraphsTablesAndTabsButNotDeletedText() {
        val document = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
            <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:t>報價單</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Total: </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>NT${'$'}1,200</w:t></w:r><w:r><w:tab/><w:t>&amp; tax</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Item</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Qty</w:t></w:r></w:p></w:tc></w:tr>
            <w:tr><w:tc><w:p><w:r><w:t>Apple</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>3</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:r><w:delText>removed</w:delText></w:r></w:p>
            </w:body></w:document>"""
        val r = DocumentText.extract(zip("[Content_Types].xml" to "<Types/>", "word/document.xml" to document), DocumentText.Type.Docx)
        assertEquals("報價單\nTotal: NT$1,200\t& tax\nItem\tQty\nApple\t3", text(r))
        assertEquals(7, (r as DocumentText.Result.Text).count)
    }

    @Test fun excelSheetsInWorkbookOrderWithSharedInlineAndBooleanCells() {
        val rels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        val r = DocumentText.extract(zip(
            "xl/workbook.xml" to """<workbook xmlns:r="$rels"><sheets><sheet name="報價" sheetId="1" r:id="rId1"/><sheet name="Notes" sheetId="2" r:id="rId2"/></sheets></workbook>""",
            "xl/_rels/workbook.xml.rels" to """<Relationships><Relationship Id="rId2" Type="$rels/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId1" Type="$rels/worksheet" Target="worksheets/sheet1.xml"/></Relationships>""",
            "xl/sharedStrings.xml" to """<sst count="3"><si><t>Item</t></si><si><r><t>Qty</t></r></si><si><t>蘋果</t><rPh sb="0" eb="1"><t>ping</t></rPh></si></sst>""",
            "xl/worksheets/sheet1.xml" to """<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>3.5</v></c></row><row r="3"><c r="A3" t="inlineStr"><is><t>Inline</t></is></c><c r="B3" t="b"><v>1</v></c><c r="D3"><f>SUM(B1:B2)</f><v>7</v></c></row></sheetData></worksheet>""",
            "xl/worksheets/sheet2.xml" to """<worksheet><sheetData><row r="1"><c r="A1" t="str"><v>note &lt;ok&gt;</v></c></row></sheetData></worksheet>""",
        ), DocumentText.Type.Xlsx)
        assertEquals("--- sheet 報價 ---\nItem\tQty\n蘋果\t\t3.5\nInline\tTRUE\t\t7\n\n--- sheet Notes ---\nnote <ok>", text(r))
        assertEquals(2, (r as DocumentText.Result.Text).count)
    }

    @Test fun powerPointSlidesInPresentationOrder() {
        val rels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        fun slide(body: String) = """<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:txBody>$body</p:txBody></p:sp></p:spTree></p:cSld></p:sld>"""
        val r = DocumentText.extract(zip(
            "ppt/presentation.xml" to """<p:presentation xmlns:p="p" xmlns:r="$rels"><p:sldIdLst><p:sldId id="256" r:id="rId3"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst></p:presentation>""",
            "ppt/_rels/presentation.xml.rels" to """<Relationships><Relationship Id="rId2" Target="slides/slide1.xml"/><Relationship Id="rId3" Target="slides/slide2.xml"/></Relationships>""",
            "ppt/slides/slide1.xml" to slide("<a:p><a:r><a:t>Second</a:t></a:r></a:p>"),
            "ppt/slides/slide2.xml" to slide("<a:p><a:r><a:t>Title</a:t></a:r><a:br/><a:r><a:t>Subtitle</a:t></a:r></a:p><a:p><a:r><a:t>Point</a:t></a:r></a:p>"),
        ), DocumentText.Type.Pptx)
        assertEquals("--- slide 1 ---\nTitle\nSubtitle\nPoint\n\n--- slide 2 ---\nSecond", text(r))
    }

    @Test fun olderAndDamagedFilesSayWhyTheyCannotBeRead() {
        assertEquals(DocumentText.Type.Doc, DocumentText.typeOf("DOC"))
        assertEquals("document_old_format", (DocumentText.extract(ByteArray(8), DocumentText.Type.Doc) as DocumentText.Result.Unreadable).code)
        assertEquals("document_unreadable", (DocumentText.extract(latin("not a zip"), DocumentText.Type.Docx) as DocumentText.Result.Unreadable).code)
        assertEquals("document_unreadable", (DocumentText.extract(latin("%PDF-1.4 nothing"), DocumentText.Type.Pdf) as DocumentText.Result.Unreadable).code)
    }
}
