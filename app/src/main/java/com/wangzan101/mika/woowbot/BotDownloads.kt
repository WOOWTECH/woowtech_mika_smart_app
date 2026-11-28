package com.wangzan101.mika.woowbot

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import android.webkit.WebView
import com.wangzan101.mika.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.URI
import java.nio.charset.Charset
import java.util.Base64
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume

/**
 * Owner 2026-11-28: every file type a woowtechbot service offers downloads on the phone (images, video, audio, PDF, Word,
 * Excel, HTML, ZIP, …). Downloads come as the service's own URLs (possibly redirected to storage), as object URLs the page
 * made itself (`blob:`), as `data:` URLs, or, after the user agrees, as another site's https URL. All of them land in the
 * phone's Downloads folder.
 */
internal object BotDownloadLimits {
    const val DIRECT = 2L * 1024 * 1024 * 1024
    const val BLOB = 2L * 1024 * 1024 * 1024
    /** A data: URL reaches the app as one string, decoded in memory. */
    const val DATA = 32L * 1024 * 1024
    /** A download the page starts by itself is taken only this long after the user last touched it (as on iOS). */
    const val GESTURE_MS = 60_000L
}

internal class BotDownloadException(val reason: Int, val arg: String? = null) : Exception("download failed")

/** File names and types. Pure (system lookups are passed in), so it is unit tested. */
internal object BotDownloadNames {
    /** Preferred extension first for each type. */
    private val table = listOf(
        "jpg" to "image/jpeg", "jpeg" to "image/jpeg", "png" to "image/png", "gif" to "image/gif", "webp" to "image/webp",
        "heic" to "image/heic", "heif" to "image/heif", "avif" to "image/avif", "svg" to "image/svg+xml", "bmp" to "image/bmp",
        "tif" to "image/tiff", "tiff" to "image/tiff", "ico" to "image/x-icon",
        "mp4" to "video/mp4", "mov" to "video/quicktime", "m4v" to "video/x-m4v", "webm" to "video/webm",
        "mkv" to "video/x-matroska", "avi" to "video/x-msvideo", "3gp" to "video/3gpp", "mpg" to "video/mpeg", "mpeg" to "video/mpeg",
        "mp3" to "audio/mpeg", "m4a" to "audio/mp4", "aac" to "audio/aac", "wav" to "audio/wav", "ogg" to "audio/ogg",
        "oga" to "audio/ogg", "opus" to "audio/opus", "flac" to "audio/flac", "amr" to "audio/amr", "weba" to "audio/webm",
        "pdf" to "application/pdf", "doc" to "application/msword",
        "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" to "application/vnd.ms-excel", "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt" to "application/vnd.ms-powerpoint", "pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt" to "application/vnd.oasis.opendocument.text", "ods" to "application/vnd.oasis.opendocument.spreadsheet",
        "odp" to "application/vnd.oasis.opendocument.presentation", "rtf" to "application/rtf", "epub" to "application/epub+zip",
        "txt" to "text/plain", "md" to "text/markdown", "csv" to "text/csv", "tsv" to "text/tab-separated-values",
        "html" to "text/html", "htm" to "text/html", "css" to "text/css", "js" to "text/javascript", "json" to "application/json",
        "xml" to "application/xml", "ics" to "text/calendar", "vcf" to "text/vcard", "yaml" to "application/yaml", "yml" to "application/yaml",
        "zip" to "application/zip", "rar" to "application/vnd.rar", "7z" to "application/x-7z-compressed", "tar" to "application/x-tar",
        "gz" to "application/gzip", "tgz" to "application/gzip", "bz2" to "application/x-bzip2", "xz" to "application/x-xz",
        "apk" to "application/vnd.android.package-archive",
    )
    private val byExtension = table.toMap()
    private val byType: Map<String, String> = table.map { it.second }.distinct().associateWith { t -> table.first { it.second == t }.first }
    private val generic = setOf("", "application/octet-stream", "binary/octet-stream", "application/unknown", "application/force-download",
        "application/x-download", "application/download")
    const val MAX_NAME = 120

