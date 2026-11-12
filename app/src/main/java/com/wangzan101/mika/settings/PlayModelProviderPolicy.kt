package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.core.model.ModelEndpoint
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** The Play edition connects models only to the official provider API endpoints we support. */
internal object PlayModelProviderPolicy {
    val enabled: Boolean get() = BuildConfig.FLAVOR == "woowtech"

    private val official = mapOf(
        ProviderConfig.Kind.ChatGpt to setOf("https://api.openai.com/v1"),
        ProviderConfig.Kind.OpenAiResponses to setOf("https://api.openai.com/v1"),
        ProviderConfig.Kind.Anthropic to setOf("https://api.anthropic.com"),
        ProviderConfig.Kind.Gemini to setOf("https://generativelanguage.googleapis.com"),
    )

    val presets: List<ProviderPreset>
        get() = if (enabled) listOf("OpenAI", "Anthropic", "Gemini").map { label ->
            ProviderPresets.all.first { it.label == label }
        } else ProviderPresets.all

    fun permits(kind: ProviderConfig.Kind, baseUrl: String, endpoint: ModelEndpoint? = null): Boolean {
        if (!enabled) return true
        val allowed = official[kind] ?: return false
        return allowed.any { sameOfficialUrl(baseUrl, it) } &&
            (endpoint == null || allowed.any { sameOfficialUrl(endpoint.adapterBaseUrl, it) })
    }

    private fun sameOfficialUrl(input: String, expected: String): Boolean {
        val url = input.trim().toHttpUrlOrNull() ?: return false
        val canonical = expected.toHttpUrlOrNull() ?: return false
        return url.isHttps && url.host == canonical.host && url.port == 443 &&
            url.username.isEmpty() && url.password.isEmpty() && url.query == null && url.fragment == null &&
            url.encodedPath.trimEnd('/') == canonical.encodedPath.trimEnd('/')
    }
}
