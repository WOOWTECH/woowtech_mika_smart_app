package com.wangzan101.mika.core.woowbot.push

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

/** These objects hold credentials in memory only. Deliberately no data-class toString/copy. */
class BotPushCredentials(val serviceId: String, val profileEpoch: String, val origin: String, val cookie: String) {
    init {
        require(UUID.fromString(serviceId).toString() == serviceId)
        val url = origin.toHttpUrl()
        require(url.isHttps && url.username.isEmpty() && url.password.isEmpty() &&
            url.encodedPath == "/" && url.query == null && url.fragment == null && origin == url.toString().removeSuffix("/"))
        require(cookie.isNotBlank() && cookie.none { it == '\r' || it == '\n' })
    }
}
class BotPushSession(val credentials: BotPushCredentials, val id: String, val environmentId: String,
    val cookieOnly: Boolean, val ready: Boolean) {
    val binding = BotPushBinding(credentials.serviceId, MessageDigest.getInstance("SHA-256")
        .digest(JsonArray(listOf(credentials.profileEpoch, credentials.origin, environmentId, id).map(::JsonPrimitive))
            .toString().toByteArray()).joinToString("") { "%02x".format(it) })
}
class BotPushHttpResponse(val status: Int, val body: String)
fun interface BotPushHttpTransport {
    suspend fun request(credentials: BotPushCredentials, method: String, path: String, sessionId: String?, body: String?, beforeSend: suspend () -> Unit): BotPushHttpResponse
}

