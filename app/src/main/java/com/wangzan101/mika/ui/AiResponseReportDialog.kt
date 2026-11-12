package com.wangzan101.mika.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A report is only saved locally; this UI never claims that a developer received it. */
@Composable
internal fun AiResponseReportDialog(reference: AiResponseReference, response: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val queue = remember(context) { AiResponseReportQueue(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var reason by remember(reference) { mutableStateOf("offensive") }
    var note by remember(reference) { mutableStateOf("") }
    var saving by remember(reference) { mutableStateOf(false) }
    var savedId by remember(reference) { mutableStateOf<String?>(null) }
    var failed by remember(reference) { mutableStateOf(false) }
    val reasons = listOf(
        "offensive" to stringResource(R.string.chat_report_offensive),
        "unsafe" to stringResource(R.string.chat_report_unsafe),
        "other" to stringResource(R.string.chat_report_other),
    )
    AlertDialog(
        onDismissRequest = { if (!saving) onDismiss() },
        title = { Text(stringResource(R.string.chat_report_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.chat_report_local_notice))
                Text(stringResource(R.string.chat_report_reference, reference.runId ?: reference.conversationId, reference.messageKey))
                Text(response.take(300), maxLines = 5, overflow = TextOverflow.Ellipsis)
                if (savedId == null) {
                    reasons.forEach { (id, label) ->
                        FilterChip(selected = reason == id, onClick = { reason = id }, label = { Text(label) }, enabled = !saving)
                    }
                    OutlinedTextField(note, { note = it.take(1_000) }, Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.chat_report_note)) }, minLines = 2, maxLines = 4, enabled = !saving)
                }
                if (failed) Text(stringResource(R.string.chat_report_save_failed), Modifier.testTag("report-save-failed"))
                savedId?.let { Text(stringResource(R.string.chat_report_saved, it), Modifier.testTag("report-saved-local")) }
            }
        },
        confirmButton = {
            if (savedId == null) TextButton(
                onClick = {
                    saving = true
                    failed = false
                    scope.launch {
                        val result = withContext(Dispatchers.IO) { runCatching { queue.save(reference, response, reason, note) } }
                        saving = false
                        result.onSuccess { savedId = it.id }.onFailure { failed = true }
                    }
                }, enabled = !saving,
            ) { Text(stringResource(R.string.chat_report_save_on_device)) }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !saving) {
            Text(stringResource(if (savedId == null) R.string.chat_report_cancel else R.string.chat_report_close))
        } },
        modifier = Modifier.testTag("ai-response-report-dialog"),
    )
}
