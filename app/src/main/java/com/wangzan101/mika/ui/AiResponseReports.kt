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
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** messageKey is a UI location; answerId is stable when the run has an ID. */
internal data class AiResponseReference(
    val conversationId: String, val runId: String?, val messageKey: String,
    val answerId: String? = null, val savedSteerIndex: Int? = null,
)

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
    val exchange = exchanges[turn]
    val steer = if (key.startsWith("a")) exchange.steers.first { it.id == key.substringAfter('-') } else null
    val answerId = when {
        steer != null && (exchange.runId != null || !steer.id.startsWith("turn-")) -> "steer:${steer.id}"
        steer == null && exchange.runId != null -> "final"
        else -> null
    }
    return AiResponseReference(conversationId, exchange.runId, key, answerId, steer?.savedIndex)
}

private enum class ReferenceMatch { Same, Different, Ambiguous }
internal class AmbiguousReportReferenceException : IllegalStateException()
internal class UnidentifiedReportException : IllegalStateException()
internal class DamagedReportReferenceException : IllegalStateException()

private fun compareReferences(a: AiResponseReference, b: AiResponseReference): ReferenceMatch {
    if (a.conversationId != b.conversationId) return ReferenceMatch.Different
    fun identity(r: AiResponseReference): String = r.answerId ?: when {
        r.messageKey.startsWith("r") -> "final"
        r.messageKey.startsWith("a") -> "steer:${r.messageKey.substringAfter('-', "") }"
        else -> "unknown"
    }
    val ai = identity(a)
    val bi = identity(b)
    if (a.runId != b.runId) {
        if (a.runId != null && b.runId != null) return ReferenceMatch.Different
        if (ai.startsWith("steer:") && bi.startsWith("steer:") &&
            !ai.startsWith("steer:turn-") && !bi.startsWith("steer:turn-")) {
            return if (ai == bi) ReferenceMatch.Same else ReferenceMatch.Different
        }
        return if (ai == "final" && bi == "final" || ai.startsWith("steer:") && bi.startsWith("steer:"))
            ReferenceMatch.Ambiguous else ReferenceMatch.Different
    }
    if (a.runId == null) {
        if (a.messageKey == b.messageKey) return ReferenceMatch.Same
        if (ai == "final" && bi == "final") return ReferenceMatch.Ambiguous
        if (ai.startsWith("steer:") && bi.startsWith("steer:") &&
            (ai.startsWith("steer:turn-") || bi.startsWith("steer:turn-"))) return ReferenceMatch.Ambiguous
        return if (ai == bi && ai.startsWith("steer:")) ReferenceMatch.Same else ReferenceMatch.Different
    }
    if (ai == bi && ai != "unknown") return ReferenceMatch.Same
    if (!ai.startsWith("steer:") || !bi.startsWith("steer:")) return ReferenceMatch.Different
    fun legacyIndex(id: String): Int? = id.removePrefix("steer:").removePrefix("turn-")
        .toIntOrNull()?.takeIf { id.startsWith("steer:turn-") && it >= 0 }
    val aIndex = legacyIndex(ai)
    val bIndex = legacyIndex(bi)
    if (aIndex != null && bIndex != null) return ReferenceMatch.Different
    if (aIndex == null && bIndex == null) return ReferenceMatch.Different
    val named = if (aIndex != null) b else a
    val index = aIndex ?: requireNotNull(bIndex)
    if (named.savedSteerIndex != null) return if (named.savedSteerIndex == index) ReferenceMatch.Same else ReferenceMatch.Different
    return ReferenceMatch.Ambiguous
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
    val manualOnly: Boolean = false,
    val replacementOf: String? = null,
)

internal fun reportOutsideIntakeWindow(report: AiResponseReport, now: Long): Boolean {
    val windowMs = 7L * 24 * 60 * 60 * 1_000
    return report.createdAtMs < now - windowMs || report.createdAtMs > now + windowMs
}

internal class AiResponseReportQueue(private val dir: File) {
    constructor(context: Context) : this(File(context.filesDir, "ai-response-reports"))

    fun save(reference: AiResponseReference, response: String, reason: String, note: String,
        allowUnidentified: Boolean = false): AiResponseReport = synchronized(lock) {
        require(reason in setOf("offensive", "unsafe", "other"))
        require(response.isNotBlank())
        find(reference, allowUnidentified)?.let { return@synchronized it }
        val report = AiResponseReport(UUID.randomUUID().toString(), reference, response.take(MAX_RESPONSE), reason,
            note.trim().take(MAX_NOTE), System.currentTimeMillis())
        write(report)
        report
    }

