package com.wangzan101.mika.woowbot

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextOverflow
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.appearanceDark
import com.wangzan101.mika.ui.theme.systemBarsFor
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.R
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.theme.MikaTheme

class BotServicesActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) = super.attachBaseContext(AppLanguage.wrap(newBase))
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.WOOWTECHBOT_ENABLED) { finish(); return }
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
                })
            }
        }
    }
    companion object {
        fun intent(context: Context) = Intent(context, BotServicesActivity::class.java)
    }
}

/** Embeddable management screen. Opening a service does not claim it has authenticated. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BotServicesScreen(registry: BotServiceRegistry, onLocal: () -> Unit, onOpen: (String) -> Unit,
    onClose: () -> Unit = onLocal, selectedId: String? = null, onManage: (String) -> Unit = onOpen) {
    val state by registry.state.collectAsState()
    val supported = remember { BotServices.supportsIsolation() }
    var adding by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(registry) { runCatching { BotServices.cleanRetired(registry) }.onFailure { error = true } }
    val c = MikaTheme.colors
    Scaffold(containerColor = c.bg, topBar = { TopAppBar(title = { Text(stringResource(R.string.bot_ui_services)) }, navigationIcon = {
        IconButton(onClick = onClose) { Icon(MikaIcons.Back, stringResource(R.string.bot_ui_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(stringResource(R.string.bot_workspace_hint), color = c.ink2, style = MaterialTheme.typography.bodyMedium) }
            item { Text(stringResource(R.string.bot_workspace_device), color = c.ink3, style = MaterialTheme.typography.labelMedium) }
            item {
                Row(Modifier.fillMaxWidth().background(if (selectedId == null) c.accentSoft else c.surface, RoundedCornerShape(16.dp))
                    .clickable(onClick = onLocal).padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(MikaIcons.Chats, null, Modifier.size(28.dp))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(R.string.bot_workspace_local_detail), color = c.ink2, style = MaterialTheme.typography.bodySmall)
                    }
                    Icon(if (selectedId == null) MikaIcons.Check else MikaIcons.Chevron, null)
                }
            }
            item { Text(stringResource(R.string.bot_services_title), color = c.ink3, style = MaterialTheme.typography.labelMedium) }
            if (!supported) item { Text(stringResource(R.string.bot_services_unsupported), color = c.bad) }
            if (error) item { Text(stringResource(R.string.bot_services_action_error), color = c.bad) }
            items(state.services, key = { it.id }) { service ->
                Row(Modifier.fillMaxWidth().background(if (selectedId == service.id) c.accentSoft else c.surface, RoundedCornerShape(16.dp))
                    .clickable(enabled = supported) {
                        runCatching { registry.setEnabled(service.id, true); onOpen(service.id) }.onFailure { error = true }
                    }.padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(MikaIcons.Link, null, Modifier.size(28.dp))
                    Column(Modifier.weight(1f)) {
                        Text(service.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(service.origin, color = c.ink2, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (!service.enabled) Text(stringResource(R.string.bot_services_disconnected), color = c.ink3, style = MaterialTheme.typography.bodySmall)
                    }
                    if (selectedId == service.id) Icon(MikaIcons.Check, stringResource(R.string.bot_ui_selected), Modifier.size(18.dp))
                    IconButton(onClick = { onManage(service.id) }, enabled = supported) { Icon(MikaIcons.More, stringResource(R.string.bot_services_manage_session)) }
                }
            }
            item { OutlinedButton(onClick = { adding = true }, modifier = Modifier.fillMaxWidth(), enabled = state.services.size < BotServiceRegistry.MAX_SERVICES) {
                Icon(MikaIcons.Plus, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.bot_services_add))
            } }
        }
    }
    if (adding) {
        var name by remember { mutableStateOf("") }
        var address by remember { mutableStateOf("") }
        var lan by remember { mutableStateOf(false) }
        var invalid by remember { mutableStateOf(false) }
        AlertDialog(onDismissRequest = { adding = false }, title = { Text(stringResource(R.string.bot_services_add)) }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.take(80) }, label = { Text(stringResource(R.string.bot_services_name)) }, singleLine = true)
                OutlinedTextField(address, { address = it.take(BotOrigin.MAX_URL) }, label = { Text(stringResource(R.string.bot_services_address)) }, singleLine = true)
                Row { Checkbox(lan, { lan = it }); Text(stringResource(R.string.bot_services_lan_opt_in)) }
                if (invalid) Text(stringResource(R.string.bot_services_invalid), color = MaterialTheme.colorScheme.error)
            }
        }, confirmButton = { TextButton(onClick = {
            runCatching { registry.add(name, address, lan) }.onSuccess { adding = false }.onFailure { invalid = true }
        }) { Text(stringResource(R.string.bot_services_add)) } }, dismissButton = {
            TextButton(onClick = { adding = false }) { Text(stringResource(R.string.bot_services_cancel)) }
        })
    }
}

@Composable
internal fun BotUnavailableScreen(message: Int, onBack: () -> Unit) {
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(message))
            Button(onClick = onBack) { Text(stringResource(R.string.bot_services_local)) }
        }
    }
}
