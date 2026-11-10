package com.wangzan101.mika.ui

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import com.wangzan101.mika.ChineseUi
import com.wangzan101.mika.core.remote.RelayConnectionInfo
import com.wangzan101.mika.core.remote.RelayGateway
import com.wangzan101.mika.settings.RelayInfoState
import com.wangzan101.mika.core.remote.RelayState
import com.wangzan101.mika.settings.RelayConfig
import com.wangzan101.mika.ui.components.PageScaffold
import com.wangzan101.mika.ui.theme.MikaTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class RelaySectionTest {
    @get:Rule(order = Int.MIN_VALUE) val chinese = ChineseUi()
    @get:Rule val compose = createComposeRule()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = com.wangzan101.mika.CloseComposeActivity(compose)
    private val config = mutableStateOf(RelayConfig())
    private val state = mutableStateOf(RelayState.Off)
    private val infoState = mutableStateOf(RelayInfoState.Idle)
    private val changes = mutableListOf<Boolean>()
    private val deviceChanges = mutableListOf<Boolean>()
    private var paired: Pair<String, String>? = null
    private var unpaired = 0
    private var copied = 0

    private fun page() {
        compose.setContent { MikaTheme {
            PageScaffold("远程", {}) {
                RelayControls(config.value, state.value, false, false,
                    { url, code -> paired = url to code }, changes::add, { unpaired++ }, { copied++ }, { copied++ },
                    onDeviceAccess = deviceChanges::add, infoState = infoState.value)
            }
        } }
    }

    @Test fun pairingRequiresHttpsAndClearsCodeWithoutEnablingAccess() {
        page()
        compose.onNodeWithTag("relay-pair").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("relay-code").performTextInput("example-pairing-code")
        compose.onNodeWithTag("relay-pair").assertIsNotEnabled()
        compose.onNodeWithTag("relay-gateway").performTextInput("https://relay.example")
        compose.onNodeWithTag("relay-pair").performScrollTo().performClick()
        assertEquals("https://relay.example" to "example-pairing-code", paired)
        assertTrue(changes.isEmpty())
        compose.onNodeWithTag("relay-code").assertTextEquals("")
    }

    @Test fun pairedSettingsKeepTokensHiddenAndRequireExplicitEnableAndUnpair() {
        config.value = RelayConfig(gateway = "https://relay.example/", connectionInfo = personalInfo())
        page()
        compose.onNodeWithText("已配对，远程访问未开启").assertIsDisplayed()
        compose.onNodeWithTag("relay-code").assertDoesNotExist()
        compose.onNodeWithTag("relay-enabled").performClick()
        assertEquals(listOf(true), changes)
        compose.onNodeWithTag("relay-device-access").performScrollTo().assertIsOff().performClick()
        assertEquals(listOf(true), deviceChanges)
        compose.onNodeWithText("复制 MCP 地址").performScrollTo().performClick()
        assertEquals(1, copied)
        compose.onNodeWithText("解除网关配对").performScrollTo().performClick()
        assertEquals(0, unpaired)
        compose.onNodeWithText("取消").performClick()
        assertEquals(0, unpaired)
    }

    @Test fun onlineAndRevokedStateAreShownAsObserved() {
        config.value = RelayConfig(true, "https://relay.example/")
        state.value = RelayState.Online
        page()
        compose.onNodeWithText("网关已连接，等待 CLI / MCP 请求").assertIsDisplayed()
        compose.runOnIdle { state.value = RelayState.Unauthorized }
        compose.onNodeWithText("配对已失效或被撤销，请重新配对网关").assertIsDisplayed()
        compose.runOnIdle { state.value = RelayState.Incompatible }
        compose.onNodeWithText("请将 Mika 与网关更新到匹配的版本").assertIsDisplayed()
    }
    private fun personalInfo() = RelayConnectionInfo.checked(RelayGateway.parse("https://relay.example/"),
        "https://relay.example/r/AAAAAAAAAAAAAAAAAAAAAA/mcp", "https://relay.example/r/AAAAAAAAAAAAAAAAAAAAAA/api/v1")

    @Test fun unresolvedAndRevokedDiscoveryCannotCopyUnverifiedAddresses() {
        config.value = RelayConfig(gateway = "https://relay.example/")
        page()
        compose.onNodeWithTag("relay-copy-address").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("relay-copy-config").assertIsNotEnabled()
        compose.runOnIdle { config.value = config.value.copy(connectionInfo = personalInfo()); infoState.value = RelayInfoState.Ready }
        compose.onNodeWithTag("relay-copy-address").performClick()
        assertEquals(1, copied)
        compose.runOnIdle { infoState.value = RelayInfoState.Unauthorized }
        compose.onNodeWithTag("relay-copy-address").assertIsNotEnabled()
        compose.onNodeWithTag("relay-copy-config").assertIsNotEnabled()
    }

    @Test fun personalEndpointIsVisibleWhileOfflineAndTemporaryFailureKeepsCopyAvailable() {
        config.value = RelayConfig(gateway = "https://relay.example/", connectionInfo = personalInfo())
        infoState.value = RelayInfoState.Unavailable
        page()
        compose.onNodeWithText(personalInfo().mcpUrl).performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("relay-copy-address").performScrollTo().performClick()
        assertEquals(1, copied)
    }

}
