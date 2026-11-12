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

/** No transport exists yet. Every saved item remains explicitly queued on this device. */
internal data class AiResponseReport(
    val id: String,
    val reference: AiResponseReference,
    val response: String,
    val reason: String,
    val note: String,
    val createdAtMs: Long,
    val status: String = "queued_local",
)

internal class AiResponseReportQueue(private val dir: File) {
    constructor(context: Context) : this(File(context.filesDir, "ai-response-reports"))

    @Synchronized
    fun save(reference: AiResponseReference, response: String, reason: String, note: String): AiResponseReport {
        require(reason in setOf("offensive", "unsafe", "other"))
        require(response.isNotBlank())
        val report = AiResponseReport(UUID.randomUUID().toString(), reference, response.take(MAX_RESPONSE), reason,
            note.trim().take(MAX_NOTE), System.currentTimeMillis())
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
        return report
    }

    fun all(): List<AiResponseReport> = dir.listFiles { file -> file.extension == "json" }.orEmpty()
        .mapNotNull { file -> runCatching { parseReport(Json.parseToJsonElement(file.readText()) as JsonObject) }.getOrNull() }
        .sortedBy { it.createdAtMs }

    private fun AiResponseReport.toJson() = buildJsonObject {
        put("id", id); put("conversationId", reference.conversationId); put("runId", reference.runId)
        put("messageKey", reference.messageKey); put("response", response); put("reason", reason)
        put("note", note); put("createdAtMs", createdAtMs); put("status", status)
    }

    private fun parseReport(o: JsonObject): AiResponseReport {
        fun text(key: String) = (o[key] as? JsonPrimitive)?.contentOrNull
        return AiResponseReport(
            id = requireNotNull(text("id")),
            reference = AiResponseReference(requireNotNull(text("conversationId")), text("runId"), requireNotNull(text("messageKey"))),
            response = requireNotNull(text("response")), reason = requireNotNull(text("reason")), note = text("note").orEmpty(),
            createdAtMs = (o["createdAtMs"] as? JsonPrimitive)?.longOrNull ?: error("Missing date"),
            status = requireNotNull(text("status")),
        )
    }

    private companion object {
        const val MAX_RESPONSE = 4_000
        const val MAX_NOTE = 1_000
    }
}
