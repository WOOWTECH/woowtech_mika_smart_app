package com.wangzan101.mika.ui

import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AiResponseReportsTest {
    @Test fun senderUsesReceiverContractAndRequiresMatchingAcknowledgment() {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", "run", "r0"), "answer", "unsafe", "detail")
            val sender = AiResponseReportSender(server.url("/api/v1/ai-reports").toString())
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"wrong","accepted":true}"""))
            assertEquals(ReportDeliveryResult.Retryable, sender.send(report))
            val request = server.takeRequest()
            assertEquals("POST", request.method)
            assertEquals("/api/v1/ai-reports", request.path)
            assertNull(request.getHeader("Authorization"))
            val body = Json.parseToJsonElement(request.body.readUtf8()) as JsonObject
            assertEquals(setOf("id", "reason", "note", "response", "created_at_ms"), body.keys)
            assertEquals(report.id, body["id"]?.toString()?.trim('"'))
            server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"${report.id}","accepted":true}"""))
            assertEquals(ReportDeliveryResult.Rejected, sender.send(report))
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${report.id}","accepted":true,"deletion_receipt":"receipt"}"""))
            val ack = sender.send(report)
            assertEquals(ReportDeliveryResult.Acknowledged("receipt"), ack)
            assertEquals("acknowledged", queue.recordAttempt(report.id, ack, 100).status)
            assertEquals("receipt", AiResponseReportQueue(dir).get(report.id)?.deletionReceipt)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun failedAttemptsStayPendingWithBoundedBackoff() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", null, "r0"), "answer", "other", "")
            val first = queue.recordAttempt(report.id, ReportDeliveryResult.Retryable, 1_000)
            assertEquals("queued_local", first.status)
            assertEquals(31_000, first.nextAttemptAtMs)
            assertNull(first.acknowledgedAtMs)
            val second = queue.recordAttempt(report.id, ReportDeliveryResult.Retryable, 31_000)
            assertEquals(151_000, second.nextAttemptAtMs)
            assertEquals(2, AiResponseReportQueue(dir).get(report.id)?.attempts)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun automaticDeliveryStopsAfterThreeAttemptsAndNeverClaimsReceipt() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", null, "r0"), "answer", "other", "")
            repeat(4) { server.enqueue(MockResponse().setResponseCode(503)) }
            val sender = AiResponseReportSender(server.url("/api/v1/ai-reports").toString())
            var now = report.createdAtMs
            repeat(3) {
                AiResponseReportDelivery.deliverDue(queue, sender) { now }
                now = requireNotNull(queue.get(report.id)).nextAttemptAtMs
            }
            AiResponseReportDelivery.deliverDue(queue, sender) { now + 1_000_000 }
            assertEquals(3, server.requestCount)
            val pending = requireNotNull(AiResponseReportQueue(dir).get(report.id))
            assertEquals("queued_local", pending.status)
            assertEquals(3, pending.attempts)
            assertNull(pending.acknowledgedAtMs)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }
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