/** Dedicated client: no shared interceptors, cookie jar, redirects or credential logging. */
class BotPushOkHttpTransport : BotPushHttpTransport {
    private val retryAfter = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .retryOnConnectionFailure(false).callTimeout(20, TimeUnit.SECONDS).build()
    override suspend fun request(credentials: BotPushCredentials, method: String, path: String,
        sessionId: String?, body: String?, beforeSend: suspend () -> Unit): BotPushHttpResponse = withContext(Dispatchers.IO) {
        val preview = method == "GET" && BotPushHttpApi.isPreviewPath(path)
        require(path == "/api/auth/session" || path == BotPushHttpApi.PATH ||
            path == "${BotPushHttpApi.PATH}?serviceId=${credentials.serviceId}" || preview)
        if (System.currentTimeMillis() < (retryAfter[credentials.origin] ?: 0L)) throw BotPushHttpException(429)
        val request = Request.Builder().url(credentials.origin + path)
            .header("Cookie", credentials.cookie).header("Origin", credentials.origin)
            .header("Accept", "application/json").header("User-Agent", "Mozilla/5.0 WOOWTECH-Assistant")
        sessionId?.let { request.header("X-Woowtech-Session-Id", it) }
        request.method(method, body?.toRequestBody("application/json".toMediaType()))
        beforeSend()
        currentCoroutineContext().ensureActive()
        val call = client.newCall(request.build())
        // A blocking call ignores coroutine timeouts, so each kind of request bounds its own time: an unreachable service
        // must not hold back the others' notifications (2026-11-28: two unreachable PaaS labs, 20 s each).
        call.timeout().timeout(when {
            path == "/api/auth/session" -> DISCOVERY_TIMEOUT_MS
            preview -> PREVIEW_TIMEOUT_MS
            else -> 20_000L
        }, TimeUnit.MILLISECONDS)
        call.execute().use { response ->
            if (response.code == 429) {
                val now = System.currentTimeMillis()
                val header = response.header("Retry-After")
                val until = header?.toLongOrNull()?.takeIf { it >= 0 }?.let {
                    runCatching { Math.addExact(now, Math.multiplyExact(it, 1000L)) }.getOrDefault(Long.MAX_VALUE)
                } ?: runCatching { java.time.ZonedDateTime.parse(header,
                    java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
                retryAfter[credentials.origin] = maxOf(now + 30_000L, until ?: 0L)
            }
            val source = response.body?.source() ?: error("Missing push response")
            val limit = if (preview) PREVIEW_LIMIT else 65_536L
            source.request(limit + 1)
            check(source.buffer.size <= limit) { "Oversize push response" }
            BotPushHttpResponse(response.code, source.readUtf8())
        }
    }
}

private const val DISCOVERY_TIMEOUT_MS = 8_000L
private const val PREVIEW_TIMEOUT_MS = 5_000L
private const val PREVIEW_LIMIT = 1_048_576L

/** HTTP/status errors never include response bodies, cookies, tokens or request headers. */
class BotPushHttpException(val status: Int) : Exception("Push request failed ($status)")
class BotPushStaleException : Exception("Push identity or token epoch changed")

class BotPushHttpApi(
    private val transport: BotPushHttpTransport,
    private val resolve: suspend (BotPushBinding) -> BotPushSession?,
    private val isCurrent: suspend (BotPushCredentials) -> Boolean,
    private val tokenIsCurrent: () -> Boolean,
) : BotPushDeviceApi {
    suspend fun discover(credentials: BotPushCredentials): BotPushSession {
        val response = transport.request(credentials, "GET", "/api/auth/session", null, null, {})
        if (response.status != 200) throw BotPushHttpException(response.status)
        val json = Json.parseToJsonElement(response.body).jsonObject
        if (json.string("kind") != "session" || json.string("via") != "cookie" ||
            (json["scopes"] as? JsonArray)?.any { it == JsonPrimitive("client") } != true)
            throw BotPushNotReadyException()
        val id = json.string("id")?.takeIf { it.isNotBlank() && it.length <= 512 && it.all { c -> c.code in 33..126 } }
            ?: throw BotPushNotReadyException()
        val environment = json.string("environmentId")?.takeIf { it.isNotBlank() } ?: throw BotPushNotReadyException()
        val capability = (json["capabilities"] as? JsonObject)?.get("woowtechAndroidPush") == JsonPrimitive(1)
        val config = json["woowtechAndroidPush"] as? JsonObject
        val cookieOnly = (json["cookieOnly"] as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull
            ?: throw BotPushNotReadyException()
        // Do not trust a server-supplied arbitrary route, even when the capability is present.
        val valid = capability && config?.string("devicePath") == PATH && config.string("payloadVersion") == "1" &&
            config.string("auth") == "cookie" && config["acceptsCookieOnly"] == JsonPrimitive(true)
        if (!valid) throw BotPushNotReadyException()
        return BotPushSession(credentials, id, environment, cookieOnly,
            config?.get("enabled") == JsonPrimitive(true) && config["ready"] == JsonPrimitive(true))
    }
    private suspend fun session(binding: BotPushBinding): BotPushSession {
        val saved = resolve(binding) ?: throw BotPushStaleException()
        val actual = discover(saved.credentials) // Same captured cookie, never selectedService/new profile.
        if (actual.binding != binding) throw BotPushStaleException()
        return actual
    }
    private suspend fun guard(credentials: BotPushCredentials) {
        currentCoroutineContext().ensureActive()
        if (!isCurrent(credentials) || !tokenIsCurrent()) throw BotPushStaleException()
    }
    override suspend fun register(binding: BotPushBinding, token: String) {
        require(token.length in 20..4096 && token.all { it.code in 33..126 })
        val session = session(binding)
        if (!session.ready) throw BotPushNotReadyException()
        guard(session.credentials)
        val body = buildJsonObject {
            put("v", 1); put("platform", "fcm"); put("serviceId", binding.serviceId); put("token", token)
        }.toString()
        require(body.toByteArray().size <= 8192)
        val result = transport.request(session.credentials, "PUT", PATH, session.id, body) { guard(session.credentials) }
        // A stale response is ambiguous: the lifecycle must retain its ledger entry.
        guard(session.credentials)
        if (result.status == 503 && runCatching {
                Json.parseToJsonElement(result.body).jsonObject.string("code") == "push_not_ready"
            }.getOrDefault(false)) throw BotPushNotReadyException()
        validate(result, binding.serviceId, registered = true)
    }
    override suspend fun revoke(binding: BotPushBinding) {
        val session = session(binding)
        // Cleanup deliberately permits retired profiles/disabled capability flags, with the ORIGINAL cookie.
        val result = transport.request(session.credentials, "DELETE", "$PATH?serviceId=${binding.serviceId}", session.id, null, {})
        validate(result, null, registered = false)
    }
    suspend fun get(binding: BotPushBinding): JsonObject {
        val session = session(binding)
        val result = transport.request(session.credentials, "GET", PATH, session.id, null, {})
        if (result.status != 200) throw BotPushHttpException(result.status)
        val json = Json.parseToJsonElement(result.body).jsonObject
        check(json.keys == RESPONSE_KEYS)
        val state = json.string("state")
        check(json["v"] == JsonPrimitive(1) && state in setOf("absent", "pending", "registered"))
        check(json["registered"] == JsonPrimitive(state == "registered"))
        if (state == "absent") check(json["serviceId"] == JsonNull && json["registrationId"] == JsonNull)
        else check(json.string("serviceId") == binding.serviceId && canonicalUuid(json.string("registrationId")))
        return json // pending is not an instruction to PUT; the durable ledger controls cleanup.
    }
    private fun validate(response: BotPushHttpResponse, serviceId: String?, registered: Boolean) {
        if (response.status != 200) throw BotPushHttpException(response.status)
        val json = Json.parseToJsonElement(response.body).jsonObject
        check(json.keys == RESPONSE_KEYS)
        check(json["v"] == JsonPrimitive(1) && json["registered"] == JsonPrimitive(registered))
        check(json.string("state") == if (registered) "registered" else "absent")
        if (registered) check(json.string("serviceId") == serviceId && canonicalUuid(json.string("registrationId")))
        else check(json["serviceId"] == JsonNull && json["registrationId"] == JsonNull)
    }
    /**
     * The bot's name and the start of its latest reply for a notification, read with the verified session (owner
     * 2026-11-28). Two fixed GETs of the website's own API; any failure leaves that part out.
     */
    suspend fun preview(credentials: BotPushCredentials, botId: String, threadId: String): BotPushPreview? = coroutineScope {
        require(BotPushContract.validId(botId) && BotPushContract.validId(threadId))
        val bots = async { runCatching { transport.request(credentials, "GET", BOTS_PATH, null, null, {}) }.getOrNull() }
        val messages = async { runCatching { transport.request(credentials, "GET", messagesPath(threadId), null, null, {}) }.getOrNull() }
        val name = bots.await()?.takeIf { it.status == 200 }?.let { BotPushPreviewText.name(it.body, botId) }
        val excerpt = messages.await()?.takeIf { it.status == 200 }?.let { BotPushPreviewText.excerpt(it.body) }
        if (name == null && excerpt == null) null else BotPushPreview(name, excerpt)
    }
    companion object {
        const val PATH = "/api/woowtech/android-push/device"
        const val BOTS_PATH = "/api/bots?messages=1"
        private val RESPONSE_KEYS = setOf("v", "serviceId", "registrationId", "state", "registered")
        private val MESSAGES_PATH = Regex("/api/threads/[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}/messages\\?limit=8")
        fun messagesPath(threadId: String) = "/api/threads/$threadId/messages?limit=8"
        fun isPreviewPath(path: String) = path == BOTS_PATH || MESSAGES_PATH.matches(path)
    }
}
private fun JsonObject.string(key: String): String? = (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun canonicalUuid(value: String?): Boolean = value != null && runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)
