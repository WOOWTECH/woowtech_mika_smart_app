package com.wangzan101.mika.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
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

internal val botUiColors = listOf(0xff6b83f6, 0xff32a898, 0xffcf83e8, 0xffe9a05c, 0xffdb748d, 0xff7a879d).map { Color(it) }

@Composable
internal fun BotUiButton(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    IconButton(onClick, enabled = enabled, modifier = Modifier.size(48.dp)) {
        Icon(icon, label, tint = MikaTheme.colors.ink.copy(alpha = if (enabled) 1f else .4f))
    }
}

@Composable
internal fun BotUiRoundButton(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    val c = MikaTheme.colors
    Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        IconButton(onClick, enabled = enabled, modifier = Modifier.size(42.dp)
            .clip(CircleShape).background(c.surface).border(1.dp, c.hair, CircleShape)) {
            Icon(icon, label, Modifier.size(22.dp), tint = c.ink.copy(alpha = if (enabled) 1f else .4f))
        }
    }
}

@Composable
internal fun BotUiAvatar(profile: BotUiProfile, modifier: Modifier = Modifier.size(32.dp)) {
    val bitmap by produceState<Bitmap?>(null, profile.image) {
        value = withContext(Dispatchers.Default) { runCatching {
            profile.image?.let { Base64.getDecoder().decode(it) }?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        }.getOrNull() }
    }
    val description = stringResource(R.string.bot_ui_avatar)
    if (bitmap != null) Image(bitmap!!.asImageBitmap(), description, modifier.clip(RoundedCornerShape(10.dp)))
    else Canvas(modifier.semantics { contentDescription = description }) {
        val w = size.width; val h = size.height
        val color = botUiColors[profile.color.coerceIn(0, 5)]
        val radius = when (profile.robot) { 1 -> w * .3f; 2 -> w * .04f; else -> w * .16f }
        drawRoundRect(color, Offset(w * .1f, h * .23f), Size(w * .8f, h * .65f), CornerRadius(radius))
        drawLine(color, Offset(w * .5f, h * .1f), Offset(w * .5f, h * .25f), w * .055f)
        drawCircle(color, w * .07f, Offset(w * .5f, h * .1f))
        for (x in listOf(.33f, .67f)) {
            if (profile.face == 1) drawLine(Color.White, Offset(w*(x-.06f), h*.48f), Offset(w*(x+.06f), h*.48f), w*.05f)
            else drawCircle(Color.White, w * (if (profile.face == 2) .08f else .055f), Offset(w*x, h*.48f))
        }
        drawLine(Color.White, Offset(w*.39f,h*.7f), Offset(w*.61f,h*.7f), w*.035f)
    }
}

@Composable
internal fun BotUiPage(title: String, onClose: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(MikaTheme.colors.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                BotUiButton(MikaIcons.Close, stringResource(R.string.bot_ui_close), onClick = onClose)
                Text(title, Modifier.weight(1f), style = MikaType.Title, color = MikaTheme.colors.ink)
                actions()
            }
            content()
        }
    }
}

/** Saved names continue to come from ConversationStore.title, including legacy auto titles. */
@Composable
internal fun BotUiChatHeader(vm: ChatViewModel, ui: ChatUi, subtitle: String?, onHistory: () -> Unit) {
    val context = LocalContext.current
    val store = vm.botUiStore
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(store) { store.changes.collect { revision++ } }
    val fallback = ChatCopy.title(ui.exchanges).ifBlank { context.getString(R.string.app_name) }
    val identity by produceState(Pair(fallback, BotUiProfile()), ui.conversationId, revision, fallback) {
        value = withContext(Dispatchers.IO) {
            (ui.conversationId?.let(store::title) ?: fallback) to
                (ui.conversationId?.let(store::botUiProfile) ?: BotUiProfile())
        }
    }
    var menu by remember(ui.conversationId) { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var finding by rememberSaveable(ui.conversationId) { mutableStateOf(false) }
    var files by rememberSaveable(ui.conversationId) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().background(MikaTheme.colors.bg).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            BotUiRoundButton(MikaIcons.Back, stringResource(R.string.bot_ui_history), onClick = onHistory)
            Row(Modifier.weight(1f).clip(RoundedCornerShape(24.dp)).background(MikaTheme.colors.fill)
                .clickable { editing = vm.botUiConversationId() }.padding(horizontal = 12.dp, vertical = 8.dp)
                .testTag("bot_ui_name_capsule"), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BotUiAvatar(identity.second, Modifier.size(24.dp))
                Text(identity.first, style = MikaType.Body, color = MikaTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Box {
                BotUiRoundButton(MikaIcons.More, stringResource(R.string.bot_ui_more)) { menu = true }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.bot_ui_profile)) }, leadingIcon = { Icon(MikaIcons.Edit, null) }, onClick = { menu = false; editing = vm.botUiConversationId() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_new)) }, leadingIcon = { Icon(MikaIcons.Plus, null) }, enabled = vm.canSwitch(), onClick = { menu = false; vm.newConversation() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.bot_ui_find)) }, leadingIcon = { Icon(MikaIcons.Search, null) }, onClick = { menu = false; finding = true })
                    DropdownMenuItem(text = { Text(stringResource(R.string.bot_ui_files)) }, leadingIcon = { Icon(MikaIcons.Doc, null) }, onClick = { menu = false; files = true })
                }
            }
        }
        subtitle?.let { Text(it, Modifier.padding(start = 60.dp, end = 16.dp, bottom = 6.dp), style = MikaType.Hint, color = MikaTheme.colors.ink3) }
    }
    editing?.let { id -> BotUiProfileEditor(store, id, identity.first) { editing = null } }
    if (finding) BotUiFind(ui.exchanges) { finding = false }
    if (files) BotUiFiles(ui.exchanges.flatMap { it.files }) { files = false }
}

