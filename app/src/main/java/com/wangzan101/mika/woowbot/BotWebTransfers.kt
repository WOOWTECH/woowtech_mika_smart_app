package com.wangzan101.mika.woowbot

import com.wangzan101.mika.R
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.OutputStream
import java.util.concurrent.TimeUnit

/** No global cookie jar, redirects, proxy endpoints or certificate bypass. Caller supplies one profile's cookie. */
internal object BotWebTransfers {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES).build()
    /** Large files: no overall time limit, only the connect and per-read ones. */
    private val downloads = client.newBuilder().callTimeout(0, TimeUnit.SECONDS).build()

    class Head(val type: String?, val disposition: String?, val length: Long?, val url: String)

    /**
     * Downloads [url] into the stream [open] returns once the response headers are known (they decide the saved name and
     * type). Up to five redirects, for example to storage; only https, or the service's own LAN address. The profile's
     * cookie goes to the service's own origin only. [foreign] marks a download from another site the user agreed to.
     */
    fun download(service: BotService, url: String, cookie: String?, foreign: Boolean, limit: Long = BotDownloadLimits.DIRECT,
                 open: (Head) -> OutputStream, progress: (Long, Long?) -> Unit, active: () -> Boolean) {
        require(url.length <= BotOrigin.MAX_URL && (service.policy.allows(url) || foreign && url.startsWith("https://")))
        var target = url.toHttpUrl()
        var hops = 0
        while (true) {
            val own = service.policy.allows(target.toString())
            require(own || target.isHttps)
            val request = Request.Builder().url(target).apply {
                if (own) {
                    header("Origin", service.origin)
                    if (!cookie.isNullOrEmpty()) header("Cookie", cookie)
                }
            }.build()
            val response = downloads.newCall(request).execute()
            if (response.code in 300..399) {
                val location = response.header("Location")
                response.close()
                require(location != null && ++hops <= 5)
                target = requireNotNull(target.resolve(location))
                continue
            }
            response.use {
                if (!it.isSuccessful) throw BotDownloadException(R.string.bot_services_download_failed)
                val body = requireNotNull(it.body)
                val length = body.contentLength().takeIf { size -> size >= 0 }
                if (length != null && length > limit) throw BotDownloadException(R.string.bot_services_download_too_large, sizeLabel(limit))
                open(Head(it.header("Content-Type"), it.header("Content-Disposition"), length, target.toString())).use { out -> body.byteStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var size = 0L
                    while (true) {
                        if (!active()) throw java.util.concurrent.CancellationException("download cancelled")
                        val count = input.read(buffer)
                        if (count == -1) break
                        size += count
                        if (size > limit) throw BotDownloadException(R.string.bot_services_download_too_large, sizeLabel(limit))
                        out.write(buffer, 0, count)
                        progress(size, length)
                    }
                    if (length != null && size != length) throw BotDownloadException(R.string.bot_services_download_failed)
                } }
            }
            return
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
