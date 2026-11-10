package com.wangzan101.mika.core.remote

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl

/** Client endpoints, never device credentials. Both endpoints belong to one validated channel. */
data class RelayConnectionInfo private constructor(
    val mcpUrl: String,
    val apiBaseUrl: String,
) {
    val personal: Boolean get() = mcpUrl.toHttpUrl().encodedPath.startsWith("/r/")
    val cliCommand: String get() = "mika connect --url $apiBaseUrl --token-file /path/to/token"

    companion object {
        fun checked(gateway: HttpUrl, mcpUrl: String, apiBaseUrl: String): RelayConnectionInfo {
            fun endpoint(raw: String): HttpUrl {
                val u = raw.toHttpUrl()
                require(u.scheme == gateway.scheme && u.host == gateway.host && u.port == gateway.port)
                require(u.username.isEmpty() && u.password.isEmpty() && u.query == null && u.fragment == null)
                // Canonical URLs only: reject encoded separators and dot-segment aliases.
                require(raw == u.toString())
                return u
            }
            val mcp = endpoint(mcpUrl)
            val api = endpoint(apiBaseUrl)
            require(Regex("/(?:r/[A-Za-z0-9_-]{22}/)?mcp").matches(mcp.encodedPath))
            require(api.encodedPath == mcp.encodedPath.removeSuffix("mcp") + "api/v1")
            return RelayConnectionInfo(mcp.toString(), api.toString())
        }

    }
}
