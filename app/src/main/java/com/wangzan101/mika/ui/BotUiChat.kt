package com.wangzan101.mika.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.chat.BotUiProfile
import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.chat.SharedFile
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.MikaType
import com.wangzan101.mika.ui.viewer.FileViewer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Base64

internal fun botUiEnabled(context: Context) = botUiPackageEnabled(context.packageName, BuildConfig.WOOWTECHBOT_ENABLED, BuildConfig.DEBUG)

internal fun botUiPackageEnabled(packageName: String, enabled: Boolean, debug: Boolean) = enabled &&
    (packageName == "io.woowtech.agent" || (debug && packageName == "io.woowtech.agent.dev"))

@Composable
internal fun BotUiButton(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    IconButton(onClick, enabled = enabled, modifier = Modifier.size(48.dp)) {
        Icon(icon, label, tint = MikaTheme.colors.ink.copy(alpha = if (enabled) 1f else .4f))
    }
}

@Composable
internal fun BotUiRoundButton(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    val c = MikaTheme.colors
    // `.icon-button`: a 40 dp circle on the card colour with a hairline, inside a 48 dp touch target.
    Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        IconButton(onClick, enabled = enabled, modifier = Modifier.size(40.dp)
            .clip(CircleShape).background(c.surface).border(1.dp, c.hair, CircleShape)) {
            Icon(icon, label, Modifier.size(20.dp), tint = c.ink.copy(alpha = if (enabled) 1f else .4f))
        }
    }
}

@Composable
internal fun BotUiPage(title: String, onClose: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        NoDialogDim()
        Column(Modifier.fillMaxSize().background(MikaTheme.colors.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f).padding(start = 8.dp), style = MikaType.Title, color = MikaTheme.colors.ink)
                actions()
                BotUiRoundButton(MikaIcons.Close, stringResource(R.string.bot_ui_close), onClick = onClose)
            }
            content()
        }
    }
}

/** Bounded decode and local 320px centre crop; never persists a provider URI or uploads anything. */
internal fun botUiImportAvatar(context: Context, uri: Uri): String {
    val bytes = context.contentResolver.openInputStream(uri)!!.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= 12 * 1024 * 1024)
            output.write(buffer, 0, count)
        }
        output.toByteArray()
    }
    require(bytes.size <= 12 * 1024 * 1024)
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    require(bounds.outWidth > 0 && bounds.outHeight > 0)
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1024) sample *= 2
    val source = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }))
    val edge = minOf(source.width, source.height)
    val crop = Bitmap.createBitmap(source, (source.width - edge) / 2, (source.height - edge) / 2, edge, edge)
    val orientation = runCatching { android.media.ExifInterface(bytes.inputStream()).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1) }.getOrDefault(1)
    val matrix = android.graphics.Matrix().apply {
        when (orientation) {
            2 -> setScale(-1f, 1f)
            3 -> setRotate(180f)
            4 -> setScale(1f, -1f)
            5 -> { setRotate(90f); postScale(-1f, 1f) }
            6 -> setRotate(90f)
            7 -> { setRotate(-90f); postScale(-1f, 1f) }
            8 -> setRotate(-90f)
        }
    }
    val oriented = Bitmap.createBitmap(crop, 0, 0, crop.width, crop.height, matrix, true)
    val scaled = Bitmap.createScaledBitmap(oriented, 320, 320, true)
    // JPEG has no transparency: a transparent PNG or WebP is laid on white first, as iOS does (iOS parity k9, owner
    // 2026-11-28), instead of the encoder turning its clear pixels black.
    val opaque = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888)
    android.graphics.Canvas(opaque).apply {
        drawColor(android.graphics.Color.WHITE)
        drawBitmap(scaled, 0f, 0f, android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
    }
    val output = ByteArrayOutputStream()
    check(opaque.compress(Bitmap.CompressFormat.JPEG, 90, output))
    val result = Base64.getEncoder().encodeToString(output.toByteArray())
    opaque.recycle()
    if (scaled !== oriented) scaled.recycle()
    if (oriented !== crop) oriented.recycle()
    if (crop !== source) crop.recycle()
    source.recycle()
    return result
}

@Composable
internal fun BotUiFind(exchanges: List<Exchange>, onClose: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val messages = remember(exchanges, query) { botUiMessages(exchanges).filter { query.isNotBlank() && it.contains(query.trim(), ignoreCase = true) } }
    BotUiPage(stringResource(R.string.bot_ui_find), onClose) {
        BotUiSearchPill(query, { query = it }, stringResource(R.string.bot_ui_find), Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
        Text(stringResource(R.string.bot_ui_matches, messages.size), Modifier.padding(horizontal = 24.dp, vertical = 4.dp), color = MikaTheme.colors.ink2, fontSize = 12.sp, lineHeight = 16.sp)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(messages) { text -> androidx.compose.foundation.text.selection.SelectionContainer {
                Text(text, Modifier.fillMaxWidth().background(MikaTheme.colors.surface, RoundedCornerShape(12.dp)).padding(16.dp), color = MikaTheme.colors.ink, fontSize = 15.sp, lineHeight = 22.sp)
            } }
        }
    }
}

internal fun botUiMessages(exchanges: List<Exchange>): List<String> = exchanges.flatMap { ex ->
    listOfNotNull(ex.goal, ex.draft, when(val status = ex.status) {
        is ExchangeStatus.Done -> status.answer
        is ExchangeStatus.Cancelled -> status.summary
        is ExchangeStatus.Failed -> status.reason
        is ExchangeStatus.NeedsInput -> status.prompt
        is ExchangeStatus.NeedsTakeover -> status.message
        is ExchangeStatus.NeedsConfirmation -> status.title + "\n" + status.body
        is ExchangeStatus.Paused -> status.why
        is ExchangeStatus.Queued -> status.why
        else -> null
    }) + ex.steers.flatMap { listOfNotNull(it.text, it.finished, it.interrupted) }
}.filter { it.isNotBlank() }

@Composable
internal fun BotUiFiles(files: List<SharedFile>, onClose: () -> Unit) {
    val context = LocalContext.current
    BotUiPage(stringResource(R.string.bot_ui_files), onClose) {
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (files.isEmpty()) item { Text(stringResource(R.string.bot_ui_no_files), color = MikaTheme.colors.ink2, fontSize = 14.sp, lineHeight = 20.sp) }
            items(files.distinctBy { it.uri }) { file ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MikaTheme.colors.surface)
                    .clickable { FileViewer.open(context, Uri.parse(file.uri), file.name) }.padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(MikaIcons.Doc, null, Modifier.size(20.dp), tint = MikaTheme.colors.ink2)
                    Text(file.name, Modifier.weight(1f), color = MikaTheme.colors.ink, fontSize = 15.sp, lineHeight = 20.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
