package com.wangzan101.mika.ui

import android.content.Context
import com.wangzan101.mika.R
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

internal sealed interface ReportDeliveryResult {
    data class Acknowledged(val deletionReceipt: String?) : ReportDeliveryResult
    data object Retryable : ReportDeliveryResult
    data object Rejected : ReportDeliveryResult
}

internal class ExistingManualReportException(val report: AiResponseReport) : IllegalStateException()

/** The relay's public intake accepts reports without a device token or pairing. */
internal class AiResponseReportSender(
    private val endpoint: String,
    private val client: OkHttpClient = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).build(),
) {
    fun send(report: AiResponseReport): ReportDeliveryResult {
        val url = endpoint.toHttpUrlOrNull() ?: return ReportDeliveryResult.Retryable
        if (url.scheme != "https" && url.host !in setOf("localhost", "127.0.0.1")) return ReportDeliveryResult.Retryable
        val body = buildJsonObject {
            put("id", report.id)
            put("reason", report.reason)
            put("note", report.note)
            put("response", report.response)
            put("created_at_ms", report.createdAtMs)
        }.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
        val request = Request.Builder().url(url).post(body).build()
        return try {
            client.newCall(request).execute().use { response ->
                when (response.code) {
                    201 -> {
                        runCatching {
                            val json = Json.parseToJsonElement(response.peekBody(16_384).string()) as JsonObject
                            val id = (json["id"] as? JsonPrimitive)?.contentOrNull
                            val accepted = (json["accepted"] as? JsonPrimitive)?.booleanOrNull
                            if (id == report.id && accepted == true) {
                                ReportDeliveryResult.Acknowledged((json["deletion_receipt"] as? JsonPrimitive)?.contentOrNull)
                            } else ReportDeliveryResult.Retryable
                        }.getOrDefault(ReportDeliveryResult.Retryable)
                    }
                    408, 429 -> ReportDeliveryResult.Retryable
                    in 500..599 -> ReportDeliveryResult.Retryable
                    else -> ReportDeliveryResult.Rejected
                }
            }
        } catch (_: IOException) {
            ReportDeliveryResult.Retryable
        }
    }
}

internal object AiResponseReportDelivery {
    private const val MAX_ATTEMPTS = 3
    private val mutex = Mutex()

    fun sender(context: Context): AiResponseReportSender {
        val base = context.getString(R.string.relay_gateway_default).trim().trimEnd('/')
        return AiResponseReportSender(if (base.isEmpty()) "" else "$base/api/v1/ai-reports")
    }

    suspend fun deliverDue(queue: AiResponseReportQueue, sender: AiResponseReportSender, now: () -> Long = System::currentTimeMillis) {
        mutex.withLock {
            withContext(Dispatchers.IO) {
                queue.all().filter { !it.manualOnly && !reportOutsideIntakeWindow(it, now()) &&
                    it.status == "queued_local" && it.attempts < MAX_ATTEMPTS && it.nextAttemptAtMs <= now() }
                    .forEach { report ->
                        val current = queue.get(report.id) ?: return@forEach
                        if (queue.autoBlockedByManual(current)) return@forEach
                        val selected = try { queue.find(current.reference) } catch (_: AmbiguousReportReferenceException) { null }
                        if (selected?.id == current.id && !current.manualOnly &&
                            !reportOutsideIntakeWindow(current, now()) && current.status == "queued_local" &&
                            current.attempts < MAX_ATTEMPTS && current.nextAttemptAtMs <= now()) {
                            queue.recordAttempt(current.id, sender.send(current), now())
                        }
                    }
            }
        }
    }

    suspend fun retry(queue: AiResponseReportQueue, sender: AiResponseReportSender, id: String,
        allowUnidentified: Boolean = false): AiResponseReport =
        mutex.withLock {
            withContext(Dispatchers.IO) {
                val current = requireNotNull(queue.get(id, allowUnidentified))
                require(!current.manualOnly)
                val selected = requireNotNull(queue.find(current.reference, allowUnidentified))
                if (selected.status == "acknowledged" || reportOutsideIntakeWindow(selected, System.currentTimeMillis())) selected
                else {
                    val report = queue.retry(selected.id, allowUnidentified)
                    queue.recordAttempt(report.id, sender.send(report), System.currentTimeMillis(), allowUnidentified)
                }
            }
        }

    /** A user explicitly accepted the risk for this report; do not send unrelated queued reports. */
    suspend fun deliverOne(queue: AiResponseReportQueue, sender: AiResponseReportSender, id: String): AiResponseReport =
        mutex.withLock {
            withContext(Dispatchers.IO) {
                val current = requireNotNull(queue.get(id, allowUnidentified = true))
                require(!current.manualOnly)
                val selected = requireNotNull(queue.find(current.reference, allowUnidentified = true))
                if (selected.status != "queued_local" || queue.autoBlockedByManual(selected, allowUnidentified = true) ||
                    reportOutsideIntakeWindow(selected, System.currentTimeMillis()) || selected.attempts >= MAX_ATTEMPTS ||
                    selected.nextAttemptAtMs > System.currentTimeMillis()) selected
                else queue.recordAttempt(selected.id, sender.send(selected), System.currentTimeMillis(), allowUnidentified = true)
            }
        }

    /** Recheck the old report while no other delivery is in flight; never replace a known receipt. */
    suspend fun createManual(queue: AiResponseReportQueue, reference: AiResponseReference, response: String,
        reason: String, note: String, sourceId: String?, allowUnidentified: Boolean = false): AiResponseReport =
        mutex.withLock {
            withContext(Dispatchers.IO) {
                if (sourceId != null) {
                    val source = queue.getManual(sourceId, allowUnidentified) ?: requireNotNull(queue.get(sourceId, allowUnidentified))
                    val selected = if (source.manualOnly) source else requireNotNull(queue.find(source.reference, allowUnidentified, promote = false))
                    if (selected.status == "acknowledged") return@withContext selected
                    require(selected.id == source.id && reportOutsideIntakeWindow(source, System.currentTimeMillis()))
                    require(reference == source.reference && response == source.response)
                    val replacements = queue.manualReports(reference.conversationId, allowUnidentified)
                        .filter { it.replacementOf == sourceId }
                    replacements.firstOrNull { it.status == "acknowledged" }?.let { return@withContext it }
                    replacements.firstOrNull { !reportOutsideIntakeWindow(it, System.currentTimeMillis()) }?.let {
                        if (it.response != response || it.reason != reason || it.note != note.trim().take(1_000))
                            throw ExistingManualReportException(it)
                        return@withContext it
                    }
                }
                queue.createManual(reference, response, reason, note, sourceId)
            }
        }

    suspend fun sendManual(queue: AiResponseReportQueue, sender: AiResponseReportSender, id: String,
        allowUnidentified: Boolean = false): AiResponseReport = mutex.withLock {
        withContext(Dispatchers.IO) {
            val report = requireNotNull(queue.getManual(id, allowUnidentified))
            if (report.status == "acknowledged" || reportOutsideIntakeWindow(report, System.currentTimeMillis())) report
            else queue.recordManualAttempt(id, sender.send(report), System.currentTimeMillis(), allowUnidentified)
        }
    }
}