    fun extension(name: String): String? = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        .takeIf { it.isNotEmpty() && it.length <= 10 && name.lastIndexOf('.') > 0 && it.all { c -> c.isLetterOrDigit() } }

    fun normalize(type: String?): String = type.orEmpty().substringBefore(';').trim().lowercase(Locale.ROOT)

    /** RFC 6266 / 5987: `filename*` (charset'language'percent-encoded) wins over `filename`. */
    fun fromDisposition(value: String?): String? {
        if (value.isNullOrBlank()) return null
        val params = parameters(value)
        params["filename*"]?.let { extended -> decodeExtended(extended)?.takeIf { it.isNotBlank() }?.let { return it } }
        return params["filename"]?.takeIf { it.isNotBlank() }
    }

    fun sanitize(raw: String): String {
        var name = raw.substringAfterLast('/').substringAfterLast('\\')
        name = name.filterNot { it.isISOControl() || it in "<>:\"|?*" || it in '‪'..'‮' || it in '⁦'..'⁩' ||
            it == '‎' || it == '‏' }
        name = name.trim().trim('.').trim()
        if (name.isEmpty()) name = "download"
        if (name.length > MAX_NAME) {
            val keep = extension(name)?.let { ".$it" }.orEmpty()
            name = name.take(MAX_NAME - keep.length).trimEnd() + keep
        }
        return name
    }

    /**
     * The name and type a download is saved with. The name comes from the page's `<a download>`, then Content-Disposition,
     * then the URL's last path segment. A known extension decides the type (so the saved file opens with the right app and
     * the system keeps its name); otherwise the given type, adding its extension when the name has none.
     */
    fun resolve(
        explicit: String?, disposition: String?, url: String?, type: String?,
        systemType: (String) -> String? = { null }, systemExtension: (String) -> String? = { null },
    ): Pair<String, String> {
        val fromUrl = url?.takeIf { it.startsWith("https://", true) || it.startsWith("http://", true) }?.let { link ->
            runCatching { URI(link).rawPath.orEmpty().substringAfterLast('/') }.getOrNull()?.let(::percentDecode)
        }
        var name = sanitize(listOfNotNull(explicit, fromDisposition(disposition), fromUrl).firstOrNull { it.isNotBlank() } ?: "download")
        val given = normalize(type).takeIf { it !in generic && '/' in it }
        val ext = extension(name)
        val byName = ext?.let { byExtension[it] ?: systemType(it) }
        val chosen = byName ?: given ?: "application/octet-stream"
        if (ext == null && given != null) (byType[given] ?: systemExtension(given))?.let { name = sanitize("$name.$it") }
        return name to chosen
    }

    private fun parameters(value: String): Map<String, String> {
        val out = mutableMapOf<String, String>()
        var i = value.indexOf(';').takeIf { it >= 0 } ?: return out
        while (i < value.length) {
            i++
            while (i < value.length && value[i] == ' ') i++
            val eq = value.indexOf('=', i).takeIf { it >= 0 } ?: break
            val key = value.substring(i, eq).trim().lowercase(Locale.ROOT)
            i = eq + 1
            while (i < value.length && value[i] == ' ') i++
            val text = StringBuilder()
            if (i < value.length && value[i] == '"') {
                i++
                while (i < value.length && value[i] != '"') {
                    if (value[i] == '\\' && i + 1 < value.length) i++
                    text.append(value[i]); i++
                }
                i = value.indexOf(';', i).takeIf { it >= 0 } ?: value.length
            } else {
                val end = value.indexOf(';', i).takeIf { it >= 0 } ?: value.length
                text.append(value.substring(i, end).trim()); i = end
            }
            if (key.isNotEmpty() && key !in out) out[key] = text.toString()
        }
        return out
    }

    private fun decodeExtended(value: String): String? = runCatching {
        val first = value.indexOf('\''); val second = value.indexOf('\'', first + 1)
        require(first > 0 && second > first)
        String(percentBytes(value.substring(second + 1)), Charset.forName(value.substring(0, first)))
    }.getOrNull()

    fun percentDecode(text: String): String = runCatching { String(percentBytes(text), Charsets.UTF_8) }.getOrDefault(text)