    fun get(id: String, allowUnidentified: Boolean = false): AiResponseReport? = synchronized(lock) {
        all(allowUnidentified).firstOrNull { it.id == id }
    }

    // Prefer an acknowledgement if older versions left multiple reports for the same response.
    fun find(reference: AiResponseReference, allowUnidentified: Boolean = false,
        promote: Boolean = true): AiResponseReport? = synchronized(lock) {
        val scan = scan()
        if (scan.unidentified && !allowUnidentified) throw UnidentifiedReportException()
        if (scan.damagedReferences.any { compareReferences(it, reference) != ReferenceMatch.Different })
            throw DamagedReportReferenceException()
        val comparisons = scan.reports.filterNot { it.manualOnly }.map { it to compareReferences(it.reference, reference) }
        if (comparisons.any { it.second == ReferenceMatch.Ambiguous }) throw AmbiguousReportReferenceException()
        val matches = comparisons.filter { it.second == ReferenceMatch.Same }.map { it.first }
        val steerId = reference.answerId?.takeIf { it.startsWith("steer:") }?.removePrefix("steer:")
            ?: reference.messageKey.takeIf { it.startsWith("a") }?.substringAfter('-', "")
        if (reference.runId == null && (steerId.isNullOrEmpty() || steerId.startsWith("turn-")) && matches.size > 1)
            throw AmbiguousReportReferenceException()
        // Keep the evidence and ID, and add the proven stable identity for future background delivery.
        val promoted = matches.map { report ->
            val updated = if (!promote || reference.answerId == null) report else report.copy(reference = report.reference.copy(
                answerId = reference.answerId, savedSteerIndex = report.reference.savedSteerIndex ?: reference.savedSteerIndex))
            if (updated != report) write(updated)
            updated
        }
        promoted.firstOrNull { it.status == "acknowledged" } ?: promoted.firstOrNull()
    }

