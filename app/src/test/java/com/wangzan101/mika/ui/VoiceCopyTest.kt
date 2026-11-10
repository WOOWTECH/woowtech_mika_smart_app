package com.wangzan101.mika.ui

import com.wangzan101.mika.i18n.EnglishTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import com.wangzan101.mika.voice.SpeechFailure
import com.wangzan101.mika.voice.SystemSpeech
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** The composer and capsule share this failure copy. */
class VoiceCopyTest {
    @get:Rule val texts = EnglishTexts()

    @Test fun offlineLanguageErrorGivesActionableEnglishGuidance() {
        val failure = SystemSpeech.failureOf(12) { false }!!
        assertEquals("Check Wi-Fi or mobile data, then try speaking again.", VoiceCopy.failure(failure))
    }

    @Test fun offlineLanguageErrorGivesActionableTraditionalChineseGuidance() {
        UiText.source = ResFileTexts.traditional
        val failure = SystemSpeech.failureOf(13) { false }!!
        assertEquals("請開啟或檢查 Wi-Fi／行動數據後再試一次語音輸入。", VoiceCopy.failure(failure))
    }

    @Test fun serverErrorDoesNotAssertThatTheInternetIsDown() {
        // ERROR_SERVER can fail even on a working network; use the same non-diagnostic advice.
        val failure = SystemSpeech.failureOf(4) { true }!!
        assertEquals(SpeechFailure.Network, failure)
        assertEquals("Check Wi-Fi or mobile data, then try speaking again.", VoiceCopy.failure(failure))
    }
}