    /** `%XX` only; `+` stays a plus (not form encoding). Text that is not escaped keeps its UTF-8 bytes. */
    fun percentBytes(text: String): ByteArray {
        val out = ByteArrayOutputStream(text.length)
        val run = StringBuilder()
        fun flush() {
            if (run.isNotEmpty()) { out.write(run.toString().toByteArray(Charsets.UTF_8)); run.setLength(0) }
        }
        var i = 0
        while (i < text.length) {
            val hi = if (text[i] == '%' && i + 2 < text.length) text[i + 1].digitToIntOrNull(16) else null
            val lo = if (hi != null) text[i + 2].digitToIntOrNull(16) else null
            if (hi != null && lo != null) { flush(); out.write(hi * 16 + lo); i += 3 } else { run.append(text[i]); i++ }
        }
        flush()
        return out.toByteArray()
    }
}

/** `data:[<type>][;base64],<data>` */
internal object BotDataUrl {
    class Decoded(val type: String, val bytes: ByteArray)

    fun decode(url: String, limit: Long = BotDownloadLimits.DATA): Decoded {
        if (!url.regionMatches(0, "data:", 0, 5, ignoreCase = true)) throw BotDownloadException(R.string.bot_services_download_unsupported)
        val comma = url.indexOf(',')
        if (comma < 5) throw BotDownloadException(R.string.bot_services_download_unsupported)
        val meta = url.substring(5, comma)
        val data = url.substring(comma + 1)
        val base64 = meta.endsWith(";base64", ignoreCase = true)
        val type = meta.substringBefore(';').trim().lowercase(Locale.ROOT).ifEmpty { "text/plain" }
        val estimate = if (base64) data.length / 4L * 3 else data.length.toLong()
        if (estimate > limit + 3) throw BotDownloadException(R.string.bot_services_download_too_large, sizeLabel(limit))
        val bytes = runCatching {
            if (base64) Base64.getMimeDecoder().decode(BotDownloadNames.percentDecode(data)) else BotDownloadNames.percentBytes(data)
        }.getOrElse { throw BotDownloadException(R.string.bot_services_download_failed) }
        if (bytes.size > limit) throw BotDownloadException(R.string.bot_services_download_too_large, sizeLabel(limit))
        return Decoded(type, bytes)
    }
}

internal fun sizeLabel(bytes: Long): String = when {
    bytes >= 1024L * 1024 * 1024 -> "${bytes / (1024L * 1024 * 1024)} GB"
    else -> "${bytes / (1024L * 1024)} MB"
}

/** The phone's Downloads folder (MediaStore; no storage permission on Android 10 and later). */
internal class BotDownloadStore(private val context: Context) {
    private val resolver get() = context.contentResolver

    fun create(name: String, type: String): Uri = resolver.insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
        ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, type)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }) ?: throw BotDownloadException(R.string.bot_services_download_failed)

    fun output(uri: Uri): OutputStream = resolver.openOutputStream(uri, "w") ?: throw BotDownloadException(R.string.bot_services_download_failed)

    /** Makes the file visible and returns the name it was stored under (the system adds " (1)" when the name is taken). */
    fun finish(uri: Uri, fallback: String): String {
        resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        return runCatching {
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull() ?: fallback
    }

    fun discard(uri: Uri) { runCatching { resolver.delete(uri, null, null) } }

    fun openIntent(uri: Uri, type: String): Intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)

    companion object {
        fun systemType(extension: String): String? = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        fun systemExtension(type: String): String? = MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
    }
}

/**
 * Reads a Blob the page turned into an object URL (see assets/woowtechbot/workspace-downloads.js), chunk by chunk with
 * evaluateJavascript: no native interface is exposed to the page. [valid] says the same page is still shown.
 */
internal class BotBlobReader(private val view: WebView, private val hook: String, private val valid: () -> Boolean) {
    class Info(val size: Long, val type: String, val name: String)
    private val token = UUID.randomUUID().toString()

