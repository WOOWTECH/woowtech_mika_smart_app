package com.wangzan101.mika.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wangzan101.mika.R
import com.wangzan101.mika.chat.BotUiProfile
import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 36 dp control button with a hairline ring (`.profile-top .icon-button`). */
@Composable
internal fun BotUiCircleButton(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    val c = MikaTheme.colors
    Box(
        Modifier.size(36.dp).clip(CircleShape).background(c.control).border(1.dp, c.hair, CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = c.ink.copy(alpha = if (enabled) 1f else .4f))
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
    val c = MikaTheme.colors
    Column(Modifier.fillMaxWidth().background(c.bg).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            BotUiRoundButton(MikaIcons.Back, stringResource(R.string.bot_ui_history), onClick = onHistory)
            // `.conversation-title`: a 40 dp pill on the control colour that hugs its content and sits in the middle,
            // 24 dp identity tile, 14 sp / 600 name.
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Row(Modifier.height(40.dp).clip(CircleShape).background(c.control)
                    .clickable { editing = vm.botUiConversationId() }.padding(start = 8.dp, end = 14.dp)
                    .testTag("bot_ui_name_capsule"), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    BotUiAvatar(identity.second, Modifier.size(24.dp))
                    Text(identity.first, Modifier.weight(1f, fill = false), color = c.ink, fontSize = 14.sp, lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Box {
                BotUiRoundButton(MikaIcons.More, stringResource(R.string.bot_ui_more)) { menu = true }
                BotUiPopover(menu, { menu = false }, PopoverPlacement.BelowEnd) {
                    BotUiPopoverItem(MikaIcons.Edit, stringResource(R.string.bot_ui_profile), { menu = false; editing = vm.botUiConversationId() })
                    BotUiPopoverItem(MikaIcons.New, stringResource(R.string.chat_new), { menu = false; vm.newConversation() }, enabled = vm.canSwitch())
                    BotUiPopoverItem(MikaIcons.Search, stringResource(R.string.bot_ui_find), { menu = false; finding = true })
                    BotUiPopoverItem(MikaIcons.Doc, stringResource(R.string.bot_ui_files), { menu = false; files = true })
                }
            }
        }
        subtitle?.let { Text(it, Modifier.padding(start = 60.dp, end = 16.dp, bottom = 6.dp), color = c.ink3, fontSize = 12.sp, lineHeight = 17.sp) }
    }
    editing?.let { id -> BotUiProfileEditor(store, id, identity.first) { editing = null } }
    if (finding) BotUiFind(ui.exchanges) { finding = false }
    if (files) BotUiFiles(ui.exchanges.flatMap { it.files }) { files = false }
}

/**
 * Conversation name and icon, laid out like the design's `avatarPage`: no title, save and close as round buttons at the top
 * right, the 120 dp bubble helmet with a pencil badge, the name centred below it, and the icon card opening under them. Only the
 * name and the icon (the helmet or an uploaded picture) can change.
 */
@Composable
internal fun BotUiProfileEditor(store: ConversationStore, id: String, fallback: String, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable(id) { mutableStateOf(fallback) }
    var profile by remember(id) { mutableStateOf(BotUiProfile(color = 1, palette = 2)) }
    var ready by remember(id) { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    var open by rememberSaveable { mutableStateOf(false) }
    var upload by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(id) {
        val saved = withContext(Dispatchers.IO) { runCatching { store.title(id) to store.botUiProfile(id) } }
        saved.onSuccess { (title, icon) -> name = title ?: fallback; profile = icon.upgraded(); upload = icon.image != null; ready = true }
            .onFailure { error = true }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            val image = withContext(Dispatchers.IO) { runCatching { botUiImportAvatar(context, uri) }.getOrNull() }
            if (image != null) profile = profile.copy(image = image) else error = true
            busy = false
        }
    }
    val c = MikaTheme.colors
    val nameFocus = remember { FocusRequester() }
    var nameFocused by remember { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    val editable = ready && !busy
    Dialog(onDismissRequest = { if (!busy) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        NoDialogDim()
        Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End)) {
                BotUiCircleButton(MikaIcons.Check, stringResource(R.string.save), editable && name.isNotBlank()) {
                    scope.launch {
                        busy = true
                        val saved = withContext(Dispatchers.IO) { store.saveBotUiProfile(id, name, profile.upgraded()) }
                        busy = false
                        if (saved) onClose() else error = true
                    }
                }
                BotUiCircleButton(MikaIcons.Close, stringResource(R.string.bot_ui_close)) { if (!busy) onClose() }
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(start = 12.dp, end = 12.dp, top = 18.dp, bottom = 30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                // `.avatar-large`: the 120 dp bubble helmet (spec: at least 120), with a 23 dp pencil badge 4 dp outside its corner.
                Box(Modifier.size(120.dp).testTag("bot_ui_avatar_button").selectable(selected = open, enabled = editable, role = Role.Button) { open = !open }
                    .semantics { contentDescription = context.getString(R.string.bot_ui_edit_icon) }) {
                    BotUiAvatar(profile, Modifier.fillMaxSize())
                    Box(Modifier.align(Alignment.BottomEnd).offset(x = 4.dp, y = 4.dp).size(23.dp).clip(CircleShape)
                        .background(c.bg).padding(2.dp).clip(CircleShape).background(c.control), contentAlignment = Alignment.Center) {
                        Icon(MikaIcons.Edit, null, Modifier.size(13.dp), tint = c.ink2)
                    }
                }
                Spacer(Modifier.height(18.dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    // Same width as the pencil on the other side, so the name sits in the middle of the page.
                    Spacer(Modifier.width(32.dp))
                    // `.profile-name-row input`: 18 sp / 600 centred, 10 dp radius, accent ring while editing.
                    BasicTextField(
                        name, { name = it.take(60) }, singleLine = true, enabled = editable,
                        textStyle = TextStyle(color = c.ink, fontSize = 18.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                        cursorBrush = SolidColor(c.accent),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                            .border(1.dp, if (nameFocused) c.accent else Color.Transparent, RoundedCornerShape(10.dp))
                            .padding(8.dp).focusRequester(nameFocus).onFocusChanged { nameFocused = it.isFocused }
                            .testTag("bot_ui_profile_name").semantics { contentDescription = context.getString(R.string.bot_ui_name) },
                    )
                    Box(Modifier.size(width = 32.dp, height = 36.dp).clip(RoundedCornerShape(8.dp))
                        .clickable(enabled = editable, role = Role.Button) { nameFocus.requestFocus(); keyboard?.show() }
                        .semantics { contentDescription = context.getString(R.string.bot_ui_edit_name) }, contentAlignment = Alignment.Center) {
                        Icon(MikaIcons.Edit, null, Modifier.size(18.dp), tint = c.ink2)
                    }
                }
                if (name.isBlank()) Text(stringResource(R.string.bot_ui_name_required), color = c.bad, fontSize = 12.sp, lineHeight = 17.sp)
                Spacer(Modifier.height(24.dp))
                AnimatedVisibility(open, enter = fadeIn(tween(160)) + expandVertically(tween(200)), exit = fadeOut(tween(120)) + shrinkVertically(tween(160))) {
                    // `.avatar-card`: control colour, 1 px hairline, 24 dp corners.
                    val cardShape = RoundedCornerShape(24.dp)
                    Column(Modifier.fillMaxWidth().clip(cardShape).background(c.control).border(1.dp, c.hair, cardShape)) {
                        Row(Modifier.fillMaxWidth().padding(9.dp).selectableGroup(), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            listOf(false to R.string.bot_ui_robot, true to R.string.bot_ui_upload).forEach { (isUpload, label) ->
                                Text(stringResource(label), Modifier.heightIn(min = 36.dp).clip(RoundedCornerShape(13.dp))
                                    .background(if (upload == isUpload) c.raisedHover else Color.Transparent)
                                    .selectable(selected = upload == isUpload, enabled = editable, role = Role.Tab) { upload = isUpload }
                                    .padding(horizontal = 12.dp, vertical = 8.dp),
                                    color = if (upload == isUpload) c.ink else c.ink2, fontSize = 14.sp, lineHeight = 20.sp)
                            }
                            Spacer(Modifier.weight(1f))
                            Text(stringResource(R.string.bot_ui_reset), Modifier.clip(RoundedCornerShape(10.dp))
                                .clickable(enabled = editable, role = Role.Button) { profile = BotUiProfile(color = 1, palette = 2); upload = false }
                                .padding(horizontal = 12.dp, vertical = 8.dp), color = c.ink2, fontSize = 12.sp, lineHeight = 16.sp)
                        }
                        Box(Modifier.fillMaxWidth().height(1.dp).background(c.edge))
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 20.dp)) {
                            if (upload) {
                                // `.avatar-upload`: dashed 16 dp frame with the camera, the action and the formats line.
                                val dash = c.hair
                                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                                    .drawBehind {
                                        drawRoundRect(dash, cornerRadius = CornerRadius(16.dp.toPx()),
                                            style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))))
                                    }
                                    .clickable(enabled = editable, role = Role.Button) { picker.launch("image/*") }
                                    .padding(horizontal = 8.dp, vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Icon(MikaIcons.Camera, null, Modifier.size(32.dp), tint = c.ink2)
                                    Text(stringResource(R.string.bot_ui_choose_image), color = c.ink, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
                                    Text(stringResource(R.string.bot_ui_upload_formats), color = c.ink2, fontSize = 11.sp, lineHeight = 15.sp, textAlign = TextAlign.Center)
                                }
                                Spacer(Modifier.height(10.dp))
                                Text(stringResource(R.string.bot_ui_crop_hint), Modifier.fillMaxWidth(), color = c.ink2, fontSize = 11.sp, lineHeight = 15.sp, textAlign = TextAlign.Center)
                            } else {
                                BotUiHelmetPane(profile, editable) { profile = it }
                            }
                        }
                    }
                }
                if (busy) LinearProgressIndicator(Modifier.padding(top = 16.dp).fillMaxWidth())
                if (error) Text(stringResource(R.string.bot_ui_save_error), Modifier.padding(top = 16.dp), color = c.warn, fontSize = 13.sp, lineHeight = 18.sp)
            }
        }
    }
}

