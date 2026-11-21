package com.wangzan101.mika.core.document

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class DocumentTest {
    private fun parse(s: String) = Document.parse(Json.parseToJsonElement(s).jsonObject)
    @Test fun literalHtmlAndOfflinePolicy() {
        val d = parse("""{"title":"中文 <script>","sections":[{"type":"paragraph","text":"<img src=x onerror=alert(1)> & \"hello\""}]}""")
        val html = d.html()
        assertFalse(html.contains("<script>"))
        assertFalse(html.contains("<img"))
        assertTrue(html.contains("&lt;img"))
        assertTrue(html.contains("default-src 'none'"))
        assertTrue(html.contains("中文"))
    }
    @Test fun csvQuotesUnicodeAndFormulaProtection() {
        val d = Document("表格", listOf(Document.Section("table", columns=listOf("欄位"),
            rows=listOf(listOf("逗號,引號\"換\n行"), listOf(" =1+1"), listOf("00123")))))
        assertEquals("\uFEFF\"欄位\"\r\n\"逗號,引號\"\"換\n行\"\r\n\"' =1+1\"\r\n\"00123\"\r\n", d.csv(null))
    }
    @Test fun ambiguousAndInvalidTablesRejected() {
        val t = Document.Section("table", columns=listOf("a"), rows=listOf(listOf("b")))
        val d = Document("test", listOf(t,t))
        assertThrows(IllegalArgumentException::class.java) { d.csv(null) }
        assertEquals(Document("one", listOf(t)).csv(null), d.csv(1))
        assertThrows(IllegalArgumentException::class.java) { d.csv(2) }
        assertThrows(IllegalArgumentException::class.java) { parse("""{"title":"x","sections":[{"type":"table","columns":["a"],"rows":[["b","c"]]}]}""") }
    }
    @Test fun emptyUnknownAndOversizedRejected() {
        listOf("""{"title":"x","sections":[]}""", """{"title":"x","sections":[{"type":"script"}]}""", """{"title":"x","sections":[4]}""").forEach {
            assertThrows(IllegalArgumentException::class.java) { parse(it) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            Document.parse(buildJsonObject { put("title", "a".repeat(250001)) })
        }
    }
    @Test fun filenameCannotTraverse() {
        val name = Document("../../中文\\file:bad", emptyList()).fileName("pdf")
        assertFalse(name.contains('/')); assertFalse(name.contains('\\')); assertFalse(name.contains(':'))
        assertTrue(name.endsWith(".pdf"))
        val emojiName = Document("A" + "😀".repeat(50), emptyList()).fileName("pdf").removeSuffix(".pdf")
        assertFalse(Character.isHighSurrogate(emojiName.last()))
    }
}
