package com.wangzan101.mika.woowbot

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
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
            MikaTheme {
                val registry = remember { runCatching { BotServices.registry(this) }.getOrNull() }
                if (registry == null) BotUnavailableScreen(R.string.bot_services_storage_error) { finish() }
                else BotServicesScreen(registry, onLocal = { finish() }, onOpen = {
                    startActivity(BotServiceActivity.intent(this, it))
                    finish()
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
fun BotServicesScreen(registry: BotServiceRegistry, onLocal: () -> Unit, onOpen: (String) -> Unit) {
    val state by registry.state.collectAsState()
    val supported = remember { BotServices.supportsIsolation() }
    var adding by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(registry) { runCatching { BotServices.cleanRetired(registry) }.onFailure { error = true } }
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.bot_services_title)) }, navigationIcon = {
        TextButton(onClick = onLocal) { Text(stringResource(R.string.bot_services_local)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(stringResource(R.string.bot_services_description)) }
            if (!supported) item { Text(stringResource(R.string.bot_services_unsupported), color = MaterialTheme.colorScheme.error) }
            if (error) item { Text(stringResource(R.string.bot_services_action_error), color = MaterialTheme.colorScheme.error) }
            items(state.services, key = { it.id }) { service ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(service.name, style = MaterialTheme.typography.titleMedium)
                        Text(service.origin, style = MaterialTheme.typography.bodySmall)
                        Text(stringResource(if (service.enabled) R.string.bot_services_ready else R.string.bot_services_disconnected))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(enabled = supported, onClick = {
                                runCatching { registry.setEnabled(service.id, true); onOpen(service.id) }.onFailure { error = true }
                            }) { Text(stringResource(if (service.enabled) R.string.bot_services_open else R.string.bot_services_connect)) }
                            if (service.enabled) TextButton(onClick = {
                                runCatching { registry.setEnabled(service.id, false); BotWebSessions.clear(service.profileName) }.onFailure { error = true }
                            }) { Text(stringResource(R.string.bot_services_disconnect)) }
                        }
                        // Logout runs in the service activity so it can revoke the cookie session before clearing it.
                        TextButton(enabled = supported, onClick = { onOpen(service.id) }) {
                            Text(stringResource(R.string.bot_services_manage_session))
                        }
                    }
                }
            }
            item { OutlinedButton(onClick = { adding = true }, enabled = state.services.size < BotServiceRegistry.MAX_SERVICES) {
                Text(stringResource(R.string.bot_services_add))
            } }
            item { Text(stringResource(R.string.bot_services_disconnect_help), style = MaterialTheme.typography.bodySmall) }
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
