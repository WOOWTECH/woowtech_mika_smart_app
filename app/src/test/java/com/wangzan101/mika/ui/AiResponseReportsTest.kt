package com.wangzan101.mika.ui

import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
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
    @Test fun deletingAcknowledgedReportRequiresMatchingServerConfirmation() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", "run", "r0"), "private answer", "unsafe", "note")
            queue.recordAttempt(report.id, ReportDeliveryResult.Acknowledged("receipt-secret"), System.currentTimeMillis())
            val sender = AiResponseReportSender(server.url("/api/v1/ai-reports").toString())
            server.enqueue(MockResponse().setResponseCode(503))
            assertEquals(ReportDeletionResult.Retryable, AiResponseReportDelivery.delete(queue, sender, report.id))
            assertEquals("acknowledged", AiResponseReportQueue(dir).get(report.id)?.status)
            server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"${report.id}","deleted":false}"""))
            assertEquals(ReportDeletionResult.Retryable, AiResponseReportDelivery.delete(queue, sender, report.id))
            assertEquals("acknowledged", queue.get(report.id)?.status)
            server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"${report.id}","deleted":true}"""))
            assertEquals(ReportDeletionResult.Deleted, AiResponseReportDelivery.delete(queue, sender, report.id))
            assertNull(AiResponseReportQueue(dir).get(report.id))
            repeat(3) {
                val request = server.takeRequest()
                assertEquals("DELETE", request.method)
                assertEquals("/api/v1/ai-reports/${report.id}", request.path)
                assertEquals("Bearer receipt-secret", request.getHeader("Authorization"))
            }
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun deletionHandlesUnsentAndUncertainReportsWithoutLosingEvidence() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val sender = AiResponseReportSender(server.url("/api/v1/ai-reports").toString())
            val unsent = queue.save(AiResponseReference("conversation", "run", "r0"), "answer", "other", "")
            assertEquals(ReportDeletionResult.Deleted, AiResponseReportDelivery.delete(queue, sender, unsent.id))
            assertNull(queue.get(unsent.id))
            val uncertain = queue.save(AiResponseReference("conversation", "run2", "r1"), "answer", "other", "")
            queue.recordAttempt(uncertain.id, ReportDeliveryResult.Retryable, System.currentTimeMillis())
            assertEquals(ReportDeletionResult.CannotVerify, AiResponseReportDelivery.delete(queue, sender, uncertain.id))
            queue.recordAttempt(uncertain.id, ReportDeliveryResult.Acknowledged(null), System.currentTimeMillis())
            assertEquals(ReportDeletionResult.CannotVerify, AiResponseReportDelivery.delete(queue, sender, uncertain.id))
            assertEquals("acknowledged", AiResponseReportQueue(dir).get(uncertain.id)?.status)
            assertEquals(0, server.requestCount)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

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

    @Test fun reopenAndRetryPreservesIdentityThroughFailureRejectionAndAcknowledgment() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val ref = AiResponseReference("conversation", "run", "r0")
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(ref, "private answer", "unsafe", "private note")
            val sender = AiResponseReportSender(server.url("/api/v1/ai-reports").toString())
            repeat(3) { server.enqueue(MockResponse().setResponseCode(503)) }
            var now = report.createdAtMs
            repeat(3) {
                AiResponseReportDelivery.deliverDue(queue, sender) { now }
                now = requireNotNull(queue.get(report.id)).nextAttemptAtMs
            }
            val reopened = AiResponseReportQueue(dir)
            assertEquals(3, reopened.find(ref)?.attempts)
            assertEquals(report.id, reopened.save(ref, "other text", "other", "").id)
            server.enqueue(MockResponse().setResponseCode(400))
            assertEquals("rejected", AiResponseReportDelivery.retry(reopened, sender, report.id).status)
            assertEquals("rejected", AiResponseReportQueue(dir).find(ref)?.status)
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${report.id}","accepted":true}"""))
            assertEquals("acknowledged", AiResponseReportDelivery.retry(reopened, sender, report.id).status)
            assertEquals("acknowledged", AiResponseReportQueue(dir).find(ref)?.status)
            assertEquals("acknowledged", AiResponseReportDelivery.retry(reopened, sender, report.id).status)
            assertEquals(5, server.requestCount)
            repeat(5) {
                val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()) as JsonObject
                assertEquals(report.id, body["id"]?.toString()?.trim('"'))
                assertEquals("private answer", body["response"]?.toString()?.trim('"'))
            }
            assertEquals(1, reopened.all().size)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun concurrentQueueInstancesDeduplicateAndIsolateReferences() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        val pool = Executors.newFixedThreadPool(8)
        try {
            val ref = AiResponseReference("conversation", "run", "r0")
            val start = CountDownLatch(1)
            val saves = (1..16).map {
                pool.submit<AiResponseReport> {
                    start.await()
                    AiResponseReportQueue(dir).save(ref, "answer", "other", "")
                }
            }
            start.countDown()
            assertEquals(1, saves.map { it.get(10, TimeUnit.SECONDS).id }.toSet().size)
            val queue = AiResponseReportQueue(dir)
            val otherRefs = listOf(ref.copy(conversationId = "other"), ref.copy(runId = "other"),
                ref.copy(runId = "another", messageKey = "r1"), ref.copy(messageKey = "a0-steer"),
                ref.copy(conversationId = "third", runId = null))
            otherRefs.forEach {
                assertNull(queue.find(it))
                queue.save(it, "answer", "other", "")
            }
            assertEquals(6, queue.all().map { it.id }.toSet().size)
        } finally {
            pool.shutdownNow()
            dir.deleteRecursively()
        }
    }

    @Test fun retryWaitsForConcurrentDeliveryAndDoesNotResendAnAcknowledgedReport() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", "run", "r0"), "answer", "other", "")
            val sender = AiResponseReportSender(server.url("/").toString())
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${report.id}","accepted":true}""")
                .setBodyDelay(500, TimeUnit.MILLISECONDS))
            val delivery = async(Dispatchers.IO) { AiResponseReportDelivery.deliverDue(queue, sender) }
            assertTrue(server.takeRequest(5, TimeUnit.SECONDS) != null)
            val retry = async(Dispatchers.IO) { AiResponseReportDelivery.retry(AiResponseReportQueue(dir), sender, report.id) }
            delivery.await()
            assertEquals("acknowledged", retry.await().status)
            assertEquals(1, server.requestCount)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun legacyDuplicateAcknowledgmentSuppressesPendingCopies() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("conversation", "run", "r0")
            val pending = queue.save(ref, "answer", "other", "")
            val duplicateId = java.util.UUID.randomUUID().toString()
            val original = java.io.File(dir, "${pending.id}.json").readText()
            java.io.File(dir, "$duplicateId.json").writeText(original.replace(pending.id, duplicateId))
            queue.recordAttempt(duplicateId, ReportDeliveryResult.Acknowledged(null), 100)
            assertEquals(duplicateId, queue.find(ref)?.id)
            val sender = AiResponseReportSender(server.url("/").toString())
            AiResponseReportDelivery.deliverDue(queue, sender)
            assertEquals(duplicateId, AiResponseReportDelivery.retry(queue, sender, pending.id).id)
            assertEquals(0, server.requestCount)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun offlineRetryRemainsPendingAndUnreadableQueueDoesNotCreateDuplicates() = runBlocking {
        val server = MockWebServer()
        server.start()
        val sender = AiResponseReportSender(server.url("/").toString())
        server.shutdown()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val ref = AiResponseReference("conversation", null, "r0")
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(ref, "answer", "other", "")
            val retried = AiResponseReportDelivery.retry(queue, sender, report.id)
            assertEquals("queued_local", retried.status)
            assertNull(retried.acknowledgedAtMs)
            assertEquals(report.id, AiResponseReportQueue(dir).find(ref)?.id)
            java.io.File(dir, "broken.json").writeText("{")
            assertTrue(runCatching { queue.find(ref) }.isFailure)
            assertTrue(runCatching { queue.save(ref, "answer", "other", "") }.isFailure)
            assertEquals(2, dir.listFiles { file -> file.extension == "json" }?.size)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun identifiableDamagedRecordBlocksOnlyItsOwnResponse() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val blockedRef = AiResponseReference("conversation", "run", "r0")
            val healthyRef = blockedRef.copy(runId = "another-run", messageKey = "r1")
            val blocked = queue.save(blockedRef, "answer", "other", "")
            val healthy = queue.save(healthyRef, "answer", "other", "")
            java.io.File(dir, "damaged.json").writeText(
                """{"conversationId":"conversation","runId":"run","messageKey":"r0"}"""
            )
            assertTrue(runCatching { queue.find(blockedRef) }.isFailure)
            assertTrue(runCatching { queue.save(blockedRef, "answer", "other", "") }.isFailure)
            assertEquals(healthy.id, queue.find(healthyRef)?.id)
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${healthy.id}","accepted":true}"""))
            AiResponseReportDelivery.deliverDue(queue, AiResponseReportSender(server.url("/").toString()))
            assertEquals(1, server.requestCount)
            assertEquals("acknowledged", queue.find(healthyRef)?.status)
            assertNull(queue.get(blocked.id))
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun expiredReportIsKeptAndExplicitReplacementIsManual() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val report = queue.save(AiResponseReference("conversation", null, "r0"), "answer", "other", "")
            val week = 7L * 24 * 60 * 60 * 1_000
            assertFalse(reportOutsideIntakeWindow(report, report.createdAtMs + week))
            assertTrue(reportOutsideIntakeWindow(report, report.createdAtMs + week + 1))
            assertTrue(reportOutsideIntakeWindow(report, report.createdAtMs - week - 1))
            val oldCreatedAt = report.createdAtMs - week - 1_000
            val file = java.io.File(dir, "${report.id}.json")
            file.writeText(file.readText().replace("\"createdAtMs\":${report.createdAtMs}", "\"createdAtMs\":$oldCreatedAt"))
            val oldBytes = file.readText()
            val sender = AiResponseReportSender(server.url("/").toString())
            AiResponseReportDelivery.deliverDue(queue, sender)
            val expired = AiResponseReportDelivery.retry(queue, sender, report.id)
            assertEquals("queued_local", expired.status)
            assertNull(expired.acknowledgedAtMs)
            assertEquals(oldCreatedAt, expired.createdAtMs)
            assertEquals(0, server.requestCount)
            val replacement = AiResponseReportDelivery.createManual(queue, report.reference, "answer", "other", "", report.id)
            assertTrue(replacement.manualOnly)
            assertEquals(report.id, replacement.replacementOf)
            assertTrue(replacement.id != report.id)
            assertFalse(reportOutsideIntakeWindow(replacement, System.currentTimeMillis()))
            assertEquals(replacement.id, AiResponseReportDelivery.createManual(queue, report.reference, "answer", "other", "", report.id).id)
            val different = runCatching {
                AiResponseReportDelivery.createManual(queue, report.reference, "answer", "other", "different details", report.id)
            }.exceptionOrNull() as ExistingManualReportException
            assertEquals(replacement.id, different.report.id)
            assertEquals("", different.report.note)
            assertEquals(0, server.requestCount)
            assertEquals(oldBytes, file.readText())
            AiResponseReportDelivery.deliverDue(queue, sender)
            // Even if the device clock is corrected, the retained old report must not resume automatically.
            AiResponseReportDelivery.deliverDue(queue, sender) { oldCreatedAt + 1 }
            assertEquals(0, server.requestCount)
            server.enqueue(MockResponse().setResponseCode(503))
            assertEquals("queued_local", AiResponseReportDelivery.sendManual(queue, sender, replacement.id).status)
            AiResponseReportDelivery.deliverDue(queue, sender)
            assertEquals(1, server.requestCount)
            assertEquals(replacement.id, AiResponseReportQueue(dir).manualReports("conversation").single().id)
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${replacement.id}","accepted":true}"""))
            assertEquals("acknowledged", AiResponseReportDelivery.sendManual(queue, sender, replacement.id).status)
            assertEquals("acknowledged", AiResponseReportDelivery.sendManual(queue, sender, replacement.id).status)
            assertEquals(replacement.id, AiResponseReportDelivery.createManual(queue, report.reference, "answer", "other", "", report.id).id)
            assertEquals(2, server.requestCount)
            val firstBody = Json.parseToJsonElement(server.takeRequest().body.readUtf8()) as JsonObject
            assertEquals(replacement.id, firstBody["id"]?.toString()?.trim('"'))
            assertEquals(replacement.createdAtMs.toString(), firstBody["created_at_ms"].toString())
            assertEquals(oldBytes, file.readText())
            assertEquals(report.id, queue.find(report.reference)?.id)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }

    @Test fun manualReportsAreIndependentAndNeverGuessedByText() = runBlocking {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val legacy = AiResponseReference("c", "run", "a0-old-uuid")
            val old = queue.save(legacy, "same answer", "other", "")
            queue.recordAttempt(old.id, ReportDeliveryResult.Acknowledged(null), 10)
            val uncertain = AiResponseReference("c", "run", "a0-turn-0", "steer:turn-0", 0)
            assertTrue(runCatching { queue.find(uncertain) }.exceptionOrNull() is AmbiguousReportReferenceException)
            val independent = AiResponseReportDelivery.createManual(queue, uncertain, "same answer", "other", "", null)
            val runless = AiResponseReference("c", null, "r0")
            val other = AiResponseReportDelivery.createManual(queue, runless, "same answer", "other", "", null)
            assertTrue(independent.id != other.id && independent.id != old.id)
            assertEquals(setOf(independent.id, other.id), AiResponseReportQueue(dir).manualReports("c").map { it.id }.toSet())
            assertTrue(queue.manualReports("different-conversation").isEmpty())
            assertEquals("acknowledged", queue.get(old.id)?.status)
            assertTrue(runCatching { queue.find(uncertain) }.exceptionOrNull() is AmbiguousReportReferenceException)
        } finally { dir.deleteRecursively() }
    }

    @Test fun independentReportPausesPossibleOldReportButNotOtherConversations() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val legacy = queue.save(AiResponseReference("c", "run", "a0-uuid"), "same", "other", "")
            val unrelated = queue.save(AiResponseReference("other", "run", "r0"), "answer", "other", "")
            val uncertain = AiResponseReference("c", "run", "a0-turn-0", "steer:turn-0", 0)
            val manual = AiResponseReportDelivery.createManual(queue, uncertain, "same", "other", "", null)
            val sender = AiResponseReportSender(server.url("/").toString())
            server.enqueue(MockResponse().setResponseCode(503))
            AiResponseReportDelivery.deliverDue(queue, sender)
            assertEquals(1, server.requestCount)
            val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()) as JsonObject
            assertEquals(unrelated.id, body["id"]?.toString()?.trim('"'))
            assertEquals(0, queue.get(legacy.id)?.attempts)
            assertEquals(0, queue.getManual(manual.id)?.attempts)
        } finally { server.shutdown(); dir.deleteRecursively() }
    }

    @Test fun replacementRechecksAcknowledgmentBeforeCreating() = runBlocking {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("c", "run", "r0", "final")
            val old = queue.save(ref, "answer", "other", "")
            val file = java.io.File(dir, "${old.id}.json")
            val oldCreated = old.createdAtMs - 8L * 24 * 60 * 60 * 1_000
            file.writeText(file.readText().replace("\"createdAtMs\":${old.createdAtMs}", "\"createdAtMs\":$oldCreated"))
            queue.recordAttempt(old.id, ReportDeliveryResult.Acknowledged(null), System.currentTimeMillis())
            val result = AiResponseReportDelivery.createManual(queue, ref, "answer", "other", "", old.id)
            assertEquals(old.id, result.id)
            assertEquals("acknowledged", result.status)
            assertTrue(queue.manualReports("c").isEmpty())
        } finally { dir.deleteRecursively() }
    }

    @Test fun concurrentManualSendsStopAfterFirstAcknowledgment() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("c", null, "r0")
            val report = AiResponseReportDelivery.createManual(queue, ref, "answer", "other", "", null)
            val sender = AiResponseReportSender(server.url("/").toString())
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${report.id}","accepted":true}""")
                .setBodyDelay(500, TimeUnit.MILLISECONDS))
            val first = async(Dispatchers.IO) { AiResponseReportDelivery.sendManual(queue, sender, report.id) }
            assertTrue(server.takeRequest(5, TimeUnit.SECONDS) != null)
            val second = async(Dispatchers.IO) { AiResponseReportDelivery.sendManual(AiResponseReportQueue(dir), sender, report.id) }
            assertEquals("acknowledged", first.await().status)
            assertEquals("acknowledged", second.await().status)
            assertEquals(1, server.requestCount)
        } finally { server.shutdown(); dir.deleteRecursively() }
    }

    @Test fun damagedManualFlagCannotTurnIntoAutomaticDelivery() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("c", "run", "r0", "final")
            queue.save(ref, "answer", "other", "")
            val manual = AiResponseReportDelivery.createManual(queue, ref, "answer", "other", "", null)
            val file = java.io.File(dir, "manual-${manual.id}.json")
            val json = Json.parseToJsonElement(file.readText()) as JsonObject
            file.writeText(JsonObject(json - "manualOnly").toString())
            assertTrue(queue.manualReports("c").isEmpty())
            assertTrue(runCatching { queue.find(ref) }.exceptionOrNull() is DamagedReportReferenceException)
            AiResponseReportDelivery.deliverDue(queue, AiResponseReportSender(server.url("/").toString()))
            assertEquals(0, server.requestCount)
        } finally { server.shutdown(); dir.deleteRecursively() }
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
        assertEquals(AiResponseReference("conversation", "run-1", "r0", "final"), aiResponseReference("conversation", listOf(done), "r0"))
        assertNull(aiResponseReference("conversation", listOf(working), "r0"))
        assertNull(aiResponseReference("conversation", listOf(done), "u0"))
        assertNull(aiResponseReference("conversation", listOf(done), "r1"))
        assertNull(aiResponseReference(null, listOf(done), "r0"))
        val withSteer = done.copy(steers = listOf(com.wangzan101.mika.task.SteerNote("steer-1", "more", com.wangzan101.mika.task.SteerState.Joined, finished = "earlier answer")))
        assertEquals(AiResponseReference("conversation", "run-1", "a0-steer-1", "steer:steer-1"),
            aiResponseReference("conversation", listOf(withSteer), "a0-steer-1"))
        assertNull(aiResponseReference("conversation", listOf(done), "a0-steer-1"))
    }

    @Test fun stableRunAndSteerIdsSurviveReorderingAndKeepIdenticalAnswersSeparate() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val steers = listOf("first", "second").map {
                com.wangzan101.mika.task.SteerNote(it, "question", com.wangzan101.mika.task.SteerState.Joined, finished = "same answer")
            }
            val ex = Exchange("question", emptyList(), ExchangeStatus.Done("same answer", null), false, "run", steers = steers)
            val first = requireNotNull(aiResponseReference("c", listOf(ex), "a0-first"))
            val second = requireNotNull(aiResponseReference("c", listOf(ex), "a0-second"))
            val firstReport = queue.save(first, "same answer", "other", "")
            val secondReport = queue.save(second, "same answer", "other", "")
            queue.recordAttempt(firstReport.id, ReportDeliveryResult.Acknowledged(null), 10)
            val rebuilt = ex.copy(steers = steers.mapIndexed { i, s -> s.copy(savedIndex = i) })
            val other = ex.copy(runId = "other")
            val movedFirst = requireNotNull(aiResponseReference("c", listOf(other, rebuilt), "a1-first"))
            val movedSecond = requireNotNull(aiResponseReference("c", listOf(other, rebuilt), "a1-second"))
            assertEquals(firstReport.id, queue.find(movedFirst)?.id)
            assertEquals("acknowledged", queue.find(movedFirst)?.status)
            assertEquals(secondReport.id, queue.find(movedSecond)?.id)
            assertEquals(2, queue.all().size)
            val oldFinal = queue.save(AiResponseReference("c", "run", "r0"), "same answer", "other", "")
            assertEquals(oldFinal.id, queue.find(requireNotNull(aiResponseReference("c", listOf(other, rebuilt), "r1")))?.id)
        } finally { dir.deleteRecursively() }
    }

    @Test fun legacySteerIndexesMigrateOnlyWithProvenMapping() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val old = queue.save(AiResponseReference("c", "run", "a0-turn-1"), "same", "other", "")
            queue.recordAttempt(old.id, ReportDeliveryResult.Acknowledged(null), 10)
            val pending = queue.save(AiResponseReference("c", "run", "a0-turn-0"), "same", "other", "")
            val mapped = AiResponseReference("c", "run", "a3-live-id", "steer:live-id", savedSteerIndex = 1)
            assertEquals(old.id, queue.find(mapped)?.id)
            assertEquals("acknowledged", AiResponseReportQueue(dir).find(mapped)?.status)
            val different = AiResponseReference("c", "run", "a3-other-id", "steer:other-id", savedSteerIndex = 0)
            assertEquals(pending.id, queue.find(different)?.id)
            assertEquals("queued_local", AiResponseReportQueue(dir).find(different)?.status)
            assertEquals(2, queue.all().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun legacyUuidWithoutMappingNeverGuessesFromIdenticalText() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val old = queue.save(AiResponseReference("c", "run", "a0-old-uuid"), "same", "other", "")
            queue.recordAttempt(old.id, ReportDeliveryResult.Acknowledged(null), 10)
            val rebuilt = AiResponseReference("c", "run", "a0-turn-0", "steer:turn-0", savedSteerIndex = 0)
            assertTrue(runCatching { queue.find(rebuilt) }.exceptionOrNull() is AmbiguousReportReferenceException)
            assertTrue(runCatching { queue.save(rebuilt, "same", "other", "") }.exceptionOrNull() is AmbiguousReportReferenceException)
            val second = AiResponseReference("c", "run", "a0-turn-1", "steer:turn-1", savedSteerIndex = 1)
            assertTrue(runCatching { queue.find(second) }.exceptionOrNull() is AmbiguousReportReferenceException)
            assertEquals(1, queue.all().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun steerUuidBridgesRunIdAvailabilityWithoutUsingText() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val old = queue.save(AiResponseReference("c", null, "a0-uuid-one"), "same", "other", "")
            val moved = AiResponseReference("c", "run", "a4-uuid-one", "steer:uuid-one", savedSteerIndex = 0)
            assertEquals(old.id, queue.find(moved)?.id)
            assertNull(queue.find(AiResponseReference("c", "run", "a4-uuid-two", "steer:uuid-two", savedSteerIndex = 1)))
        } finally { dir.deleteRecursively() }
    }

    @Test fun runlessFinalReportsWithReusedKeyAreNotMerged() {
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val ref = AiResponseReference("c", null, "r0")
            val first = queue.save(ref, "same", "other", "")
            val secondId = java.util.UUID.randomUUID().toString()
            val original = java.io.File(dir, "${first.id}.json").readText()
            java.io.File(dir, "$secondId.json").writeText(original.replace(first.id, secondId))
            queue.recordAttempt(first.id, ReportDeliveryResult.Acknowledged(null), 10)
            assertTrue(runCatching { queue.find(ref) }.exceptionOrNull() is AmbiguousReportReferenceException)
            assertEquals(2, queue.all().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun unidentifiedDamageRequiresExplicitChoiceAndSendsOnlySelectedReport() = runBlocking {
        val server = MockWebServer()
        server.start()
        val dir = Files.createTempDirectory("ai-reports").toFile()
        try {
            val queue = AiResponseReportQueue(dir)
            val chosen = queue.save(AiResponseReference("c", "run", "r0", "final"), "answer", "other", "")
            val other = queue.save(AiResponseReference("c", "other-run", "r1", "final"), "other answer", "other", "")
            java.io.File(dir, "broken.json").writeText("{")
            assertTrue(runCatching { queue.find(chosen.reference) }.exceptionOrNull() is UnidentifiedReportException)
            assertTrue(runCatching { queue.save(chosen.reference, "answer", "other", "") }.exceptionOrNull() is UnidentifiedReportException)
            val sender = AiResponseReportSender(server.url("/").toString())
            assertTrue(runCatching { AiResponseReportDelivery.deliverDue(queue, sender) }.exceptionOrNull() is UnidentifiedReportException)
            assertEquals(0, server.requestCount)
            assertEquals(chosen.id, queue.find(chosen.reference, allowUnidentified = true)?.id)
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${chosen.id}","accepted":true}"""))
            assertEquals("acknowledged", AiResponseReportDelivery.deliverOne(queue, sender, chosen.id).status)
            assertEquals(1, server.requestCount)
            assertEquals("queued_local", queue.get(other.id, allowUnidentified = true)?.status)
            assertEquals("acknowledged", AiResponseReportDelivery.retry(queue, sender, chosen.id, allowUnidentified = true).status)
            assertEquals(1, server.requestCount)
            val newRef = AiResponseReference("c", "third-run", "r2", "final")
            assertTrue(runCatching { queue.save(newRef, "new answer", "other", "") }.exceptionOrNull() is UnidentifiedReportException)
            val newReport = queue.save(newRef, "new answer", "other", "", allowUnidentified = true)
            server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"${newReport.id}","accepted":true}"""))
            assertEquals("acknowledged", AiResponseReportDelivery.deliverOne(queue, sender, newReport.id).status)
            assertEquals(2, server.requestCount)
            assertEquals("queued_local", queue.get(other.id, allowUnidentified = true)?.status)
        } finally {
            server.shutdown()
            dir.deleteRecursively()
        }
    }
}
