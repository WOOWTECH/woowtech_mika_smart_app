package com.wangzan101.mika.ui

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.wangzan101.mika.core.shell.BuiltinShellStatus
import com.wangzan101.mika.settings.AccessibilityState
import com.wangzan101.mika.settings.SystemStatus
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccessibilityInstallHelpTest {
    @get:Rule val compose = createComposeRule()

    @Test fun helpRemainsAvailableWhenRestrictionProbeSaysNoAndWaitsForRunningService() {
        val status = mutableStateOf(SystemStatus(35, BuiltinShellStatus.NotPaired, AccessibilityState.Off, notificationsAllowed = true, restrictedSettings = false))
        val fixes = mutableListOf<Fix>()
        compose.setContent {
            PhoneOpsScreen(status.value, "15", {}, {}, {}, {}, onFix = { fixes += it })
        }
        compose.onNodeWithTag("setup-app-info").performScrollTo().performClick()
        compose.onNodeWithTag("a11y-install-open").performScrollTo().performClick()
        assertEquals(listOf(Fix.OpenAppInfo, Fix.OpenAccessibility), fixes)
        compose.onNodeWithTag("accessibility-install-help").assertExists()
        compose.runOnIdle { status.value = status.value.copy(accessibility = AccessibilityState.EnabledNotRunning) }
        compose.onNodeWithTag("accessibility-install-help").assertExists()
        compose.runOnIdle { status.value = status.value.copy(accessibility = AccessibilityState.On) }
        compose.onNodeWithTag("accessibility-install-help").assertDoesNotExist()
    }

    @Test fun olderAndroidDoesNotShowRestrictedSettingsInstructions() {
        compose.setContent {
            PhoneOpsScreen(SystemStatus(32, BuiltinShellStatus.NotPaired, AccessibilityState.Off, notificationsAllowed = true), "12", {}, {}, {}, {})
        }
        compose.onNodeWithTag("accessibility-install-help").assertDoesNotExist()
    }
}