/** A part of the helmet editor: 13 sp / 500 in the secondary ink, a heading for screen readers. */
@Composable
private fun HelmetPartLabel(text: Int, modifier: Modifier = Modifier) {
    Text(stringResource(text), modifier.semantics { heading() }, color = MikaTheme.colors.ink2, fontSize = 13.sp, lineHeight = 18.sp,
        fontWeight = FontWeight.Medium)
}

/**
 * Owner 11/28, the website's editor for the bubble helmet: ten outlines five by two, twelve colours, the face in white, black or
 * matching the body, and ten expressions. Every outline, colour and expression is a button of at least 48 dp; choosing one
 * replaces an uploaded picture, as choosing a colour always did.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BotUiHelmetPane(profile: BotUiProfile, editable: Boolean, onChange: (BotUiProfile) -> Unit) {
    val c = MikaTheme.colors
    val noPhoto = profile.image == null
    Column(Modifier.fillMaxWidth()) {
        HelmetPartLabel(R.string.bot_ui_outline)
        Spacer(Modifier.height(10.dp))
        // 6 dp gaps keep each tile 48 dp wide down to a 320 dp screen.
        Column(Modifier.fillMaxWidth().selectableGroup(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            BotUiHelmetOutlines.indices.chunked(5).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { shape ->
                        val picked = noPhoto && profile.shape == shape
                        val label = stringResource(BotUiHelmetOutlines[shape].nameRes)
                        val tileShape = RoundedCornerShape(16.dp)
                        Box(Modifier.weight(1f).heightIn(min = 60.dp).clip(tileShape).background(if (picked) c.raisedHover else Color.Transparent)
                            .border(2.dp, if (picked) c.ink2 else Color.Transparent, tileShape)
                            .selectable(selected = picked, enabled = editable, role = Role.Button) { onChange(profile.copy(shape = shape, image = null)) }
                            .semantics { contentDescription = label }.testTag("bot_ui_shape_$shape"), contentAlignment = Alignment.Center) {
                            // The current colour, face and expression in this outline.
                            BotUiHelmet(profile.copy(shape = shape), Modifier.size(44.dp))
                        }
                    }
                }
            }
        }
        // The 48 dp buttons leave 10 dp around each dot and 6 dp around each chip, so the gaps below the labels are smaller.
        HelmetPartLabel(R.string.bot_ui_color, Modifier.padding(top = 22.dp, bottom = 2.dp))
        FlowRow(Modifier.fillMaxWidth().selectableGroup(), horizontalArrangement = Arrangement.Center, maxItemsInEachRow = 6) {
            BotUiAvatarColors.forEachIndexed { index, entry ->
                val picked = noPhoto && profile.color == index
                val ring = c.ink
                val label = stringResource(entry.nameRes)
                // A 27 dp dot in a 48 dp button, the ring 5 dp outside it while picked. Every dot has a hairline edge, so pearl white
                // still shows on the light card.
                Box(Modifier.size(48.dp).clip(CircleShape)
                    .selectable(selected = picked, enabled = editable, role = Role.Button) { onChange(profile.copy(color = index, image = null)) }
                    .semantics { contentDescription = label }.testTag("bot_ui_color_$index"), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(27.dp)
                        .drawBehind { if (picked) drawCircle(ring, radius = size.minDimension / 2f + 5.dp.toPx(), style = Stroke(2.dp.toPx())) }
                        .clip(CircleShape).background(entry.color).border(Dp.Hairline, c.hair, CircleShape))
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            HelmetPartLabel(R.string.bot_ui_face, Modifier.weight(1f))
            val auto = noPhoto && profile.face == 0
            Box(Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp))
                .selectable(selected = auto, enabled = editable, role = Role.RadioButton) { onChange(profile.copy(face = 0, image = null)) }
                .padding(horizontal = 6.dp).testTag("bot_ui_face_auto"), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.bot_ui_face_auto), color = if (auto) c.accent else c.ink2, fontSize = 13.sp, lineHeight = 18.sp,
                    fontWeight = if (auto) FontWeight.SemiBold else FontWeight.Normal)
            }
        }
        Row(Modifier.fillMaxWidth().clip(CircleShape).background(c.raisedHover).padding(4.dp).selectableGroup()) {
            listOf(1 to R.string.bot_ui_face_white, 2 to R.string.bot_ui_face_black).forEach { (face, label) ->
                val picked = noPhoto && profile.face == face
                Text(stringResource(label), Modifier.weight(1f).clip(CircleShape).background(if (picked) c.bg else Color.Transparent)
                    .selectable(selected = picked, enabled = editable, role = Role.RadioButton) { onChange(profile.copy(face = face, image = null)) }
                    .padding(9.dp), color = if (picked) c.ink else c.ink2, fontSize = 14.sp, lineHeight = 20.sp, textAlign = TextAlign.Center)
            }
        }
        HelmetPartLabel(R.string.bot_ui_expression, Modifier.padding(top = 22.dp, bottom = 4.dp))
        FlowRow(Modifier.fillMaxWidth().selectableGroup(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BotUiHelmetExpressions.forEachIndexed { expression, entry ->
                val picked = noPhoto && profile.expression == expression
                val label = stringResource(entry.nameRes)
                val press = remember { MutableInteractionSource() }
                // A 36 dp chip in a 48 dp button: the button takes the touch, the chip shows the press.
                Box(Modifier.heightIn(min = 48.dp).widthIn(min = 48.dp)
                    .selectable(selected = picked, interactionSource = press, indication = null, enabled = editable, role = Role.Button) {
                        onChange(profile.copy(expression = expression, image = null))
                    }
                    .semantics { contentDescription = label }.testTag("bot_ui_expression_$expression"), contentAlignment = Alignment.Center) {
                    Box(Modifier.heightIn(min = 36.dp).clip(CircleShape).background(c.raisedHover)
                        .border(1.5.dp, if (picked) c.ink else Color.Transparent, CircleShape).indication(press, LocalIndication.current)
                        .padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                        Text(label, color = c.ink, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = if (picked) FontWeight.SemiBold else FontWeight.Normal)
                    }
                }
            }
        }
    }
}
