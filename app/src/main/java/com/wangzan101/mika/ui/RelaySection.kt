package com.wangzan101.mika.ui

import com.wangzan101.mika.ui.components.MikaDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.wangzan101.mika.R
import com.wangzan101.mika.core.remote.RelayGateway
import com.wangzan101.mika.core.remote.RelayState
import com.wangzan101.mika.mcp.McpRuntime
import com.wangzan101.mika.settings.RelayConfig
import com.wangzan101.mika.settings.RelayInfoState
import com.wangzan101.mika.ui.components.ButtonKind
import com.wangzan101.mika.ui.components.ButtonSize
import com.wangzan101.mika.ui.components.FooterNote
import com.wangzan101.mika.ui.components.GroupCard
import com.wangzan101.mika.ui.components.InputRow
import com.wangzan101.mika.ui.components.ListRow
import com.wangzan101.mika.ui.components.MikaButton
import com.wangzan101.mika.ui.components.MikaSwitch
import com.wangzan101.mika.ui.components.RowActions
import com.wangzan101.mika.ui.theme.MikaIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
internal fun RelaySection(runtime: McpRuntime, mcp: Boolean, onCopy: (String) -> Unit) {
    val config by runtime.relaySettings.config.collectAsState()
    val state by runtime.relayState.collectAsState()
    val infoState by runtime.relayDiscovery.state.collectAsState()
    // Also migrates existing encrypted pairings when this page is first opened after an upgrade.
    LaunchedEffect(runtime) {
        withContext(Dispatchers.IO) { runtime.relayDiscovery.refresh() }
    }
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    fun change(action: suspend () -> Unit) {
        if (busy) return
        busy = true; failed = false
        scope.launch {
            try { withContext(Dispatchers.IO) { action() } }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: Exception) { failed = true }
            finally { busy = false }
        }
    }
    RelayControls(config, state, busy, failed,
        onPair = { url, code -> change { runtime.pairRelay(url, code) } },
        onEnabled = { on -> change { runtime.setRelayEnabled(on) } },
        onDeviceAccess = { on -> change { runtime.setRelayDeviceAccess(on) } },
        onUnpair = { change { runtime.unpairRelay() } },
        onCopyAddress = { runtime.relaySettings.config.value.connectionInfo?.let {
            onCopy(if (mcp) it.mcpUrl else it.apiBaseUrl)
        } },
        onCopyConfig = { change {
            runtime.relaySettings.pairing()?.connectionInfo?.let { info ->
                val text = if (mcp) McpRuntime.clientConfig(info.mcpUrl, runtime.settings.token())
                else info.cliCommand
                withContext(Dispatchers.Main) { onCopy(text) }
            }
        } }, mcp = mcp, infoState = infoState,
        onRefresh = { change { runtime.relayDiscovery.refresh() } },
        onCopyToken = { change { val token = runtime.settings.token(); withContext(Dispatchers.Main) { onCopy(token) } } })
}

