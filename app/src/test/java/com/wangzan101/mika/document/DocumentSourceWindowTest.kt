package com.wangzan101.mika.document

import org.junit.Assert.*
import org.junit.Test

class DocumentSourceWindowTest {
    @Test fun editingPreviewPreservesUnseenSourceAndTraversesEveryCharacter() {
        val source = "甲".repeat(1499) + "😀" + "乙".repeat(3500) + "\n| A |\n| --- |\n| tail |"
        var offset = 0
        val visited = StringBuilder()
        while (offset < source.length) {
            val page = DocumentSourceWindow.at(source, offset)
            assertTrue(page.text.length <= 1500)
            assertFalse(page.text.last().isHighSurrogate())
            assertFalse(page.text.first().isLowSurrogate())
            visited.append(page.text)
            offset = page.end
        }
        assertEquals(source, visited.toString())
        val first = DocumentSourceWindow.at(source, 0)
        assertEquals("Edited" + source.substring(first.end), first.replace(source, "Edited"))
        val middle = DocumentSourceWindow.at(source, first.end)
        assertEquals(source.substring(0, middle.start) + "New" + source.substring(middle.end), middle.replace(source, "New"))
    }
}
