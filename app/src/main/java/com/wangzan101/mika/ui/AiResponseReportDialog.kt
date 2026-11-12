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
    var loading by remember(reference) { mutableStateOf(true) }
    var loadFailed by remember(reference) { mutableStateOf(false) }
    var ambiguous by remember(reference) { mutableStateOf(false) }
    var unidentified by remember(reference) { mutableStateOf(false) }
    var allowUnidentified by remember(reference) { mutableStateOf(false) }
    var loadVersion by remember(reference) { mutableStateOf(0) }
    var manualCompose by remember(reference) { mutableStateOf(false) }
    var freshWarning by remember(reference) { mutableStateOf(false) }
    var manualSource by remember(reference) { mutableStateOf<AiResponseReport?>(null) }
    var manualResponse by remember(reference) { mutableStateOf(response) }
    var showHistory by remember(reference) { mutableStateOf(false) }
    var history by remember(reference) { mutableStateOf<List<AiResponseReport>>(emptyList()) }
    var historyFailed by remember(reference) { mutableStateOf(false) }
    var reviewExisting by remember(reference) { mutableStateOf(false) }
    var now by remember(reference) { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(reference, loadVersion) {
        loading = true
        if (reference.runId == null && reference.answerId == null) {
            loadFailed = true
            loading = false
            return@LaunchedEffect
        }
        val result = withContext(Dispatchers.IO) { runCatching { queue.find(reference, allowUnidentified) } }
        result.onSuccess { savedReport = it; loadFailed = false; ambiguous = false; unidentified = false }.onFailure {
            loadFailed = true
            ambiguous = it is AmbiguousReportReferenceException || it is DamagedReportReferenceException
            unidentified = it is UnidentifiedReportException
        }
        loading = false
    }
    LaunchedEffect(savedReport?.id, allowUnidentified) {
        val id = savedReport?.id ?: return@LaunchedEffect
        while (true) {
            delay(5_000)
            now = System.currentTimeMillis()
            val result = withContext(Dispatchers.IO) { runCatching {
                if (savedReport?.manualOnly == true) queue.getManual(id, allowUnidentified) else queue.get(id, allowUnidentified)
            } }
            if (!saving) result.getOrNull()?.let { savedReport = it }
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
                if (savedReport?.manualOnly == true) Text(stringResource(R.string.chat_report_selected_manual))
                val selectedManual = savedReport?.takeIf { it.manualOnly }
                if (selectedManual != null) {
                    Text(selectedManual.response)
                    Text(reasons.firstOrNull { it.first == selectedManual.reason }?.second.orEmpty())
                    if (selectedManual.note.isNotBlank()) Text(selectedManual.note)
                } else Text((if (manualCompose) manualResponse else response).take(300), maxLines = 5, overflow = TextOverflow.Ellipsis)
                if (loading) Text(stringResource(R.string.chat_report_loading))
                if (loadFailed) Text(stringResource(when {
                    reference.runId == null && reference.answerId == null -> R.string.chat_report_no_identity
                    unidentified -> R.string.chat_report_unidentified
                    ambiguous -> R.string.chat_report_ambiguous
                    else -> R.string.chat_report_load_failed
                }))
                if (allowUnidentified) Text(stringResource(R.string.chat_report_continue_notice))
                if (manualCompose || savedReport?.manualOnly == true) Text(stringResource(R.string.chat_report_manual_notice))
                if (freshWarning) Text(stringResource(R.string.chat_report_new_warning))
                TextButton(onClick = {
                    scope.launch {
                        val result = withContext(Dispatchers.IO) { runCatching { queue.manualReports(reference.conversationId, allowUnidentified) } }
                        result.onSuccess { history = it; showHistory = true; historyFailed = false }.onFailure {
                            if (it is UnidentifiedReportException) { loadFailed = true; unidentified = true }
                            else historyFailed = true
                        }
                    }
                }, enabled = !saving) { Text(stringResource(R.string.chat_report_history)) }
                if (historyFailed) Text(stringResource(R.string.chat_report_load_failed))
                if (reviewExisting) Text(stringResource(R.string.chat_report_review_existing))
                if (showHistory) {
                    Text(stringResource(R.string.chat_report_history_notice))
                    if (history.isEmpty()) Text(stringResource(R.string.chat_report_history_empty))
                    history.forEach { report ->
                        TextButton(onClick = {
                            savedReport = report; manualCompose = false; freshWarning = false
                            loadFailed = false; showHistory = false; failed = false; reviewExisting = false
                        }, enabled = !saving) {
                            Text("${report.id}\n${report.response.take(200)}", maxLines = 4, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                if (!loading && !loadFailed && savedReport == null) {
                    reasons.forEach { (id, label) ->
                        FilterChip(selected = reason == id, onClick = { reason = id }, label = { Text(label) }, enabled = !saving)
                    }
                    OutlinedTextField(note, { note = it.take(1_000) }, Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.chat_report_note)) }, minLines = 2, maxLines = 4, enabled = !saving)
                }
                if (failed) Text(stringResource(R.string.chat_report_save_failed), Modifier.testTag("report-save-failed"))
                savedReport?.let { report ->
                    Text(stringResource(if (report.status == "acknowledged") R.string.chat_report_acknowledged
                        else if (reportOutsideIntakeWindow(report, now)) R.string.chat_report_expired
                        else if (report.status == "rejected" || report.attempts >= 3) R.string.chat_report_needs_retry
                        else R.string.chat_report_pending, report.id),
                        Modifier.testTag("report-delivery-status"))
                }
            }
        },
        confirmButton = {
            if (freshWarning && !loading) TextButton(onClick = {
                val source = savedReport ?: return@TextButton
                manualSource = source; manualResponse = source.response
                reason = source.reason; note = source.note
                savedReport = null; manualCompose = true; freshWarning = false; showHistory = false
            }) { Text(stringResource(R.string.chat_report_continue_risk)) }
            else if (loadFailed && !loading && (ambiguous || reference.runId == null && reference.answerId == null)) TextButton(onClick = {
                allowUnidentified = true; manualSource = null; manualResponse = response
                manualCompose = true; loadFailed = false; showHistory = false
            }) { Text(stringResource(R.string.chat_report_continue_risk)) }
            else if (loadFailed && !loading && unidentified) TextButton(onClick = {
                allowUnidentified = true
                loadVersion++
            }) { Text(stringResource(R.string.chat_report_continue_risk)) }
            else if (loadFailed && !loading && (reference.runId != null || reference.answerId != null)) TextButton(onClick = { loadVersion++ }) {
                Text(stringResource(R.string.chat_report_retry))
            }
            else if (!loading && !loadFailed && savedReport == null) TextButton(
                onClick = {
                    if (saving) return@TextButton
                    saving = true
                    failed = false
                    reviewExisting = false
                    scope.launch {
                        val result = runCatching {
                            if (manualCompose) AiResponseReportDelivery.createManual(queue, manualSource?.reference ?: reference, manualResponse, reason, note,
                                manualSource?.id, allowUnidentified)
                            else withContext(Dispatchers.IO) { queue.save(reference, response, reason, note, allowUnidentified) }
                        }
                        result.onSuccess { report ->
                            savedReport = report
                            manualCompose = false
                            saving = false
                            runCatching {
                                val sender = AiResponseReportDelivery.sender(context.applicationContext)
                                if (report.status == "acknowledged") report
                                else if (report.manualOnly) AiResponseReportDelivery.sendManual(queue, sender, report.id, allowUnidentified)
                                else if (allowUnidentified) AiResponseReportDelivery.deliverOne(queue, sender, report.id)
                                else {
                                    AiResponseReportDelivery.deliverDue(queue, sender)
                                    withContext(Dispatchers.IO) { queue.get(report.id) }
                                }
                            }.onSuccess { it?.let { report -> savedReport = report } }.onFailure {
                                if (it is UnidentifiedReportException) { loadFailed = true; unidentified = true }
                            }
                        }.onFailure {
                            if (it is ExistingManualReportException) {
                                savedReport = it.report; manualCompose = false; reviewExisting = true
                            } else if (it is UnidentifiedReportException) { loadFailed = true; unidentified = true }
                            else failed = true
                            saving = false
                        }
                    }
                }, enabled = !saving,
            ) { Text(stringResource(R.string.chat_report_submit)) }
            else if (!loading && !loadFailed && savedReport != null && savedReport?.status != "acknowledged" &&
                reportOutsideIntakeWindow(requireNotNull(savedReport), now)) TextButton(onClick = { freshWarning = true }) {
                Text(stringResource(R.string.chat_report_create_new))
            }
            else if (!loading && !loadFailed && savedReport != null && savedReport?.status != "acknowledged") TextButton(
                onClick = {
                    if (saving) return@TextButton
                    val id = savedReport?.id ?: return@TextButton
                    saving = true
                    failed = false
                    scope.launch {
                        runCatching {
                            val sender = AiResponseReportDelivery.sender(context.applicationContext)
                            if (savedReport?.manualOnly == true) AiResponseReportDelivery.sendManual(queue, sender, id, allowUnidentified)
                            else AiResponseReportDelivery.retry(queue, sender, id, allowUnidentified)
                        }.onSuccess { savedReport = it }.onFailure {
                            if (it is UnidentifiedReportException) { loadFailed = true; unidentified = true }
                            else failed = true
                        }
                        now = System.currentTimeMillis()
                        saving = false
                    }
                }, enabled = !saving,
            ) { Text(stringResource(R.string.chat_report_retry)) }
        },
        dismissButton = { TextButton(onClick = { if (freshWarning) freshWarning = false else onDismiss() }, enabled = !saving) {
            Text(stringResource(if (freshWarning) R.string.chat_report_back else if (savedReport == null) R.string.chat_report_cancel else R.string.chat_report_close))
        } },
        modifier = Modifier.testTag("ai-response-report-dialog"),
    )
}
