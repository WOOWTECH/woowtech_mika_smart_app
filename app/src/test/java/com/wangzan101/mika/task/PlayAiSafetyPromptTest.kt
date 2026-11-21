package com.wangzan101.mika.task

import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.core.agent.SystemPrompt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayAiSafetyPromptTest {
    @Test fun playRunsIncludeSafetyRulesWithoutChangingOtherEditions() {
        val base = SystemPrompt.identity("io.woowtech.assistant")
        val actual = PlayAiSafetyPrompt.identity("io.woowtech.assistant")
        if (BuildConfig.PLAY_EDITION) {
            assertTrue(actual.startsWith(base))
            assertTrue(actual.contains("non-consensual intimate content"))
            assertTrue(actual.contains("child tasks"))
        } else {
            assertEquals(base, actual)
        }
    }
}
