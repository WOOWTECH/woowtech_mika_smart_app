package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.core.model.ModelEndpoint

/**
 * Model services in the Play edition. Owner decision 2026-11-13: like the direct-download edition, the Play edition
 * offers every API-key provider and custom endpoints. [PlayTransportPolicy] still requires HTTPS for services off the
 * phone. Owner decision 2026-11-18: account sign-in offers ChatGPT and xAI / Grok (see AccountSignIn).
 */
internal object PlayModelProviderPolicy {
    val enabled: Boolean get() = BuildConfig.FLAVOR == "woowtech"

    val presets: List<ProviderPreset> get() = ProviderPresets.all

    @Suppress("UNUSED_PARAMETER")
    fun permits(kind: ProviderConfig.Kind, baseUrl: String, endpoint: ModelEndpoint? = null): Boolean = true
}
