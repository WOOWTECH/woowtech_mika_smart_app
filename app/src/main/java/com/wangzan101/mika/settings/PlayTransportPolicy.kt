package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** The Play package must not send model prompts, API keys, or MCP data over the LAN in cleartext. */
internal object PlayTransportPolicy {
    val enabled: Boolean get() = BuildConfig.FLAVOR == "woowtech"

    fun permits(url: String): Boolean {
        if (!enabled) return true
        val parsed = url.toHttpUrlOrNull() ?: return false
        return parsed.isHttps || (parsed.scheme == "http" && parsed.host in setOf("localhost", "127.0.0.1"))
    }
}
