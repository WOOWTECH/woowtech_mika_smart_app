package com.wangzan101.mika.document

import com.wangzan101.mika.core.document.DocumentModel
import com.wangzan101.mika.core.document.DocumentSection
import com.wangzan101.mika.core.document.DocumentWriters
import org.junit.Assert.*
import org.junit.Test

class DocumentCsvPreviewTextTest {
    @Test fun generatedCsvKeepsEveryTwoThreeAndFourByteBoundary() {
        val cap = DocumentCsvPreviewText.MAX_BYTES
        val header = "\uFEFF\"A\"\r\n\""
        for (scalar in listOf("é", "中", "🙂")) {
            val width = scalar.toByteArray(Charsets.UTF_8).size
            for (inside in 0..width) {
                val padding = "x".repeat(cap - header.toByteArray(Charsets.UTF_8).size - inside)
                val model = DocumentModel("Preview", "en", listOf(DocumentSection.Table(
                    listOf("A"), listOf(listOf(padding + scalar + "END")),
                )))
                val complete = DocumentWriters.csv(model, null)
                val original = complete.copyOf()
                val end = if (inside in 1 until width) cap - inside else cap
                val expected = String(complete, 0, end, Charsets.UTF_8).removePrefix("\uFEFF")
                assertEquals(expected, DocumentCsvPreviewText.text(complete))
                // The real loader reads only the cap plus one byte of lookahead.
                assertEquals(expected, DocumentCsvPreviewText.text(complete.copyOf(cap + 1)))
                assertFalse(DocumentCsvPreviewText.text(complete).contains('\uFFFD'))
                assertArrayEquals(original, complete)
                assertTrue(String(complete, Charsets.UTF_8).contains(scalar + "END"))
            }
        }
    }

    @Test fun emptyShortAndExactCapKeepTheirCompleteScalars() {
        assertEquals("", DocumentCsvPreviewText.text(byteArrayOf()))
        assertEquals("中🙂", DocumentCsvPreviewText.text("\uFEFF中🙂".toByteArray(Charsets.UTF_8)))
        val cap = DocumentCsvPreviewText.MAX_BYTES
        val exact = "x".repeat(cap - 4) + "🙂"
        assertEquals(cap, exact.toByteArray(Charsets.UTF_8).size)
        assertEquals(exact, DocumentCsvPreviewText.text(exact.toByteArray(Charsets.UTF_8)))
        assertEquals(exact, DocumentCsvPreviewText.text((exact + "TAIL").toByteArray(Charsets.UTF_8)))
    }
}
