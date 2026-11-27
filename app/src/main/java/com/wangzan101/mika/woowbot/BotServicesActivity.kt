package com.wangzan101.mika.woowbot

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.BotUiCard
import com.wangzan101.mika.ui.BotUiCardDivider
import com.wangzan101.mika.ui.BotUiPillButton
import com.wangzan101.mika.ui.BotUiSectionLabel
import com.wangzan101.mika.ui.BotUiSettingsRow
import com.wangzan101.mika.ui.BotUiSheet
import com.wangzan101.mika.ui.BotUiTextField
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.appearanceDark
import com.wangzan101.mika.ui.theme.systemBarsFor

/** Translucent host ([R.style.Theme_Mika_Sheet]): the sheet rises over whatever opened it and finishes after its exit motion. */
class BotServicesActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) = super.attachBaseContext(AppLanguage.wrap(newBase))
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.WOOWTECHBOT_ENABLED) { finish(); return }
        val startAdding = intent.getBooleanExtra(EXTRA_ADD, false)
        setContent {
            val dark = appearanceDark()
            SideEffect { systemBarsFor(dark) }
            MikaTheme(dark = dark) {
                val registry = remember { runCatching { BotServices.registry(this) }.getOrNull() }
                if (registry == null) BotUnavailableScreen(R.string.bot_services_storage_error) { finish() }
                else BotServicesScreen(registry, onLocal = { finish() }, onOpen = {
                    startActivity(BotServiceActivity.intent(this, it))
                    finish()
                }, onClose = { finish() }, onManage = {
                    startActivity(BotServiceActivity.intent(this, it).putExtra(BotServiceActivity.EXTRA_MANAGE, true)); finish()
                }, startAdding = startAdding)
            }
        }
    }
    companion object {
        const val EXTRA_ADD = "add"
        fun intent(context: Context) = Intent(context, BotServicesActivity::class.java)
    }
}

/**
 * The assistant and service switcher, as a bottom sheet in the website's settings style. Opening a service does not claim it has
 * authenticated; [onClose] runs after the sheet's exit motion.
 */
@Composable
fun BotServicesScreen(registry: BotServiceRegistry, onLocal: () -> Unit, onOpen: (String) -> Unit,
    onClose: () -> Unit = onLocal, selectedId: String? = null, onManage: (String) -> Unit = onOpen, startAdding: Boolean = false) {
    val state by registry.state.collectAsState()
    val supported = remember { BotServices.supportsIsolation() }
    var adding by remember { mutableStateOf(startAdding) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(registry) { runCatching { BotServices.cleanRetired(registry) }.onFailure { error = true } }
    BotUiSheet(stringResource(R.string.bot_ui_services), onDismissRequest = onClose) {
        val c = MikaTheme.colors
        Text(stringResource(R.string.bot_workspace_hint), Modifier.padding(horizontal = 8.dp), color = c.ink2, fontSize = 14.sp, lineHeight = 20.sp)
        BotUiSectionLabel(stringResource(R.string.bot_workspace_device))
        BotUiCard {
            BotUiSettingsRow(
                title = stringResource(R.string.app_name), subtitle = stringResource(R.string.bot_workspace_local_detail),
                icon = MikaIcons.Chats, onClick = onLocal,
                trailing = {
                    Icon(if (selectedId == null) MikaIcons.Check else MikaIcons.Chevron,
                        if (selectedId == null) stringResource(R.string.bot_ui_selected) else null, Modifier.size(18.dp), tint = if (selectedId == null) c.ink else c.ink3)
                },
            )
        }
        BotUiSectionLabel(stringResource(R.string.bot_services_title))
        if (!supported) Text(stringResource(R.string.bot_services_unsupported), Modifier.padding(horizontal = 8.dp), color = c.bad, fontSize = 13.sp, lineHeight = 18.sp)
        if (error) Text(stringResource(R.string.bot_services_action_error), Modifier.padding(horizontal = 8.dp), color = c.bad, fontSize = 13.sp, lineHeight = 18.sp)
        if (state.services.isNotEmpty()) BotUiCard {
            state.services.forEachIndexed { index, service ->
                if (index > 0) BotUiCardDivider()
                BotUiSettingsRow(
                    title = service.name,
                    subtitle = if (service.enabled) service.origin else service.origin + "\n" + stringResource(R.string.bot_services_disconnected),
                    icon = MikaIcons.Link, enabled = supported,
                    onClick = { runCatching { registry.setEnabled(service.id, true); onOpen(service.id) }.onFailure { error = true } },
                    trailing = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (selectedId == service.id) Icon(MikaIcons.Check, stringResource(R.string.bot_ui_selected), Modifier.size(18.dp), tint = c.ink)
                            Box(Modifier.size(40.dp).clip(CircleShape).clickable(enabled = supported) { onManage(service.id) }, contentAlignment = Alignment.Center) {
                                Icon(MikaIcons.More, stringResource(R.string.bot_services_manage_session), Modifier.size(20.dp), tint = c.ink2)
                            }
                        }
                    },
                )
            }
        }
        BotUiPillButton(stringResource(R.string.bot_services_add), onClick = { adding = true }, icon = MikaIcons.Plus,
            enabled = state.services.size < BotServiceRegistry.MAX_SERVICES)
    }
    if (adding) AddServiceDialog(registry) { adding = false }
}

/** A dialog on the website's popover surface (the theme gives it the menu colour and radius). */
@Composable
private fun AddServiceDialog(registry: BotServiceRegistry, onDone: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var lan by remember { mutableStateOf(false) }
    var invalid by remember { mutableStateOf(false) }
    val c = MikaTheme.colors
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text(stringResource(R.string.bot_services_add), fontSize = 19.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                BotUiTextField(stringResource(R.string.bot_services_name), name, { name = it.take(80) })
                BotUiTextField(stringResource(R.string.bot_services_address), address, { address = it.take(BotOrigin.MAX_URL) }, keyboardType = KeyboardType.Uri)
                Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable { lan = !lan }, verticalAlignment = Alignment.Top) {
                    Checkbox(lan, { lan = it })
                    Text(stringResource(R.string.bot_services_lan_opt_in), Modifier.padding(top = 12.dp, end = 4.dp), color = c.ink2, fontSize = 13.sp, lineHeight = 18.sp)
                }
                if (invalid) Text(stringResource(R.string.bot_services_invalid), color = c.bad, fontSize = 13.sp, lineHeight = 18.sp)
            }
        },
        confirmButton = {
            BotUiPillButton(stringResource(R.string.bot_services_add), primary = true, fill = false, onClick = {
                runCatching { registry.add(name, address, lan) }.onSuccess { onDone() }.onFailure { invalid = true }
            })
        },
        dismissButton = { TextButton(onClick = onDone) { Text(stringResource(R.string.bot_services_cancel), color = c.ink2) } },
    )
}

/** A message and the way back to the local assistant, on the page colour with the app's pill button. */
@Composable
internal fun BotUnavailableScreen(message: Int, onBack: () -> Unit) {
    val c = MikaTheme.colors
    Surface(Modifier.fillMaxSize(), color = c.bg) {
        Column(Modifier.safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(message), color = c.ink, fontSize = 16.sp, lineHeight = 24.sp)
            BotUiPillButton(stringResource(R.string.bot_services_local), onClick = onBack, primary = true, fill = false)
        }
    }
}
