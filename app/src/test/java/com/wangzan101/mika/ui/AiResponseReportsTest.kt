package com.wangzan101.mika.ui

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AiResponseReportsTest {
    @Test fun reportPersistsLocallyWithReferenceAndNoDeliveryClaim() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val reference = AiResponseReference("conversation-1", "run-1", "r0")
            val saved = AiResponseReportQueue(dir).save(reference, "answer", "unsafe", "  concern  ")
            val reopened = AiResponseReportQueue(dir).all().single()
            assertEquals(saved, reopened)
            assertEquals("queued_local", reopened.status)
            assertEquals("concern", reopened.note)
            assertTrue(saved.id.isNotBlank())
            assertFalse(dir.listFiles().orEmpty().any { it.extension == "tmp" })
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun reportBoundsTextAndRejectsInvalidInput() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("conversation", null, "r0")
            val saved = queue.save(ref, "x".repeat(5000), "other", "n".repeat(1200))
            assertEquals(4000, saved.response.length)
            assertEquals(1000, saved.note.length)
            assertEquals(null, saved.reference.runId)
            assertTrue(runCatching { queue.save(ref, " ", "other", "") }.isFailure)
            assertTrue(runCatching { queue.save(ref, "answer", "invalid", "") }.isFailure)
            assertEquals(1, queue.all().size)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun onlyFinishedAiAnswersHaveReportReferences() {
        val done = Exchange("question", emptyList(), ExchangeStatus.Done("answer", null), live = false, runId = "run-1")
        val working = done.copy(status = ExchangeStatus.Working)
        assertEquals(AiResponseReference("conversation", "run-1", "r0"), aiResponseReference("conversation", listOf(done), "r0"))
        assertNull(aiResponseReference("conversation", listOf(working), "r0"))
        assertNull(aiResponseReference("conversation", listOf(done), "u0"))
        assertNull(aiResponseReference("conversation", listOf(done), "r1"))
        assertNull(aiResponseReference(null, listOf(done), "r0"))
        val withSteer = done.copy(steers = listOf(com.wangzan101.mika.task.SteerNote("steer-1", "more", com.wangzan101.mika.task.SteerState.Joined, finished = "earlier answer")))
        assertEquals(AiResponseReference("conversation", "run-1", "a0-steer-1"),
            aiResponseReference("conversation", listOf(withSteer), "a0-steer-1"))
        assertNull(aiResponseReference("conversation", listOf(done), "a0-steer-1"))
    }
}