    fun recordAttempt(id: String, result: ReportDeliveryResult, now: Long,
        allowUnidentified: Boolean = false): AiResponseReport = synchronized(lock) {
        val old = requireNotNull(get(id, allowUnidentified))
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

    fun retry(id: String, allowUnidentified: Boolean = false): AiResponseReport = synchronized(lock) {
        val old = requireNotNull(get(id, allowUnidentified))
        if (old.status == "acknowledged") old
        else old.copy(status = "queued_local", attempts = 0, nextAttemptAtMs = 0).also(::write)
    }

    /** Independent reports are only sent when the user explicitly submits or retries them. */
    fun createManual(reference: AiResponseReference, response: String, reason: String, note: String,
        replacementOf: String? = null, now: Long = System.currentTimeMillis()): AiResponseReport = synchronized(lock) {
        require(reason in setOf("offensive", "unsafe", "other") && response.isNotBlank())
        AiResponseReport(UUID.randomUUID().toString(), reference, response.take(MAX_RESPONSE), reason,
            note.trim().take(MAX_NOTE), now, manualOnly = true, replacementOf = replacementOf).also(::write)
    }

    fun manualReports(conversationId: String, allowUnidentified: Boolean = false): List<AiResponseReport> = synchronized(lock) {
        val scan = scan()
        if (scan.unidentified && !allowUnidentified) throw UnidentifiedReportException()
        scan.reports.filter { it.manualOnly && it.reference.conversationId == conversationId }.asReversed()
    }

    /** A new independent submission pauses automatic sends of any possibly related old record. */
    fun autoBlockedByManual(report: AiResponseReport, allowUnidentified: Boolean = false): Boolean = synchronized(lock) {
        val scan = scan()
        if (scan.unidentified && !allowUnidentified) throw UnidentifiedReportException()
        scan.reports.any { it.manualOnly && compareReferences(it.reference, report.reference) != ReferenceMatch.Different }
    }

    fun getManual(id: String, allowUnidentified: Boolean = false): AiResponseReport? = synchronized(lock) {
        val scan = scan()
        if (scan.unidentified && !allowUnidentified) throw UnidentifiedReportException()
        scan.reports.firstOrNull { it.id == id && it.manualOnly }
    }

    fun recordManualAttempt(id: String, result: ReportDeliveryResult, now: Long,
        allowUnidentified: Boolean = false): AiResponseReport = synchronized(lock) {
        val old = requireNotNull(getManual(id, allowUnidentified))
        if (old.status == "acknowledged") return@synchronized old
        val attempts = old.attempts + 1
        val updated = when (result) {
            is ReportDeliveryResult.Acknowledged -> old.copy(status = "acknowledged", attempts = attempts,
                acknowledgedAtMs = now, deletionReceipt = result.deletionReceipt)
            ReportDeliveryResult.Rejected -> old.copy(status = "rejected", attempts = attempts)
            ReportDeliveryResult.Retryable -> old.copy(status = "queued_local", attempts = attempts)
        }
        write(updated)
        updated
    }

    private fun write(report: AiResponseReport) {
        dir.mkdirs()
        val name = if (report.manualOnly) "manual-${report.id}" else report.id
        val target = File(dir, "$name.json")
        val temp = File(dir, "$name.tmp")
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

    fun all(allowUnidentified: Boolean = false): List<AiResponseReport> = synchronized(lock) {
        val scan = scan()
        if (scan.unidentified && !allowUnidentified) throw UnidentifiedReportException()
        scan.reports.filterNot { report -> scan.damagedReferences.any { compareReferences(it, report.reference) != ReferenceMatch.Different } }
    }

    private data class Scan(val reports: List<AiResponseReport>, val damagedReferences: Set<AiResponseReference>, val unidentified: Boolean)

    // A damaged record with no readable reference could be an acknowledged duplicate of any
    // report. Fail closed in that case; a known reference only blocks reports for that response.
    private fun scan(): Scan {
        if (!dir.exists()) return Scan(emptyList(), emptySet(), false)
        require(dir.isDirectory)
        val reports = mutableListOf<AiResponseReport>()
        val damaged = mutableSetOf<AiResponseReference>()
        var unidentified = false
        for (file in requireNotNull(dir.listFiles { file -> file.extension == "json" })) {
            val json = runCatching { Json.parseToJsonElement(file.readText()) as JsonObject }.getOrNull()
            if (json == null) { unidentified = true; continue }
            val report = runCatching {
                parseReport(json).also {
                    val name = file.nameWithoutExtension
                    val manualFile = name.startsWith("manual-")
                    require(it.manualOnly == manualFile && it.id == (if (manualFile) name.removePrefix("manual-") else name))
                    require(UUID.fromString(it.id).toString() == it.id)
                    require(it.status in setOf("queued_local", "rejected", "acknowledged"))
                    require(it.reason in setOf("offensive", "unsafe", "other") && it.response.isNotBlank())
                    require(it.attempts >= 0)
                }
            }.getOrNull()
            if (report != null) reports += report
            else runCatching { parseReference(json) }.onSuccess { damaged += it }.onFailure { unidentified = true }
        }
        return Scan(reports.sortedWith(compareBy({ it.createdAtMs }, { it.id })), damaged, unidentified)
    }

    private fun AiResponseReport.toJson() = buildJsonObject {
        put("id", id); put("conversationId", reference.conversationId); put("runId", reference.runId)
        put("messageKey", reference.messageKey); put("response", response); put("reason", reason)
        reference.answerId?.let { put("answerId", it) }
        reference.savedSteerIndex?.let { put("savedSteerIndex", it) }
        put("note", note); put("createdAtMs", createdAtMs); put("status", status)
        put("attempts", attempts); put("nextAttemptAtMs", nextAttemptAtMs)
        put("acknowledgedAtMs", acknowledgedAtMs); put("deletionReceipt", deletionReceipt)
        if (manualOnly) put("manualOnly", true)
        replacementOf?.let { put("replacementOf", it) }
    }

    private fun parseReference(o: JsonObject): AiResponseReference {
        fun text(key: String): String {
            val value = o[key] as? JsonPrimitive ?: error("Missing reference")
            require(value.isString)
            return requireNotNull(value.contentOrNull)
        }
        val run = requireNotNull(o["runId"])
        val runId = if (run is JsonNull) null else text("runId")
        val index = (o["savedSteerIndex"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull()
        val answerId = (o["answerId"] as? JsonPrimitive)?.contentOrNull
        return AiResponseReference(text("conversationId"), runId, text("messageKey"), answerId, index)
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
            manualOnly = o["manualOnly"]?.let { (it as? JsonPrimitive)?.booleanOrNull ?: error("Invalid manual flag") } ?: false,
            replacementOf = text("replacementOf"),
        )
    }

    private companion object {
        val lock = Any()
        const val MAX_RESPONSE = 4_000
        const val MAX_NOTE = 1_000
    }
}
