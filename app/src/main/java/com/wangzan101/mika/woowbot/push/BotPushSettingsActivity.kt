package com.wangzan101.mika.woowbot.push

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.BotUiCard
import com.wangzan101.mika.ui.BotUiCardDivider
import com.wangzan101.mika.ui.BotUiSectionLabel
import com.wangzan101.mika.ui.BotUiSettingsRow
import com.wangzan101.mika.ui.BotUiSheet
import com.wangzan101.mika.ui.BotUiSwitch
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.appearanceDark
import com.wangzan101.mika.ui.theme.systemBarsFor
import com.wangzan101.mika.woowbot.BotServices

/** Bot notifications as a bottom sheet in the website's settings style; a translucent host, so it rises over the previous screen. */
class BotPushSettingsActivity : ComponentActivity() {
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) BotPushBootstrap.setOptIn(this, true)
        else BotPushBootstrap.refresh(this)
    }
    override fun attachBaseContext(newBase: Context) = super.attachBaseContext(AppLanguage.wrap(newBase))
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.WOOWTECHBOT_ENABLED) { finish(); return }
        BotPushBootstrap.install(this)
        setContent {
            val dark = appearanceDark()
            SideEffect { systemBarsFor(dark) }
            MikaTheme(dark = dark) {
                val controller = BotPushRuntime.controller
                val state = controller?.state?.collectAsState()?.value ?: BotPushState.NOT_CONFIGURED
                val discovery = controller?.discovery?.collectAsState()?.value.orEmpty()
                val services by remember { BotServices.registry(this) }.state.collectAsState()
                BotUiSheet(stringResource(R.string.bot_push_settings_title), onDismissRequest = { finish() }) {
                    val c = MikaTheme.colors
                    Text(stringResource(R.string.bot_push_settings_privacy), Modifier.padding(horizontal = 8.dp), color = c.ink2, fontSize = 14.sp, lineHeight = 20.sp)
                    BotUiCard {
                        BotUiSettingsRow(
                            title = stringResource(R.string.bot_push_enable),
                            subtitle = stringResource(if (controller?.configured != true) R.string.bot_push_not_configured else statusText(state)),
                            icon = MikaIcons.Bell,
                            trailing = {
                                BotUiSwitch(
                                    checked = controller?.optedIn == true,
                                    onCheckedChange = {
                                        if (controller?.optedIn == true) BotPushBootstrap.setOptIn(this@BotPushSettingsActivity, false)
                                        else if (Build.VERSION.SDK_INT >= 33 && !BotPushBootstrap.permissionGranted(this@BotPushSettingsActivity))
                                            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                                        else BotPushBootstrap.setOptIn(this@BotPushSettingsActivity, true)
                                    },
                                    enabled = (controller?.configured == true || controller?.optedIn == true) && state != BotPushState.PENDING,
                                )
                            },
                        )
                        if (state == BotPushState.RETRY_REQUIRED || state == BotPushState.SERVER_NOT_READY) {
                            BotUiCardDivider()
                            BotUiSettingsRow(
                                title = stringResource(R.string.bot_push_retry), icon = MikaIcons.Refresh,
                                onClick = { BotPushBootstrap.refresh(this@BotPushSettingsActivity) },
                                trailing = { Icon(MikaIcons.Chevron, null, Modifier.size(18.dp), tint = c.ink3) },
                            )
                        }
                        BotUiCardDivider()
                        BotUiSettingsRow(
                            title = stringResource(R.string.bot_push_system_settings), icon = MikaIcons.Gear,
                            onClick = { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)) },
                            trailing = { Icon(MikaIcons.Chevron, null, Modifier.size(18.dp), tint = c.ink3) },
                        )
                    }
                    val enabledServices = services.services.filter { it.enabled }
                    if (enabledServices.isNotEmpty()) {
                        BotUiSectionLabel(stringResource(R.string.bot_services_title))
                        BotUiCard {
                            enabledServices.forEachIndexed { index, service ->
                                if (index > 0) BotUiCardDivider()
                                BotUiSettingsRow(title = service.name, subtitle = stringResource(discoveryText(discovery[service.id])), icon = MikaIcons.Link)
                            }
                        }
                    }
                }
            }
        }
    }
    override fun onResume() { super.onResume(); if (BuildConfig.WOOWTECHBOT_ENABLED) BotPushBootstrap.refresh(this) }
    companion object {
        fun intent(context: Context) = Intent(context, BotPushSettingsActivity::class.java)
        private fun discoveryText(state: BotPushDiscovery?) = when (state) {
            null, BotPushDiscovery.CHECKING -> R.string.bot_push_discovery_checking
            BotPushDiscovery.READY -> R.string.bot_push_discovery_ready
            BotPushDiscovery.SIGN_IN_REQUIRED -> R.string.bot_push_discovery_sign_in
            BotPushDiscovery.IDENTITY_CHANGED -> R.string.bot_push_discovery_changed
            BotPushDiscovery.SERVER_NOT_READY -> R.string.bot_push_server_not_ready
            BotPushDiscovery.UNAVAILABLE -> R.string.bot_push_discovery_unavailable
        }
        private fun statusText(state: BotPushState) = when (state) {
            BotPushState.OFF -> R.string.bot_push_off
            BotPushState.NOT_CONFIGURED -> R.string.bot_push_not_configured
            BotPushState.PERMISSION_REQUIRED -> R.string.bot_push_permission_required
            BotPushState.NO_SERVICES -> R.string.bot_push_no_services
            BotPushState.PENDING -> R.string.bot_push_pending
            BotPushState.RETRY_REQUIRED -> R.string.bot_push_retry_required
            BotPushState.SERVER_NOT_READY -> R.string.bot_push_server_not_ready
            BotPushState.REGISTERED -> R.string.bot_push_registered
        }
    }
}
