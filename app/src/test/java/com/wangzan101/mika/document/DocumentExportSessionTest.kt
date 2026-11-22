package com.wangzan101.mika.document

import com.wangzan101.mika.R
import com.wangzan101.mika.core.document.DocumentException
import com.wangzan101.mika.core.document.DocumentProblem
import com.wangzan101.mika.core.document.DocumentWriters
import com.wangzan101.mika.core.document.DocumentLimits
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
    @Test fun sourceErrorSurvivesOutputEditsUntilSourceChanges() = runTest {
        val session = DocumentExportSession(this, "| A | B |\n| --- | --- |\n| one |", "Title", "en", DocumentFormat.CSV, StandardTestDispatcher(testScheduler))
        var writes = 0
        session.generateWith { _, _, _ -> writes++; throw IOException() }
        advanceUntilIdle()
        assertEquals(R.string.document_ragged, session.status)
        for (format in listOf(DocumentFormat.HTML, DocumentFormat.PDF, DocumentFormat.CSV)) {
            session.chooseFormat(format)
            session.editTitle("Title " + format.name)
            assertEquals(R.string.document_ragged, session.status)
            assertNull(session.generated)
            assertFalse(session.busy)
        }
        assertEquals(0, writes)
        session.editSource("| A | B |\n| --- | --- |\n| one | two |")
        assertEquals(R.string.document_local_note, session.status)
        session.generateWith { model, format, _ ->
            writes++
            assertEquals(DocumentFormat.CSV, format)
            assertEquals(listOf("one", "two"), (model.sections.single() as DocumentSection.Table).rows.single())
            throw IOException()
        }
        advanceUntilIdle()
        assertEquals(1, writes)
        assertEquals(R.string.document_failed, session.status)
        session.chooseFormat(DocumentFormat.HTML)
        assertEquals("A writer failure is not a cached source error", R.string.document_local_note, session.status)
    }

    @Test fun editingTitleCanRepairValidationIncludingCombinedByteLimit() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        for ((source, invalidTitle) in listOf(
            "Valid source" to "",
            "x".repeat(DocumentLimits.MAX_SOURCE_BYTES - 10) to "Title uses more than ten bytes",
        )) {
            val session = DocumentExportSession(this, source, invalidTitle, "en", DocumentFormat.HTML, dispatcher)
            var writes = 0
            session.generateWith { _, _, _ -> writes++; throw IOException() }
            advanceUntilIdle()
            assertEquals(if (invalidTitle.isEmpty()) R.string.document_invalid_title else R.string.document_too_large, session.status)
            assertEquals(0, writes)
            session.chooseFormat(DocumentFormat.PDF)
            assertEquals(if (invalidTitle.isEmpty()) R.string.document_invalid_title else R.string.document_too_large, session.status)
            session.editTitle("OK")
            assertEquals(R.string.document_local_note, session.status)
            session.generateWith { _, _, _ -> writes++; throw IOException() }
            advanceUntilIdle()
            assertEquals(1, writes)
        }
    }

    @Test fun formatDependentWriterFailureIsNotRetainedAsSourceValidation() = runTest {
        val session = DocumentExportSession(this, "No table", "Title", "en", DocumentFormat.CSV, StandardTestDispatcher(testScheduler))
        session.generateWith { model, _, index ->
            DocumentWriters.csv(model, index)
            throw AssertionError("CSV without a table must fail in the real writer")
        }
        advanceUntilIdle()
        assertEquals(R.string.document_missing_table, session.status)
        session.chooseFormat(DocumentFormat.HTML)
        assertEquals(R.string.document_local_note, session.status)
        var writes = 0
        session.generateWith { _, format, _ ->
            writes++
            assertEquals(DocumentFormat.HTML, format)
            throw DocumentException(DocumentProblem.TooLarge)
        }
        advanceUntilIdle()
        assertEquals(1, writes)
        assertEquals(R.string.document_too_large, session.status)
        session.chooseFormat(DocumentFormat.PDF)
        assertEquals(R.string.document_local_note, session.status)
    }

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
