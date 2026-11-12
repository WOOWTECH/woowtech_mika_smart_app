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
import androidx.compose.runtime.LaunchedEffect
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Shows the persisted delivery state for this response. */
@Composable
internal fun AiResponseReportDialog(reference: AiResponseReference, response: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val queue = remember(context) { AiResponseReportQueue(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var reason by remember(reference) { mutableStateOf("offensive") }
    var note by remember(reference) { mutableStateOf("") }
    var saving by remember(reference) { mutableStateOf(false) }
    var savedReport by remember(reference) { mutableStateOf<AiResponseReport?>(null) }
    var failed by remember(reference) { mutableStateOf(false) }
    LaunchedEffect(savedReport?.id) {
        val id = savedReport?.id ?: return@LaunchedEffect
        while (true) {
            delay(5_000)
            savedReport = withContext(Dispatchers.IO) { queue.get(id) }
        }
    }
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
                Text(stringResource(R.string.chat_report_delivery_notice))
                Text(stringResource(R.string.chat_report_reference, reference.runId ?: reference.conversationId, reference.messageKey))
                Text(response.take(300), maxLines = 5, overflow = TextOverflow.Ellipsis)
                if (savedReport == null) {
                    reasons.forEach { (id, label) ->
                        FilterChip(selected = reason == id, onClick = { reason = id }, label = { Text(label) }, enabled = !saving)
                    }
                    OutlinedTextField(note, { note = it.take(1_000) }, Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.chat_report_note)) }, minLines = 2, maxLines = 4, enabled = !saving)
                }
                if (failed) Text(stringResource(R.string.chat_report_save_failed), Modifier.testTag("report-save-failed"))
                savedReport?.let { report ->
                    Text(stringResource(if (report.status == "acknowledged") R.string.chat_report_acknowledged
                        else if (report.status == "rejected" || report.attempts >= 3) R.string.chat_report_needs_retry
                        else R.string.chat_report_pending, report.id),
                        Modifier.testTag("report-delivery-status"))
                }
            }
        },
        confirmButton = {
            if (savedReport == null) TextButton(
                onClick = {
                    saving = true
                    failed = false
                    scope.launch {
                        val result = withContext(Dispatchers.IO) { runCatching { queue.save(reference, response, reason, note) } }
                        saving = false
                        result.onSuccess { report ->
                            savedReport = report
                            AiResponseReportDelivery.deliverDue(queue, AiResponseReportDelivery.sender(context.applicationContext))
                            savedReport = withContext(Dispatchers.IO) { queue.get(report.id) }
                        }.onFailure { failed = true }
                    }
                }, enabled = !saving,
            ) { Text(stringResource(R.string.chat_report_submit)) }
            else if (savedReport?.status != "acknowledged" &&
                (savedReport?.status == "rejected" || (savedReport?.attempts ?: 0) >= 3)) TextButton(
                onClick = {
                    val id = savedReport?.id ?: return@TextButton
                    scope.launch {
                        savedReport = withContext(Dispatchers.IO) { queue.retry(id) }
                        AiResponseReportDelivery.deliverDue(queue, AiResponseReportDelivery.sender(context.applicationContext))
                        savedReport = withContext(Dispatchers.IO) { queue.get(id) }
                    }
                }
            ) { Text(stringResource(R.string.chat_report_retry)) }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !saving) {
            Text(stringResource(if (savedReport == null) R.string.chat_report_cancel else R.string.chat_report_close))
        } },
        modifier = Modifier.testTag("ai-response-report-dialog"),
    )
}
