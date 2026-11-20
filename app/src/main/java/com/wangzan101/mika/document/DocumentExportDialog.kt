package com.wangzan101.mika.document

import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wangzan101.mika.R
import com.wangzan101.mika.core.document.DocumentFormat
import com.wangzan101.mika.ui.viewer.FileViewer

@Composable
internal fun DocumentExportDialog(session: DocumentExportSession, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var sourceStart by remember(session) { mutableIntStateOf(0) }
    val sourceWindow = DocumentSourceWindow.at(session.source, sourceStart)
    // The pending artifact is frozen before opening the picker; a later format never changes its MIME.
    val contract = remember(session) {
        object : ActivityResultContracts.CreateDocument("*/*") {
            override fun createIntent(context: Context, input: String): Intent =
                super.createIntent(context, input).setType(session.pendingSave?.format?.mime ?: session.format.mime)
        }
    }
    val save = rememberLauncherForActivityResult(contract) { session.saveResult(context, it) }
    Dialog(
        onDismissRequest = { if (!session.busy) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false),
    ) {
        Surface(Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState())
                    .padding(20.dp).testTag("document-export"),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.document_export), Modifier.weight(1f))
                    TextButton(onClick = onDismiss, enabled = !session.busy) { Text(stringResource(R.string.document_close)) }
                }
                Text(stringResource(R.string.document_source_note))
                OutlinedTextField(
                    session.title, session::editTitle, Modifier.fillMaxWidth().testTag("document-title"),
                    enabled = !session.busy, label = { Text(stringResource(R.string.document_title)) }, singleLine = true,
                )
                OutlinedTextField(
                    sourceWindow.text, { session.editSource(sourceWindow.replace(session.source, it)) }, Modifier.fillMaxWidth().testTag("document-source"),
                    enabled = !session.busy, label = { Text(stringResource(R.string.document_source)) }, minLines = 5, maxLines = 12,
                )
                if (session.source.length > DocumentSourceWindow.SIZE || sourceWindow.start > 0) {
                    Text(stringResource(R.string.document_source_window))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { sourceStart = (sourceWindow.start - DocumentSourceWindow.SIZE).coerceAtLeast(0) },
                            enabled = !session.busy && sourceWindow.start > 0) { Text(stringResource(R.string.document_previous)) }
                        TextButton(onClick = { sourceStart = sourceWindow.end },
                            enabled = !session.busy && sourceWindow.end < session.source.length) { Text(stringResource(R.string.document_next)) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.selectableGroup()) {
                    DocumentFormat.entries.forEach { format ->
                        FilterChip(selected = session.format == format, onClick = { session.chooseFormat(format) },
                            label = { Text(format.name) }, enabled = !session.busy, modifier = Modifier.testTag("document-${format.extension}"))
                    }
                }
                if (session.format == DocumentFormat.CSV) {
                    Text(stringResource(R.string.document_csv_note))
                    if (session.tables.size > 1) {
                        Text(stringResource(R.string.document_choose_table))
                        Column(Modifier.selectableGroup()) {
                            session.tables.forEachIndexed { index, table ->
                                Row(
                                    Modifier.fillMaxWidth().selectable(selected = session.tableIndex == index,
                                        enabled = !session.busy, role = Role.RadioButton, onClick = { session.chooseTable(index) }).padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    RadioButton(selected = session.tableIndex == index, onClick = null, enabled = !session.busy)
                                    Text(stringResource(R.string.document_table_choice, index + 1, table.columns.take(4).joinToString(" · ") { it.take(40) }, table.rows.size))
                                }
                            }
                        }
                    }
                }
                Text(stringResource(session.status), Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("document-status"))
                if (session.busy) CircularProgressIndicator()
                if (session.generated == null) {
                    Button(onClick = { session.generate(context) }, enabled = !session.busy, modifier = Modifier.testTag("document-generate")) {
                        Text(stringResource(R.string.document_generate))
                    }
                }
                session.generated?.let { document ->
                    Text(document.file.name)
                    Button(onClick = {
                        try { DocumentFiles.retain(document); FileViewer.open(context, document.uri, document.file.name) }
                        catch (_: Exception) { session.failed() }
                    }, enabled = !session.busy, modifier = Modifier.testTag("document-preview")) { Text(stringResource(R.string.document_preview)) }
                    Button(onClick = {
                        try { session.beginSave()?.let { save.launch(it.file.name) } }
                        catch (_: Exception) { session.failed() }
                    }, enabled = !session.busy, modifier = Modifier.testTag("document-save")) { Text(stringResource(R.string.document_save)) }
                    Button(onClick = {
                        try { context.startActivity(DocumentFiles.shareIntent(document)); session.shareOpened() }
                        catch (_: Exception) { session.failed() }
                    }, enabled = !session.busy, modifier = Modifier.testTag("document-share")) { Text(stringResource(R.string.document_share)) }
                    TextButton(onClick = { session.generate(context) }, enabled = !session.busy) { Text(stringResource(R.string.document_regenerate)) }
                }
            }
        }
    }
}
