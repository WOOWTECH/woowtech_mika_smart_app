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
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.theme.MikaTheme

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
            MikaTheme {
                val controller = BotPushRuntime.controller
                val state = controller?.state?.collectAsState()?.value ?: BotPushState.NOT_CONFIGURED
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(stringResource(R.string.bot_push_settings_title), style = MaterialTheme.typography.headlineSmall)
                        Text(stringResource(R.string.bot_push_settings_privacy))
                        Text(stringResource(if (controller?.configured != true) R.string.bot_push_not_configured else statusText(state)))
                        // Always disclose current server gap, including when the user's preference is off.
                        Text(stringResource(R.string.bot_push_server_not_ready), style = MaterialTheme.typography.bodyMedium)
                        Button(enabled = (controller?.configured == true || controller?.optedIn == true) && state != BotPushState.PENDING, onClick = {
                            if (controller?.optedIn == true) BotPushBootstrap.setOptIn(this@BotPushSettingsActivity, false)
                            else if (Build.VERSION.SDK_INT >= 33 && !BotPushBootstrap.permissionGranted(this@BotPushSettingsActivity))
                                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                            else BotPushBootstrap.setOptIn(this@BotPushSettingsActivity, true)
                        }) { Text(stringResource(if (controller?.optedIn == true) R.string.bot_push_disable else R.string.bot_push_enable)) }
                        OutlinedButton(onClick = {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        }) { Text(stringResource(R.string.bot_push_system_settings)) }
                        TextButton(onClick = { finish() }) { Text(stringResource(R.string.bot_push_back)) }
                    }
                }
            }
        }
    }
    override fun onResume() { super.onResume(); if (BuildConfig.WOOWTECHBOT_ENABLED) BotPushBootstrap.refresh(this) }
    companion object {
        fun intent(context: Context) = Intent(context, BotPushSettingsActivity::class.java)
        private fun statusText(state: BotPushState) = when (state) {
            BotPushState.OFF -> R.string.bot_push_off
            BotPushState.NOT_CONFIGURED -> R.string.bot_push_not_configured
            BotPushState.PERMISSION_REQUIRED -> R.string.bot_push_permission_required
            BotPushState.NO_SERVICES -> R.string.bot_push_no_services
            BotPushState.PENDING -> R.string.bot_push_pending
            BotPushState.SERVER_NOT_READY -> R.string.bot_push_server_not_ready
            BotPushState.REGISTERED -> R.string.bot_push_registered
        }
    }
}
