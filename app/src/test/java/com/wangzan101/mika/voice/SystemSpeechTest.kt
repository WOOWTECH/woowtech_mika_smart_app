package com.wangzan101.mika.voice

import android.speech.SpeechRecognizer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SystemSpeechTest {
    @Test
    fun errorCodesMapToFailures() {
        assertNull(SystemSpeech.failureOf(SpeechRecognizer.ERROR_NO_MATCH))
        assertNull(SystemSpeech.failureOf(SpeechRecognizer.ERROR_SPEECH_TIMEOUT))
        assertEquals(SpeechFailure.Busy, SystemSpeech.failureOf(SpeechRecognizer.ERROR_RECOGNIZER_BUSY))
        assertEquals(SpeechFailure.Network, SystemSpeech.failureOf(SpeechRecognizer.ERROR_NETWORK))
        assertEquals(SpeechFailure.Network, SystemSpeech.failureOf(SpeechRecognizer.ERROR_NETWORK_TIMEOUT))
        assertEquals(SpeechFailure.NoPermission, SystemSpeech.failureOf(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS))
        assertEquals(SpeechFailure.AudioError, SystemSpeech.failureOf(SpeechRecognizer.ERROR_AUDIO))
        assertEquals(SpeechFailure.MicUnavailable, SystemSpeech.failureOf(SpeechRecognizer.ERROR_CLIENT))
    }

    @Test
    fun missingOfflineLanguageRetriesOnceWithoutOfflinePreference() {
        val fallback = SpeechLanguageFallback(true)
        assertEquals(true, fallback.preferOffline)
        assertEquals(true, fallback.retryOnline(12, usingOnDevice = true, heardText = false))
        assertEquals(false, fallback.preferOffline)
        assertEquals(false, fallback.retryOnline(12, usingOnDevice = false, heardText = false))
        assertEquals(false, fallback.retryOnline(13, usingOnDevice = true, heardText = false))
        assertEquals(false, SpeechLanguageFallback(true).retryOnline(12, usingOnDevice = true, heardText = true))
        assertEquals(false, SpeechLanguageFallback(true).retryOnline(3, usingOnDevice = true, heardText = false))
    }

    @Test
    fun unsupportedAndMissingLanguageAreNotMissingRecognizer() {
        for (code in listOf(12, 13)) {
            val failure = SpeechFailure.Unavailable(SpeechEngineSpec.Why.SystemLanguageUnavailable)
            assertEquals(failure, SystemSpeech.failureOf(code))
            assertEquals(SystemSpeech.Outcome.Fail(failure), SystemSpeech.afterError(code, holding = true, heard = false))
            assertEquals(SystemSpeech.Outcome.Finish, SystemSpeech.afterError(code, holding = false, heard = true))
        }
    }

    @Test
    fun languageErrorWithoutAnActiveNetworkSuggestsCheckingConnectivity() {
        for (code in listOf(12, 13)) {
            for (holding in listOf(true, false)) {
                assertEquals(
                    SystemSpeech.Outcome.Fail(SpeechFailure.Network),
                    SystemSpeech.afterError(code, holding, heard = false) { false },
                )
                // Already recognized words still survive a subsequent failure, even while offline.
                assertEquals(SystemSpeech.Outcome.Finish, SystemSpeech.afterError(code, holding, heard = true) { false })
            }
        }
    }

    @Test
    fun presentOrUnknownNetworkKeepsLanguageGuidance() {
        val language = SpeechFailure.Unavailable(SpeechEngineSpec.Why.SystemLanguageUnavailable)
        for (code in listOf(12, 13)) {
            // An active network need not be validated; its presence alone must retain language guidance.
            assertEquals(language, SystemSpeech.failureOf(code) { true })
            assertEquals(language, SystemSpeech.failureOf(code) { null })
            assertEquals(language, SystemSpeech.failureOf(code) { throw SecurityException("network state unavailable") })
            assertEquals(language, SystemSpeech.failureOf(code) { throw IllegalStateException("service unavailable") })
        }
    }

    @Test
    fun connectivityIsReadAgainAfterReconnection() {
        var connected = false
        val currentNetwork = { connected }
        assertEquals(SpeechFailure.Network, SystemSpeech.failureOf(12, currentNetwork))
        connected = true
        assertEquals(
            SpeechFailure.Unavailable(SpeechEngineSpec.Why.SystemLanguageUnavailable),
            SystemSpeech.failureOf(12, currentNetwork),
        )
    }

    @Test
    fun connectivityDoesNotOverrideOtherRecognizerErrors() {
        for (code in listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 99)) {
            assertEquals(SystemSpeech.failureOf(code), SystemSpeech.failureOf(code) { false })
            // No permission, audio, busy, no-match or server error needs a connectivity query at all.
            var queries = 0
            assertEquals(SystemSpeech.failureOf(code), SystemSpeech.failureOf(code) { queries++; false })
            assertEquals("error $code must not query network", 0, queries)
        }
        assertEquals(
            SystemSpeech.Outcome.Fail(SpeechFailure.NoPermission),
            SystemSpeech.afterError(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, holding = true, heard = false) { false },
        )
        assertEquals(SystemSpeech.Outcome.Retry, SystemSpeech.afterError(SpeechRecognizer.ERROR_NO_MATCH, holding = true, heard = false) { false })
    }

    @Test
    fun silenceFromAServiceThatNeverAnsweredIsNoResponse() {
        assertEquals(
            SystemSpeech.Outcome.Fail(SpeechFailure.Unavailable(SpeechEngineSpec.Why.SystemNoResponse)),
            SystemSpeech.afterSilence(answered = false),
        )
        // 回过话的服务只是这一段卡住:按已听到的收尾,不记成不响应
        assertEquals(SystemSpeech.Outcome.Finish, SystemSpeech.afterSilence(answered = true))
    }

    @Test
    fun releaseWaitStillEndsWhenTheRecognizerNeverAnswered() {
        assertEquals(
            SystemSpeech.Outcome.Fail(SpeechFailure.Unavailable(SpeechEngineSpec.Why.SystemNoResponse)),
            SystemSpeech.afterReleaseWait(answered = false),
        )
        assertEquals(SystemSpeech.Outcome.Finish, SystemSpeech.afterReleaseWait(answered = true))
    }

    @Test
    fun languageTagsFollowAppLanguage() {
        assertEquals("zh-CN", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.SimplifiedChinese, java.util.Locale.US))
        assertEquals("zh-TW", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.TraditionalChinese, java.util.Locale.US))
        assertEquals("en-US", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.English, java.util.Locale.CHINA))
        assertEquals("ar-MA", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Arabic, java.util.Locale.US))
        assertEquals("fr-FR", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.System, java.util.Locale.FRANCE))
        // 选的语言和系统不同时用这种语言最常见的地区;相同时沿用系统的地区
        assertEquals("ja-JP", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Japanese, java.util.Locale.US))
        assertEquals("pt-BR", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Portuguese, java.util.Locale.US))
        assertEquals("pt-PT", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Portuguese, java.util.Locale.forLanguageTag("pt-PT")))
        assertEquals("es-MX", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Spanish, java.util.Locale.forLanguageTag("es-MX")))
        assertEquals("id-ID", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.Indonesian, java.util.Locale.forLanguageTag("in-ID")))
        // 中文按选的简繁定地区,不跟系统
        assertEquals("zh-CN", SystemSpeech.speechTag(com.wangzan101.mika.i18n.AppLanguage.SimplifiedChinese, java.util.Locale.TAIWAN))
        assertEquals("zh", SystemSpeech.isoCode("zh-TW"))
        assertEquals("en", SystemSpeech.isoCode("en-US"))
    }

    @Test
    fun systemLanguageDropsScriptAndExtensions() {
        val system = com.wangzan101.mika.i18n.AppLanguage.System
        assertEquals("zh-CN", SystemSpeech.speechTag(system, java.util.Locale.forLanguageTag("zh-Hans-CN")))
        assertEquals("zh-TW", SystemSpeech.speechTag(system, java.util.Locale.forLanguageTag("zh-Hant-TW")))
        assertEquals("sr-RS", SystemSpeech.speechTag(system, java.util.Locale.forLanguageTag("sr-Latn-RS")))
        assertEquals("de-DE", SystemSpeech.speechTag(system, java.util.Locale.forLanguageTag("de-DE-u-co-phonebk")))
        assertEquals("ja", SystemSpeech.speechTag(system, java.util.Locale.forLanguageTag("ja")))
        val english = com.wangzan101.mika.i18n.AppLanguage.English
        assertEquals("en-GB", SystemSpeech.speechTag(english, java.util.Locale.forLanguageTag("en-Latn-GB")))
    }

    private fun svc(name: String, open: Boolean = true) = RecognizerService("a.b/.$name", open, null)

    /** 只有一个识别服务时它就是默认的:只试默认的,不点名再试一遍白等。 */
    @Test
    fun aSingleServiceIsOnlyTriedAsTheDefault() {
        assertEquals(listOf<String?>(null), SystemSpeech.attempts(listOf(svc("One")), remembered = null))
        assertEquals(listOf<String?>(null), SystemSpeech.attempts(emptyList(), remembered = null))
    }

    /** 默认的不回话时,再点名试其余的,对别的 App 开放的在前;总数有上限。 */
    @Test
    fun otherServicesFollowTheDefaultOpenOnesFirst() {
        val services = listOf(svc("Closed", open = false), svc("Open"), svc("Third"))
        assertEquals(listOf(null, "a.b/.Open", "a.b/.Third"), SystemSpeech.attempts(services, remembered = null))
        assertEquals(SystemSpeech.MAX_ATTEMPTS, SystemSpeech.attempts(services + svc("Fourth"), null).size)
    }

    /** 之前点名试通的排最前、不重复;它已经不在手机上了就不管它。 */
    @Test
    fun theServiceThatAnsweredBeforeGoesFirst() {
        val services = listOf(svc("One"), svc("Two"))
        assertEquals(listOf("a.b/.Two", null, "a.b/.One"), SystemSpeech.attempts(services, remembered = "a.b/.Two"))
        assertEquals(listOf(null, "a.b/.One", "a.b/.Two"), SystemSpeech.attempts(services, remembered = "a.b/.Gone"))
    }
}