@Composable
internal fun BotUiProfileEditor(store: ConversationStore, id: String, fallback: String, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable(id) { mutableStateOf(fallback) }
    var profile by remember(id) { mutableStateOf(BotUiProfile()) }
    var ready by remember(id) { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    var upload by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(id) {
        val saved = withContext(Dispatchers.IO) { store.title(id) to store.botUiProfile(id) }
        name = saved.first ?: fallback; profile = saved.second; ready = true
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            val image = withContext(Dispatchers.IO) { runCatching { botUiImportAvatar(context, uri) }.getOrNull() }
            if (image != null) profile = profile.copy(image = image) else error = true
            busy = false
        }
    }
    BotUiPage(stringResource(R.string.bot_ui_profile), onClose = { if (!busy) onClose() }, actions = {
        BotUiButton(MikaIcons.Check, stringResource(R.string.save), ready && !busy && name.isNotBlank()) {
            scope.launch {
                busy = true
                val saved = withContext(Dispatchers.IO) { store.saveBotUiProfile(id, name, profile) }
                busy = false
                if (saved) onClose() else error = true
            }
        }
    }) {
        LazyColumn(Modifier.fillMaxWidth().weight(1f), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.bot_ui_name)) },
                    singleLine = true, enabled = ready && !busy, isError = name.isBlank(), modifier = Modifier.fillMaxWidth().testTag("bot_ui_profile_name"))
            }
            item {
                TextButton(onClick = { expanded = !expanded }, enabled = ready && !busy) {
                    BotUiAvatar(profile, Modifier.size(80.dp)); Spacer(Modifier.width(16.dp)); Text(stringResource(R.string.bot_ui_avatar))
                }
            }
            if (expanded) {
                item { Row { FilterChip(!upload, { upload = false }, label = { Text(stringResource(R.string.bot_ui_robot)) }); Spacer(Modifier.width(12.dp)); FilterChip(upload, { upload = true }, label = { Text(stringResource(R.string.bot_ui_upload)) }) } }
                if (upload) item { Button(onClick = { picker.launch("image/*") }, enabled = !busy) { Text(stringResource(R.string.bot_ui_choose_image)) } }
                else {
                    item { Text(stringResource(R.string.bot_ui_style), color = MikaTheme.colors.ink); Row { repeat(3) { style ->
                        FilterChip(profile.image == null && profile.robot == style, { profile = profile.copy(robot = style, image = null) }, enabled = !busy,
                            modifier = Modifier.testTag("bot_ui_robot_$style"), label = { BotUiAvatar(profile.copy(robot = style, image = null), Modifier.size(48.dp)) })
                    } } }
                    item { Text(stringResource(R.string.bot_ui_color), color = MikaTheme.colors.ink); Row { botUiColors.forEachIndexed { index, color ->
                        IconButton(onClick = { profile = profile.copy(color = index, image = null) }, enabled = !busy, modifier = Modifier.weight(1f)) {
                            Box(Modifier.size(30.dp).background(color, CircleShape), contentAlignment = Alignment.Center) {
                                if (profile.color == index) Icon(MikaIcons.Check, stringResource(R.string.bot_ui_selected), tint = Color.White, modifier = Modifier.size(20.dp))
                                else Text("${index + 1}", color = Color.White)
                            }
                        }
                    } } }
                    item { Text(stringResource(R.string.bot_ui_face), color = MikaTheme.colors.ink); Row { repeat(3) { face ->
                        FilterChip(profile.image == null && profile.face == face, { profile = profile.copy(face = face, image = null) }, enabled = !busy,
                            label = { BotUiAvatar(profile.copy(face = face, image = null), Modifier.size(48.dp)) })
                    } } }
                }
            }
            if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            if (error) item { Text(stringResource(R.string.bot_ui_save_error), color = MikaTheme.colors.warn) }
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
    val output = ByteArrayOutputStream()
    check(scaled.compress(Bitmap.CompressFormat.JPEG, 90, output))
    val result = Base64.getEncoder().encodeToString(output.toByteArray())
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
        OutlinedTextField(query, { query = it }, singleLine = true, label = { Text(stringResource(R.string.bot_ui_find)) }, modifier = Modifier.fillMaxWidth().padding(16.dp))
        Text(stringResource(R.string.bot_ui_matches, messages.size), Modifier.padding(horizontal = 16.dp), color = MikaTheme.colors.ink3)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(messages) { text -> androidx.compose.foundation.text.selection.SelectionContainer {
                Text(text, Modifier.fillMaxWidth().background(MikaTheme.colors.surface, RoundedCornerShape(18.dp)).padding(16.dp), color = MikaTheme.colors.ink)
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
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            if (files.isEmpty()) item { Text(stringResource(R.string.bot_ui_no_files), color = MikaTheme.colors.ink3) }
            items(files.distinctBy { it.uri }) { file ->
                TextButton(onClick = { FileViewer.open(context, Uri.parse(file.uri), file.name) }) {
                    Icon(MikaIcons.Doc, null); Spacer(Modifier.width(12.dp)); Text(file.name)
                }
            }
        }
    }
}
