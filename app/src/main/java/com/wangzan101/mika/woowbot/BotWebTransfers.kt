package com.wangzan101.mika.woowbot

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.OutputStream
import java.util.concurrent.TimeUnit

/** No global cookie jar, redirects, proxy endpoints or certificate bypass. Caller supplies one profile's cookie. */
internal object BotWebTransfers {
    private const val MAX_DOWNLOAD = 100L * 1024 * 1024
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES).build()

    fun download(service: BotService, url: String, cookie: String?, output: OutputStream) {
        require(url.length <= BotOrigin.MAX_URL && service.policy.allows(url))
        val request = Request.Builder().url(url).header("Origin", service.origin).apply {
            if (!cookie.isNullOrEmpty()) header("Cookie", cookie)
        }.build()
        client.newCall(request).execute().use { response ->
            require(response.isSuccessful)
            val body = requireNotNull(response.body)
            require(body.contentLength() <= MAX_DOWNLOAD)
            body.byteStream().use { input ->
                val buffer = ByteArray(8192)
                var size = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count == -1) break
                    size += count
                    require(size <= MAX_DOWNLOAD)
                    output.write(buffer, 0, count)
                }
            }
        }
    }

    fun revoke(service: BotService, cookie: String?): Boolean {
        if (cookie.isNullOrEmpty()) return false
        val request = Request.Builder().url(service.origin + "/api/auth/logout")
            .header("Origin", service.origin).header("Cookie", cookie)
            .post(ByteArray(0).toRequestBody()).build()
        return runCatching { client.newCall(request).execute().use { it.isSuccessful } }.getOrDefault(false)
    }
}
