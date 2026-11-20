package com.wangzan101.mika.core.document

import org.junit.Assert.*
import org.junit.Test

class DocumentCommandTest {
    @Test fun exactRequestsRouteLocally() {
        assertEquals(DocumentFormat.PDF, DocumentCommand.parse("把剛才的回答做成 PDF"))
        assertEquals(DocumentFormat.CSV, DocumentCommand.parse("請把上一則回答匯出成CSV檔案。"))
        assertEquals(DocumentFormat.HTML, DocumentCommand.parse("Export the previous answer as HTML."))
        assertEquals(DocumentFormat.PDF, DocumentCommand.parse("save last response as pdf"))
        assertEquals(DocumentFormat.PDF, DocumentCommand.parse("把剛才的分析整理成 PDF"))
        assertEquals(DocumentFormat.CSV, DocumentCommand.parse("export the previous table to CSV"))
    }

    @Test fun questionsInstructionsAttachmentsQuotesAndActiveRunsStayInChat() {
        listOf("What is PDF?", "Can you export the last answer as PDF?", "把剛才的回答做成 PDF 是什麼意思？",
            "把剛才的回答做成 PDF 並寄給小明", "Export last answer as PDF and email it", "export last answer as pdf\n",
            "Make a PDF", "把剛才的回答做成 XLSX", "export last answer as PDF\u2028", "\"export last answer as pdf\"").forEach { assertNull(it, DocumentCommand.parse(it)) }
        val command = "把剛才的回答做成 PDF"
        assertNull(DocumentCommand.parse(command, hasAttachments = true))
        assertNull(DocumentCommand.parse(command, hasQuote = true))
        assertNull(DocumentCommand.parse(command, busy = true))
    }
}
