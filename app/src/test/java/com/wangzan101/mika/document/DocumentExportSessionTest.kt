package com.wangzan101.mika.document

import com.wangzan101.mika.R
import com.wangzan101.mika.core.document.DocumentFormat
import com.wangzan101.mika.core.document.DocumentSection
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class DocumentExportSessionTest {
    @Test fun malformedTableIsActionableAndRetryUsesEditedSource() = runTest {
        val session = DocumentExportSession(this, "| a | b |\n| --- | --- |\n| 1 |", "Title", "en", DocumentFormat.CSV, StandardTestDispatcher(testScheduler))
        var writes = 0
        session.generateWith { _, _, _ -> writes++; throw IOException() }
        advanceUntilIdle()
        assertEquals(0, writes)
        assertEquals(R.string.document_ragged, session.status)
        assertFalse(session.busy)
        session.editSource("| a | b |\n| --- | --- |\n| 1 | 2 |")
        session.generateWith { model, _, _ ->
            writes++
            assertEquals(listOf("1", "2"), (model.sections.single() as DocumentSection.Table).rows.single())
            throw IOException()
        }
        advanceUntilIdle()
        assertEquals(1, writes)
        assertEquals(R.string.document_failed, session.status)
        assertNull(session.generated)
    }

    @Test fun multipleTablesRequireChoiceAndSourceEditsInvalidateIt() = runTest {
        val source = "| A |\n| --- |\n| first |\n\n| B |\n| --- |\n| second |"
        val session = DocumentExportSession(this, source, "Title", "en", DocumentFormat.CSV, StandardTestDispatcher(testScheduler))
        var writes = 0
        session.generateWith { _, _, _ -> writes++; throw IOException() }
        advanceUntilIdle()
        assertEquals(0, writes)
        assertEquals(2, session.tables.size)
        assertEquals(R.string.document_choose_table, session.status)
        session.chooseTable(1)
        session.generateWith { _, format, index ->
            writes++; assertEquals(DocumentFormat.CSV, format); assertEquals(1, index); throw IOException()
        }
        advanceUntilIdle()
        assertEquals(1, writes)
        session.editSource(source + "\n\nNew paragraph")
        assertNull(session.tableIndex)
        assertTrue(session.tables.isEmpty())
        assertEquals(source + "\n\nNew paragraph", session.source)
    }

    @Test fun editsDuringGenerationCannotChangeSnapshotAndFailureIsNeverSuccess() = runTest {
        val source = "# 原文\n\n**Markdown**"
        val session = DocumentExportSession(this, source, "標題", "zh-Hant", DocumentFormat.PDF, StandardTestDispatcher(testScheduler))
        session.generateWith { model, format, _ ->
            assertEquals("標題", model.title)
            assertEquals(DocumentFormat.PDF, format)
            assertEquals("**Markdown**", (model.sections.last() as DocumentSection.Paragraph).text)
            throw IOException("No storage")
        }
        session.editSource("other")
        session.editTitle("other")
        session.chooseFormat(DocumentFormat.HTML)
        advanceUntilIdle()
        assertEquals(source, session.source)
        assertEquals("標題", session.title)
        assertEquals(R.string.document_failed, session.status)
        assertFalse(session.busy)
        assertNull(session.pendingSave)
    }
}
