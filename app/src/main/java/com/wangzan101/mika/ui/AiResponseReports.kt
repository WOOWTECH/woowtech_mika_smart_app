package com.wangzan101.mika.ui

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
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

internal fun reportOutsideIntakeWindow(report: AiResponseReport, now: Long): Boolean {
    val windowMs = 7L * 24 * 60 * 60 * 1_000
    return report.createdAtMs < now - windowMs || report.createdAtMs > now + windowMs
}

internal class AiResponseReportQueue(private val dir: File) {
    constructor(context: Context) : this(File(context.filesDir, "ai-response-reports"))

    fun save(reference: AiResponseReference, response: String, reason: String, note: String): AiResponseReport = synchronized(lock) {
        require(reason in setOf("offensive", "unsafe", "other"))
        require(response.isNotBlank())
        find(reference)?.let { return@synchronized it }
        val report = AiResponseReport(UUID.randomUUID().toString(), reference, response.take(MAX_RESPONSE), reason,
            note.trim().take(MAX_NOTE), System.currentTimeMillis())
        write(report)
        report
    }

    fun get(id: String): AiResponseReport? = synchronized(lock) { all().firstOrNull { it.id == id } }

    // Prefer an acknowledgement if older versions left multiple reports for the same response.
    fun find(reference: AiResponseReference): AiResponseReport? = synchronized(lock) {
        val scan = scan()
        check(reference !in scan.damagedReferences)
        val matches = scan.reports.filter { it.reference == reference }
        matches.firstOrNull { it.status == "acknowledged" } ?: matches.firstOrNull()
    }

    fun recordAttempt(id: String, result: ReportDeliveryResult, now: Long): AiResponseReport = synchronized(lock) {
        val old = requireNotNull(get(id))
        if (old.status == "acknowledged") return@synchronized old
        val attempts = old.attempts + 1
        val updated = when (result) {
            is ReportDeliveryResult.Acknowledged -> old.copy(status = "acknowledged", attempts = attempts,
                acknowledgedAtMs = now, deletionReceipt = result.deletionReceipt)
            ReportDeliveryResult.Rejected -> old.copy(status = "rejected", attempts = attempts)
            ReportDeliveryResult.Retryable -> old.copy(attempts = attempts,
                nextAttemptAtMs = now + if (attempts == 1) 30_000 else 120_000)
        }
        write(updated)
        updated
    }

    fun retry(id: String): AiResponseReport = synchronized(lock) {
        val old = requireNotNull(get(id))
        if (old.status == "acknowledged") old
        else old.copy(status = "queued_local", attempts = 0, nextAttemptAtMs = 0).also(::write)
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

    fun all(): List<AiResponseReport> = synchronized(lock) {
        val scan = scan()
        scan.reports.filterNot { it.reference in scan.damagedReferences }
    }

    private data class Scan(val reports: List<AiResponseReport>, val damagedReferences: Set<AiResponseReference>)

    // A damaged record with no readable reference could be an acknowledged duplicate of any
    // report. Fail closed in that case; a known reference only blocks reports for that response.
    private fun scan(): Scan {
        if (!dir.exists()) return Scan(emptyList(), emptySet())
        require(dir.isDirectory)
        val reports = mutableListOf<AiResponseReport>()
        val damaged = mutableSetOf<AiResponseReference>()
        for (file in requireNotNull(dir.listFiles { file -> file.extension == "json" })) {
            val json = Json.parseToJsonElement(file.readText()) as JsonObject
            val report = runCatching {
                parseReport(json).also {
                    require(it.id == file.nameWithoutExtension && UUID.fromString(it.id).toString() == it.id)
                    require(it.status in setOf("queued_local", "rejected", "acknowledged"))
                    require(it.reason in setOf("offensive", "unsafe", "other") && it.response.isNotBlank())
                    require(it.attempts >= 0)
                }
            }.getOrNull()
            if (report != null) reports += report
            else damaged += parseReference(json)
        }
        return Scan(reports.sortedWith(compareBy({ it.createdAtMs }, { it.id })), damaged)
    }

    private fun AiResponseReport.toJson() = buildJsonObject {
        put("id", id); put("conversationId", reference.conversationId); put("runId", reference.runId)
        put("messageKey", reference.messageKey); put("response", response); put("reason", reason)
        put("note", note); put("createdAtMs", createdAtMs); put("status", status)
        put("attempts", attempts); put("nextAttemptAtMs", nextAttemptAtMs)
        put("acknowledgedAtMs", acknowledgedAtMs); put("deletionReceipt", deletionReceipt)
    }

    private fun parseReference(o: JsonObject): AiResponseReference {
        fun text(key: String): String {
            val value = o[key] as? JsonPrimitive ?: error("Missing reference")
            require(value.isString)
            return requireNotNull(value.contentOrNull)
        }
        val run = requireNotNull(o["runId"])
        val runId = if (run is JsonNull) null else text("runId")
        return AiResponseReference(text("conversationId"), runId, text("messageKey"))
    }

    private fun parseReport(o: JsonObject): AiResponseReport {
        fun text(key: String) = (o[key] as? JsonPrimitive)?.contentOrNull
        return AiResponseReport(
            id = requireNotNull(text("id")),
            reference = parseReference(o),
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
        val lock = Any()
        const val MAX_RESPONSE = 4_000
        const val MAX_NOTE = 1_000
    }
}
