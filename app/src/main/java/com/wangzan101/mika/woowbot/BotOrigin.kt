package com.wangzan101.mika.woowbot

import java.net.URI
import java.util.Locale

/** An explicit user-selected web origin, never a native proxy or phone command endpoint. */
class BotOrigin private constructor(val value: String, val insecureLan: Boolean) {
    fun allows(url: String): Boolean = runCatching {
        val uri = URI(url)
        parse("${uri.scheme}://${uri.rawAuthority}", insecureLan).value == value &&
            uri.rawUserInfo == null && !url.contains('\\') && url.none { it.isISOControl() }
    }.getOrDefault(false)

    companion object {
        const val MAX_URL = 2048

        /** No credentials, queries or pairing fragments are stored. HTTP requires a private literal/.local. */
        fun parse(input: String, allowHttpLan: Boolean = false): BotOrigin {
            require(input.length in 1..MAX_URL)
            val text = input.trim()
            require(text.none { it.isWhitespace() || it.isISOControl() || it == '\\' })
            val uri = URI(text)
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            require(scheme == "https" || scheme == "http")
            require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
            require(uri.rawPath.isNullOrEmpty() || uri.rawPath == "/")
            val host = requireNotNull(uri.host).lowercase(Locale.ROOT)
            require(host.isNotBlank() && !host.endsWith('.'))
            val plainHost = host.removePrefix("[").removeSuffix("]")
            require(plainHost != "localhost" && plainHost != "::1" && plainHost != "0.0.0.0")
            require(!plainHost.startsWith("127.") && !plainHost.startsWith("169.254."))
            require(!plainHost.startsWith("fe80:") && !plainHost.startsWith("::ffff:"))
            require(uri.port == -1 || uri.port in 1..65535)
            val insecure = scheme == "http"
            require(!insecure || (allowHttpLan && isLanHost(plainHost)))
            val port = uri.port.takeUnless { it == -1 || (scheme == "https" && it == 443) || (scheme == "http" && it == 80) }
            return BotOrigin("$scheme://$host${port?.let { ":$it" }.orEmpty()}", insecure)
        }

        private fun isLanHost(host: String): Boolean {
            if (host.endsWith(".local") && host.length > 6) return true
            if (host.contains(':')) return host.startsWith("fc") || host.startsWith("fd")
            val parts = host.split('.')
            if (parts.size != 4 || parts.any { it.length > 1 && it.startsWith('0') }) return false
            val ip = parts.map { it.toIntOrNull() ?: return false }
            if (ip.any { it !in 0..255 }) return false
            return ip[0] == 10 || (ip[0] == 172 && ip[1] in 16..31) || (ip[0] == 192 && ip[1] == 168)
        }
    }
}
