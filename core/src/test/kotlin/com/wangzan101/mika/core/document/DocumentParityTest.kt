package com.wangzan101.mika.core.document

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class DocumentParityTest {
    @Test fun sharedAndroidIOSFixtureProducesExactCSVAndEscapedHTML() {
        val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .first { File(it, "test-fixtures/documents/parity-v1.json").isFile }
        val fixture = Json.parseToJsonElement(File(root, "test-fixtures/documents/parity-v1.json").readText()).jsonObject
        fun text(key: String) = fixture.getValue(key).jsonPrimitive.content
        val document = DocumentMarkdown.parse(text("title"), text("language"), text("source"))
        val rows = fixture.getValue("rows").jsonArray.map { row -> row.jsonArray.map { it.jsonPrimitive.content } }
        assertEquals(rows, document.sections.filterIsInstance<DocumentSection.Table>().single().rows)
        assertEquals(text("expectedCSV"), DocumentWriters.csv(document, 0).toString(Charsets.UTF_8))
        val html = DocumentWriters.html(document)
        assertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        assertFalse(html.contains("<script>"))
    }
}
