package com.wangzan101.mika.settings

import com.wangzan101.mika.core.model.ModelEndpoint
import com.wangzan101.mika.core.model.ModelProtocol
import com.wangzan101.mika.core.model.ModelRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.crypto.KeyGenerator

class PlayModelProviderPolicyTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun playOffersOnlyDirectOfficialProviders() {
        assumeTrue(PlayModelProviderPolicy.enabled)
        assertEquals(listOf("OpenAI", "Anthropic", "Gemini"), PlayModelProviderPolicy.presets.map { it.label })
        for (preset in PlayModelProviderPolicy.presets) {
            assertTrue(PlayModelProviderPolicy.permits(preset.kind, preset.baseUrl))
        }
        assertTrue(PlayModelProviderPolicy.permits(ProviderConfig.Kind.ChatGpt, "https://api.openai.com/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiCompat, "https://api.openai.com/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://openrouter.ai/api/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "http://127.0.0.1:8080/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://api.openai.com.evil.example/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://api.openai.com:444/v1"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://api.openai.com/v1?next=evil"))
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://user@api.openai.com/v1"))
    }

    @Test fun modelListCannotRedirectPromptsOrKeysToAnotherHost() {
        assumeTrue(PlayModelProviderPolicy.enabled)
        val redirect = ModelEndpoint(ModelProtocol.Responses, "https://other.example/v1")
        assertFalse(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://api.openai.com/v1", redirect))
        assertTrue(PlayModelProviderPolicy.permits(ProviderConfig.Kind.OpenAiResponses, "https://api.openai.com/v1", ModelEndpoint(ModelProtocol.Responses, "https://api.openai.com/v1")))
    }

    @Test fun persistedUnsupportedProviderIsRetainedButCannotRun() {
        assumeTrue(PlayModelProviderPolicy.enabled)
        File(tmp.root, "providers.json").writeText("""{
            "services":[{"id":"old","name":"Old","kind":"OpenAiCompat","baseUrl":"https://router.example/v1"}],
            "providers":[{"id":"cfg","providerId":"old","kind":"OpenAiCompat","baseUrl":"https://router.example/v1","model":"old-model","name":"Old","toolCalls":true,"vision":false,"contextTokens":64000,"reasoning":false}],
            "uses":{"Main":{"use":"model","config":"cfg"},"Vision":{"use":"none"},"Light":{"use":"main"}}
        }""")
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val store = ProviderStore(tmp.root, AesGcmKeyCipher { key }, modelFactory = { _, _, _, _ ->
            error("An unsupported model must never be constructed")
        })
        assertEquals("old", store.provider("old")?.id)
        assertEquals("cfg", store.configFor(ModelRole.Main)?.id)
        assertNull(store.modelFor(ModelRole.Main))
        assertFalse(store.use(ModelRole.Main, "old", "new-model", store.configFor(ModelRole.Main)!!.capabilities))
        assertTrue(File(tmp.root, "providers.json").readText().contains("router.example"))
    }
}
