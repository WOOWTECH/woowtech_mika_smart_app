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
                queue.all().filter { it.status == "queued_local" && it.attempts < MAX_ATTEMPTS && it.nextAttemptAtMs <= now() }
                    .forEach { report ->
                        val current = queue.get(report.id) ?: return@forEach
                        if (current.status == "queued_local" && current.attempts < MAX_ATTEMPTS && current.nextAttemptAtMs <= now()) {
                            queue.recordAttempt(current.id, sender.send(current), now())
                        }
                    }
            }
        }
    }
}
