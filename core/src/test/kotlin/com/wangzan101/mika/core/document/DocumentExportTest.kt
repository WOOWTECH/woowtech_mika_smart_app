package com.wangzan101.mika.core.document

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class DocumentExportTest {
    @Test fun inferredTitleIsPrintedOnceWithoutRemovingOtherHeadings() {
        val source = "# 文件驗收\n\n正文\n\n# 文件驗收\n\n末段"
        val document = DocumentMarkdown.parse("文件驗收", "zh-Hant", source)
        val html = DocumentWriters.html(document)
        assertEquals(2, Regex("<h1>文件驗收</h1>").findAll(html).count())
        assertTrue(html.contains("<p>正文</p>"))
        assertTrue(html.contains("<p>末段</p>"))
        assertEquals(4, document.sections.size)
        val renamed = DocumentWriters.html(document.copy(title = "自訂標題"))
        assertTrue(renamed.contains("<h1>自訂標題</h1>"))
        assertEquals(2, Regex("<h1>文件驗收</h1>").findAll(renamed).count())
        val subsection = DocumentMarkdown.parse("文件驗收", "zh-Hant", "## 文件驗收\n正文")
        assertTrue(DocumentWriters.html(subsection).contains("<h2>文件驗收</h2>"))
    }

    @Test fun chineseMarkdownKeepsSectionsAndLiteralMarkup() {
        val source = "# 台北報告\n\n第一段 **原文**。\n第二行。\n\n- 蘋果\n- 茶\n\n1. 開始\n2. 完成\n\n| 名稱 | 金額 |\n| --- | ---: |\n| 茶 | 25 |"
        val doc = DocumentMarkdown.parse("報告", "zh-Hant", source)
        assertEquals(DocumentSection.Heading(1, "台北報告"), doc.sections[0])
        assertEquals(DocumentSection.Paragraph("第一段 **原文**。\n第二行。"), doc.sections[1])
        assertEquals(DocumentSection.ListSection(listOf("蘋果", "茶"), false), doc.sections[2])
        assertEquals(DocumentSection.ListSection(listOf("開始", "完成"), true), doc.sections[3])
        assertEquals(listOf(listOf("茶", "25")), (doc.sections[4] as DocumentSection.Table).rows)
        val json = Json { encodeDefaults = true }
        val encoded = json.encodeToString(doc)
        assertTrue(encoded.contains("\"schemaVersion\":1"))
        assertTrue(encoded.contains("\"type\":\"table\""))
        assertEquals(doc, json.decodeFromString<DocumentModel>(encoded))
        assertTrue(source.contains("**原文**"))
    }

    @Test fun tablesDoNotSilentlyPadOrDiscardCells() {
        listOf("| 1 |", "| 1 | 2 | 3 |").forEach { row ->
            problem(DocumentProblem.RaggedTable) { DocumentMarkdown.parse("t", "en", "| a | b |\n| --- | --- |\n$row") }
        }
        problem(DocumentProblem.RaggedTable) { DocumentMarkdown.parse("t", "en", "| a | b |\n| --- |\n| 1 | 2 |") }
        problem(DocumentProblem.EmptyTable) { DocumentMarkdown.parse("t", "en", "| a |\n| --- |") }
        val blankCells = DocumentMarkdown.parse("t", "en", "| a |\n| --- |\n| |")
        assertTrue(DocumentWriters.csv(blankCells, 0).toString(Charsets.UTF_8).contains("\"\""))
    }

    @Test fun escapedPipesCodeSpansAndFencedExamples() {
        val doc = DocumentMarkdown.parse("t", "en", "| a | b |\n| --- | --- |\n| x\\|y | `a|b` |\n\n```md\n| x |\n| --- |\n| y |\n```")
        val tables = doc.sections.filterIsInstance<DocumentSection.Table>()
        assertEquals(1, tables.size)
        assertEquals(listOf("x|y", "`a|b`"), tables.single().rows.single())
        assertTrue((doc.sections.last() as DocumentSection.Paragraph).text.startsWith("```md"))
    }

    @Test fun htmlEscapesAllDataAndHasNoActiveContent() {
        val hostile = "<script>alert(1)</script><img src=file:///secret onerror=alert(2)> & \" '"
        val html = DocumentWriters.html(DocumentModel(hostile, "en", listOf(
            DocumentSection.Heading(2, hostile), DocumentSection.Paragraph(hostile),
            DocumentSection.ListSection(listOf(hostile), true), DocumentSection.Table(listOf(hostile), listOf(listOf(hostile))),
        )))
        assertFalse(html.contains("<script>"))
        assertFalse(html.contains("<img"))
        assertTrue(html.contains("&lt;script&gt;"))
        assertTrue(html.contains("default-src 'none'"))
        assertTrue(html.contains("<ol><li>"))
        assertTrue(html.contains("<th scope=\"col\">"))
        assertFalse(html.contains("lang=\"en\" onload="))
        problem(DocumentProblem.InvalidLanguage) {
            DocumentWriters.html(DocumentModel("t", "en\" onload=\"evil", listOf(DocumentSection.Paragraph("p"))))
        }
    }

    @Test fun csvRoundTripsQuotesCommasLineBreaksAndChineseWithBom() {
        val doc = table(listOf("名稱", "備註"), listOf(listOf("茶,水", "說\"你好\"\r\n下一行")))
        val bytes = DocumentWriters.csv(doc, null)
        assertArrayEquals(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()), bytes.take(3).toByteArray())
        assertEquals("\uFEFF\"名稱\",\"備註\"\r\n\"茶,水\",\"說\"\"你好\"\"\r\n下一行\"\r\n", bytes.toString(Charsets.UTF_8))
    }

    @Test fun csvNeutralizesFormulaAndControlPrefixesIncludingNegativeNumbers() {
        listOf("=1+2", " +cmd", "\u00a0-42", "  @SUM(A1)", "\tplain", "\rtext", " \ntext", "\uFEFF=1").forEach {
            assertEquals("'$it", DocumentWriters.safeCell(it))
        }
        listOf("42", "中文", "a=b", "line\nbreak", "").forEach { assertEquals(it, DocumentWriters.safeCell(it)) }
        val text = DocumentWriters.csv(table(listOf("=header"), listOf(listOf("-12"))), 0).toString(Charsets.UTF_8)
        assertTrue(text.contains("\"'=header\""))
        assertTrue(text.contains("\"'-12\""))
    }

    @Test fun csvRequiresOneExplicitTableWhenSeveralExist() {
        val doc = DocumentModel("t", "en", table(listOf("A"), listOf(listOf("first"))).sections +
            table(listOf("B"), listOf(listOf("second"))).sections)
        problem(DocumentProblem.SelectTable) { DocumentWriters.csv(doc, null) }
        problem(DocumentProblem.SelectTable) { DocumentWriters.csv(doc, 2) }
        val csv = DocumentWriters.csv(doc, 1).toString(Charsets.UTF_8)
        assertTrue(csv.contains("second")); assertFalse(csv.contains("first"))
        problem(DocumentProblem.MissingTable) { DocumentWriters.csv(DocumentMarkdown.parse("t", "en", "text"), null) }
    }

    @Test fun limitsUseUtf8BytesAndTotalCellsAcrossTables() {
        problem(DocumentProblem.Empty) { DocumentMarkdown.parse("t", "en", " \n ") }
        problem(DocumentProblem.TooLarge) { DocumentMarkdown.parse("t", "zh-Hant", "中".repeat(349_526)) }
        problem(DocumentProblem.TooLarge) { DocumentLimits.validate(table(List(65) { "c" }, listOf(List(65) { "v" }))) }
        problem(DocumentProblem.TooLarge) { DocumentLimits.validate(table(listOf("c"), List(5001) { listOf("v") })) }
        val large = DocumentSection.Table(List(10) { "c" }, List(2500) { List(10) { "v" } })
        problem(DocumentProblem.TooLarge) { DocumentLimits.validate(DocumentModel("t", "en", listOf(large, large))) }
        DocumentLimits.validate(table(List(10) { "c" }, List(4999) { List(10) { "v" } }))
        problem(DocumentProblem.TooLarge) {
            DocumentMarkdown.parse("t", "en", List(65) { "| c |\n| --- |\n| v |" }.joinToString("\n\n"))
        }
    }

    @Test fun unsupportedListNumberingAndNestingStayLiteral() {
        listOf("5. Fifth\n6. Sixth", "1. First\n3. Third", "- Parent\n  - Child", "    | Code |\n    | --- |\n    | Value |").forEach { source ->
            assertEquals(listOf(DocumentSection.Paragraph(source)), DocumentMarkdown.parse("t", "en", source).sections)
        }
    }

    @Test fun metadataAndNonTextControlsAreRejectedWithoutSilentCleaning() {
        problem(DocumentProblem.InvalidTitle) { DocumentMarkdown.parse("中".repeat(342), "en", "body") }
        problem(DocumentProblem.InvalidTitle) { DocumentMarkdown.parse("Title\nOther", "en", "body") }
        problem(DocumentProblem.InvalidContent) { DocumentMarkdown.parse("t", "en", "before\u0000after") }
        assertEquals("é.pdf", DocumentWriters.filename("e\u0301", DocumentFormat.PDF))
    }

    @Test fun filenamesCannotEscapeDirectoryOrSplitSupplementaryUnicode() {
        val name = DocumentWriters.filename("../報告/\\:*?\"<>|\n\u202e", DocumentFormat.PDF)
        assertEquals("報告.pdf", name)
        assertEquals("document.csv", DocumentWriters.filename("...", DocumentFormat.CSV))
        assertEquals("_CON.html", DocumentWriters.filename("CON", DocumentFormat.HTML))
        val long = DocumentWriters.filename("😀".repeat(100), DocumentFormat.PDF).removeSuffix(".pdf")
        assertTrue(long.codePointCount(0, long.length) <= 80)
        assertTrue(long.toByteArray(Charsets.UTF_8).size <= 240)
        assertFalse(long.contains('\uFFFD'))
        assertEquals("中".repeat(80) + ".csv", DocumentWriters.filename("中".repeat(90), DocumentFormat.CSV))
    }

    private fun table(columns: List<String>, rows: List<List<String>>) = DocumentModel("t", "en", listOf(DocumentSection.Table(columns, rows)))
    private fun problem(expected: DocumentProblem, action: () -> Unit) {
        try { action(); fail("Expected $expected") } catch (e: DocumentException) { assertEquals(expected, e.problem) }
    }
}
