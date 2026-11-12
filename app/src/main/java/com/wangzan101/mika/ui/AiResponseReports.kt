package com.wangzan101.mika.ui

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A selected answer's location. UI keys are only hints; the saved text is the evidence. */
internal data class AiResponseReference(val conversationId: String, val runId: String?, val messageKey: String)

internal fun aiResponseReference(conversationId: String?, exchanges: List<Exchange>, key: String): AiResponseReference? {
    if (conversationId == null) return null
    val turn = when {
        key.startsWith("r") -> key.drop(1).toIntOrNull()?.takeIf { index ->
            exchanges.getOrNull(index)?.status.let { it is ExchangeStatus.Done || it is ExchangeStatus.Cancelled && it.summary != null }
        }
        key.startsWith("a") -> key.drop(1).substringBefore('-').toIntOrNull()?.takeIf { index ->
            val id = key.substringAfter('-', "")
            id.isNotEmpty() && exchanges.getOrNull(index)?.steers?.any { it.id == id && !it.finished.isNullOrBlank() } == true
        }
        else -> null
    } ?: return null
    return AiResponseReference(conversationId, exchanges[turn].runId, key)
}

/** A report stays pending until the relay acknowledges this exact ID. */
internal data class AiResponseReport(
    val id: String,
    val reference: AiResponseReference,
    val response: String,
    val reason: String,
    val note: String,
    val createdAtMs: Long,
    val status: String = "queued_local",
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val acknowledgedAtMs: Long? = null,
    val deletionReceipt: String? = null,
)

internal class AiResponseReportQueue(private val dir: File) {
    constructor(context: Context) : this(File(context.filesDir, "ai-response-reports"))

    @Synchronized
    fun save(reference: AiResponseReference, response: String, reason: String, note: String): AiResponseReport {
        require(reason in setOf("offensive", "unsafe", "other"))
        require(response.isNotBlank())
        val report = AiResponseReport(UUID.randomUUID().toString(), reference, response.take(MAX_RESPONSE), reason,
            note.trim().take(MAX_NOTE), System.currentTimeMillis())
        write(report)
        return report
    }

    @Synchronized
    fun get(id: String): AiResponseReport? = all().firstOrNull { it.id == id }

    @Synchronized
    fun recordAttempt(id: String, result: ReportDeliveryResult, now: Long): AiResponseReport {
        val old = requireNotNull(get(id))
        if (old.status == "acknowledged") return old
        val attempts = old.attempts + 1
        val updated = when (result) {
            is ReportDeliveryResult.Acknowledged -> old.copy(status = "acknowledged", attempts = attempts,
                acknowledgedAtMs = now, deletionReceipt = result.deletionReceipt)
            ReportDeliveryResult.Rejected -> old.copy(status = "rejected", attempts = attempts)
            ReportDeliveryResult.Retryable -> old.copy(attempts = attempts,
                nextAttemptAtMs = now + if (attempts == 1) 30_000 else 120_000)
        }
        write(updated)
        return updated
    }

    @Synchronized
    fun retry(id: String): AiResponseReport {
        val old = requireNotNull(get(id))
        require(old.status != "acknowledged")
        return old.copy(status = "queued_local", attempts = 0, nextAttemptAtMs = 0).also(::write)
    }

    private fun write(report: AiResponseReport) {
        dir.mkdirs()
        val target = File(dir, "${report.id}.json")
        val temp = File(dir, "${report.id}.tmp")
        try {
            FileOutputStream(temp).use { stream ->
                stream.write(report.toJson().toString().toByteArray(Charsets.UTF_8))
                stream.fd.sync()
            }
            if (!temp.renameTo(target)) error("Could not save report")
        } finally {
            temp.delete()
        }
    }

    @Synchronized
    fun all(): List<AiResponseReport> = dir.listFiles { file -> file.extension == "json" }.orEmpty()
        .mapNotNull { file -> runCatching { parseReport(Json.parseToJsonElement(file.readText()) as JsonObject) }.getOrNull() }
        .sortedBy { it.createdAtMs }

    private fun AiResponseReport.toJson() = buildJsonObject {
        put("id", id); put("conversationId", reference.conversationId); put("runId", reference.runId)
        put("messageKey", reference.messageKey); put("response", response); put("reason", reason)
        put("note", note); put("createdAtMs", createdAtMs); put("status", status)
        put("attempts", attempts); put("nextAttemptAtMs", nextAttemptAtMs)
        put("acknowledgedAtMs", acknowledgedAtMs); put("deletionReceipt", deletionReceipt)
    }

    private fun parseReport(o: JsonObject): AiResponseReport {
        fun text(key: String) = (o[key] as? JsonPrimitive)?.contentOrNull
        return AiResponseReport(
            id = requireNotNull(text("id")),
            reference = AiResponseReference(requireNotNull(text("conversationId")), text("runId"), requireNotNull(text("messageKey"))),
            response = requireNotNull(text("response")), reason = requireNotNull(text("reason")), note = text("note").orEmpty(),
            createdAtMs = (o["createdAtMs"] as? JsonPrimitive)?.longOrNull ?: error("Missing date"),
            status = requireNotNull(text("status")),
            attempts = (o["attempts"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: 0,
            nextAttemptAtMs = (o["nextAttemptAtMs"] as? JsonPrimitive)?.longOrNull ?: 0,
            acknowledgedAtMs = (o["acknowledgedAtMs"] as? JsonPrimitive)?.longOrNull,
            deletionReceipt = text("deletionReceipt"),
        )
    }

    private companion object {
        const val MAX_RESPONSE = 4_000
        const val MAX_NOTE = 1_000
    }
}
