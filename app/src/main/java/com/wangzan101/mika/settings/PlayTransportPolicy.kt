package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** The Play package must not send model prompts, API keys, or MCP data over the LAN in cleartext. */
internal object PlayTransportPolicy {
    val enabled: Boolean get() = BuildConfig.PLAY_EDITION

    /** The Play package ships no Linux sandbox, so it has no local (stdio) MCP servers. */
    val allowsStdioMcp: Boolean get() = !enabled

    /**
     * Owner decision 2026-11-18: the Play package connects a computer only through the outbound relay, with no device
     * permissions. It never listens on the LAN (cleartext HTTP) or for adb over USB, even if those switches are on.
     */
    val allowsLocalComputerAccess: Boolean get() = !enabled

    fun allows(url: String): Boolean {
        if (!enabled) return true
        val parsed = url.toHttpUrlOrNull() ?: return false
        return parsed.isHttps || (parsed.scheme == "http" && parsed.host in setOf("localhost", "127.0.0.1"))
    }
}