/** 纯展示与用户动作回调,测试不依赖真实网关。配对码不进可恢复状态;旧令牌不显示。 */
@Composable
internal fun RelayControls(config: RelayConfig, state: RelayState, busy: Boolean, failed: Boolean,
    onPair: (String, String) -> Unit, onEnabled: (Boolean) -> Unit, onUnpair: () -> Unit,
    onCopyAddress: () -> Unit, onCopyConfig: () -> Unit, mcp: Boolean = true, onCopyToken: () -> Unit = {},
    onDeviceAccess: (Boolean) -> Unit = {}, infoState: RelayInfoState = RelayInfoState.Idle,
    onRefresh: () -> Unit = {}) {
    var gateway by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf(false) }
    val info = config.connectionInfo
    val reading = busy || infoState == RelayInfoState.Loading
    val canCopy = info != null && !reading && state != RelayState.Unauthorized && infoState !in setOf(RelayInfoState.Unauthorized, RelayInfoState.Invalid)

    if (!config.paired) {
        GroupCard {
            ListRow(MikaIcons.Link, stringResource(R.string.relay_pair_title), stringResource(R.string.relay_pair_sub), first = true)
            InputRow(stringResource(R.string.relay_gateway), gateway, { if (!busy) gateway = it.take(2048) },
                // WOOWTECH fork: 示例地址放进字符串资源,品牌版换成不带产品名的
                stringResource(R.string.relay_gateway_hint), keyboard = KeyboardType.Uri, modifier = Modifier.testTag("relay-gateway"))
            InputRow(stringResource(R.string.relay_code), code, { if (!busy) code = it.take(64) },
                stringResource(R.string.relay_code_hint), secret = true, keyboard = KeyboardType.Password, modifier = Modifier.testTag("relay-code"))
            RowActions {
                MikaButton(stringResource(if (busy) R.string.relay_busy else R.string.relay_pair), {
                    onPair(gateway.trim(), code.trim()); code = ""
                }, size = ButtonSize.Small, enabled = !busy && code.trim().length in 8..64 && runCatching { RelayGateway.parse(gateway) }.isSuccess,
                    modifier = Modifier.testTag("relay-pair"))
            }
        }
    } else {
        val status = when {
            !config.enabled -> R.string.relay_disabled
            state == RelayState.Online -> R.string.relay_online
            state == RelayState.Unauthorized -> R.string.relay_unauthorized
            state == RelayState.Incompatible -> R.string.relay_incompatible
            state == RelayState.Offline -> R.string.relay_offline
            else -> R.string.relay_connecting
        }
        GroupCard {
            ListRow(MikaIcons.Link, stringResource(R.string.relay_enable), stringResource(status), first = true) {
                MikaSwitch(config.enabled, onEnabled, Modifier.testTag("relay-enabled"), enabled = !busy)
            }
            ListRow(null, stringResource(R.string.relay_device_access), stringResource(R.string.relay_device_access_sub)) {
                MikaSwitch(config.deviceAccess, onDeviceAccess, Modifier.testTag("relay-device-access"), enabled = !busy)
            }
            ListRow(null, stringResource(R.string.relay_gateway), config.gateway)
            ListRow(null, stringResource(R.string.relay_channel), stringResource(when {
                info == null -> R.string.relay_info_missing
                info.personal -> R.string.relay_channel_personal
                else -> R.string.relay_channel_shared
            }))
            if (info != null) ListRow(null, stringResource(if (mcp) R.string.relay_client_mcp else R.string.relay_client_api),
                if (mcp) info.mcpUrl else info.apiBaseUrl)
            RowActions {
                MikaButton(stringResource(if (infoState == RelayInfoState.Loading) R.string.relay_busy else R.string.relay_info_refresh),
                    onRefresh, kind = ButtonKind.Tonal, size = ButtonSize.Small, enabled = !reading,
                    modifier = Modifier.testTag("relay-info-refresh"))
            }
            RowActions {
                MikaButton(stringResource(if (mcp) R.string.relay_copy_address else R.string.relay_copy_api), onCopyAddress, size = ButtonSize.Small, enabled = canCopy, modifier = Modifier.testTag("relay-copy-address"))
                MikaButton(stringResource(if (mcp) R.string.mcp_copy_config else R.string.mcp_copy_command), onCopyConfig, kind = ButtonKind.Tonal, size = ButtonSize.Small, enabled = canCopy, modifier = Modifier.testTag("relay-copy-config"))
            }
            if (!mcp) RowActions {
                MikaButton(stringResource(R.string.mcp_copy_token), onCopyToken, kind = ButtonKind.Tonal, size = ButtonSize.Small, enabled = !busy)
            }
            RowActions {
                MikaButton(stringResource(R.string.relay_unpair), { confirm = true }, kind = ButtonKind.Text, size = ButtonSize.Small, enabled = !busy)
            }
        }
        val infoMessage = when (infoState) {
            RelayInfoState.Unsupported -> R.string.relay_info_unsupported
            RelayInfoState.Unauthorized -> R.string.relay_unauthorized
            RelayInfoState.Invalid -> R.string.relay_info_invalid
            RelayInfoState.RateLimited -> R.string.relay_info_rate_limited
            RelayInfoState.Unavailable -> if (info != null) R.string.relay_info_cached else R.string.relay_info_failed
            else -> null
        }
        infoMessage?.let { FooterNote(stringResource(it)) }
        if (!mcp && info != null) CommandText(info.cliCommand)
        FooterNote(stringResource(R.string.relay_connection_scope))
        FooterNote(stringResource(if (mcp) R.string.relay_client_help else R.string.relay_cli_help))
    }
    FooterNote(stringResource(R.string.relay_intro))
    if (failed) FooterNote(stringResource(R.string.relay_failed))
    if (confirm) MikaDialog(onDismissRequest = { confirm = false },
        title = { Text(stringResource(R.string.relay_unpair)) }, text = { Text(stringResource(R.string.relay_unpair_body)) },
        confirmButton = { TextButton({ confirm = false; onUnpair() }) { Text(stringResource(R.string.relay_unpair)) } },
        dismissButton = { TextButton({ confirm = false }) { Text(stringResource(R.string.cancel)) } })
}
