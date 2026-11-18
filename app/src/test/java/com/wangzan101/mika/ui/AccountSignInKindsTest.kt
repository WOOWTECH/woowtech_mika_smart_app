package com.wangzan101.mika.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** Owner decision 2026-11-18: the Play edition offers the same account sign-ins as the direct-download edition. */
class AccountSignInKindsTest {
    @Test fun chatGptXaiAndOpenRouterAreAllOffered() {
        assertEquals(listOf(SignInKind.ChatGpt, SignInKind.Xai, SignInKind.OpenRouter), SignInKind.offered)
    }
}
