package com.wangzan101.mika.woowbot

import org.junit.Assert.*
import org.junit.Test

class BotWorkspaceAppearanceTest {
    @Test fun hostControlsRequireCurrentOriginMainFrameAndUserGesture() {
        assertEquals("services", BotWorkspaceAppearance.action("woowtech-ui://services", true, true, true))
        assertEquals("notifications", BotWorkspaceAppearance.action("woowtech-ui://notifications", true, true, true))
        for (flags in listOf(Triple(false, true, true), Triple(true, false, true), Triple(true, true, false))) {
            assertNull(BotWorkspaceAppearance.action("woowtech-ui://services", flags.first, flags.second, flags.third))
        }
    }
    @Test fun hostControlsCannotCarryCommandsDestinationsOrIdentity() {
        for (url in listOf("woowtech-ui://logout", "woowtech-ui://services?url=https://evil.example", "woowtech-ui://services#token", "woowtech-ui://services/", "woowtech-ui://user@services", "javascript:alert(1)")) {
            assertNull(BotWorkspaceAppearance.action(url, true, true, true))
        }
    }
}
