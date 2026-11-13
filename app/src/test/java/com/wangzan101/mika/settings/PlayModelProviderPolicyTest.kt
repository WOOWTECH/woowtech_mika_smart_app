package com.wangzan101.mika.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class PlayModelProviderPolicyTest {
    @Test fun playOffersEveryApiKeyProviderAndCustomEndpoints() {
        assumeTrue(PlayModelProviderPolicy.enabled)
        assertEquals(ProviderPresets.all.map { it.label }, PlayModelProviderPolicy.presets.map { it.label })
        for (preset in PlayModelProviderPolicy.presets) {
            assertTrue(PlayModelProviderPolicy.permits(preset.kind, preset.baseUrl))
        }
        assertTrue(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiCompat, "https://gateway.example/v1"))
        assertTrue(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://openrouter.ai/api/v1"))
    }

    @Test fun cleartextOffThePhoneStaysBlocked() {
        assumeTrue(PlayTransportPolicy.enabled)
        assertTrue(PlayTransportPolicy.permits("https://gateway.example/v1"))
        assertTrue(PlayTransportPolicy.permits("http://127.0.0.1:11434/v1"))
        assertFalse(PlayTransportPolicy.permits("http://192.168.1.10:11434/v1"))
    }
}