    suspend fun open(url: String, limit: Long = BotDownloadLimits.BLOB): Info {
        if (eval(hook) != "true") throw BotDownloadException(R.string.bot_services_download_blob_failed)
        if (text(eval("window.__woowDownloads.start(${q(token)},${q(url)})")) != "started") throw BotDownloadException(R.string.bot_services_download_blob_failed)
        val end = System.currentTimeMillis() + 30_000
        while (true) {
            when (val answer = text(eval("window.__woowDownloads.info(${q(token)},${q(url)})"))) {
                "pending" -> if (System.currentTimeMillis() > end) throw BotDownloadException(R.string.bot_services_download_blob_failed) else delay(50)
                null, "failed", "unknown" -> throw BotDownloadException(R.string.bot_services_download_blob_failed)
                else -> {
                    val json = runCatching { Json.parseToJsonElement(answer) as JsonObject }
                        .getOrElse { throw BotDownloadException(R.string.bot_services_download_blob_failed) }
                    fun field(key: String) = (json[key] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
                    val info = Info((json["size"] as? JsonPrimitive)?.longOrNull ?: -1, field("type"), field("name"))
                    if (info.size < 0) throw BotDownloadException(R.string.bot_services_download_blob_failed)
                    if (info.size > limit) throw BotDownloadException(R.string.bot_services_download_too_large, sizeLabel(limit))
                    return info
                }
            }
        }
    }

    suspend fun copy(info: Info, out: OutputStream, progress: (Long) -> Unit) {
        val chunks = ((info.size + CHUNK - 1) / CHUNK).toInt()
        var written = 0L
        for (index in 0 until chunks) {
            if (text(eval("window.__woowDownloads.read(${q(token)},$index,$CHUNK)")) != "reading") throw BotDownloadException(R.string.bot_services_download_blob_failed)
            val end = System.currentTimeMillis() + 30_000
            var data: String? = null
            while (data == null) {
                val raw = eval("window.__woowDownloads.take(${q(token)},$index)")
                if (raw == null || raw == "null") {
                    if (System.currentTimeMillis() > end) throw BotDownloadException(R.string.bot_services_download_blob_failed)
                    delay(8)
                } else data = text(raw)
            }
            if (data == "error" || data == "unknown") throw BotDownloadException(R.string.bot_services_download_blob_failed)
            val bytes = runCatching { Base64.getDecoder().decode(data) }.getOrElse { throw BotDownloadException(R.string.bot_services_download_blob_failed) }
            withContext(Dispatchers.IO) { out.write(bytes) }
            written += bytes.size
            progress(written)
        }
        if (written != info.size) throw BotDownloadException(R.string.bot_services_download_blob_failed)
    }

    suspend fun close() { runCatching { eval("window.__woowDownloads && window.__woowDownloads.end(${q(token)})") } }

    /** The `download` name of the anchor the user just clicked for [url] (direct and data: downloads), if any. */
    suspend fun anchorName(url: String): String? = runCatching {
        if (eval(hook) != "true") return null
        text(eval("window.__woowDownloads.named(${q(url.take(128))},${url.length})"))?.takeIf { it.isNotBlank() }
    }.getOrNull()

    private suspend fun eval(script: String): String? = withContext(Dispatchers.Main) {
        if (!valid()) throw BotDownloadException(R.string.bot_services_download_blob_failed)
        withTimeout(20_000) { suspendCancellableCoroutine { done -> view.evaluateJavascript(script) { if (done.isActive) done.resume(it) } } }
    }

    companion object {
        const val CHUNK = 512 * 1024
        private fun q(value: String) = JsonPrimitive(value).toString()
        /** evaluateJavascript answers in JSON: a string comes quoted, null as "null". */
        fun text(raw: String?): String? = when {
            raw == null || raw == "null" -> null
            raw.length >= 2 && raw.first() == '"' && raw.last() == '"' && '\\' !in raw -> raw.substring(1, raw.length - 1)
            raw.first() == '"' -> runCatching { (Json.parseToJsonElement(raw) as JsonPrimitive).content }.getOrNull()
            else -> raw
        }
    }
}

/** The Blob URL belongs to the service's own page: `blob:<service origin>/<id>`. */
internal fun blobOfService(url: String, service: BotService): Boolean =
    url.startsWith("blob:") && url.length <= BotOrigin.MAX_URL && service.policy.allows(url.removePrefix("blob:"))
