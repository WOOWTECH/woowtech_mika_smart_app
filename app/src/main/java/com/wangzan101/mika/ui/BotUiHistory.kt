package com.wangzan101.mika.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wangzan101.mika.R
import com.wangzan101.mika.chat.BotUiProfile
import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.chat.ConversationSummary
import com.wangzan101.mika.chat.DeleteImpact
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.MikaType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.graphics.Color
import com.wangzan101.mika.ui.components.Adaptive
import com.wangzan101.mika.ui.components.windowWidth

internal data class BotUiHistoryRow(val summary: ConversationSummary, val profile: BotUiProfile, val excerpt: String, val searchable: String)

internal fun botUiHistoryRows(store: ConversationStore, summaries: List<ConversationSummary>): List<BotUiHistoryRow> = summaries.map { summary ->
    val turns = store.turns(summary.id)
    val text = turns.flatMap { t -> listOfNotNull(t.userText, t.outcome, t.result, t.note) + t.steers + t.finishedReplies + t.interruptedReplies }
    BotUiHistoryRow(summary, store.botUiProfile(summary.id), text.lastOrNull { it.isNotBlank() }.orEmpty(),
        (listOf(summary.title) + text).joinToString("\n"))
}

internal fun botUiFilterHistory(rows: List<BotUiHistoryRow>, query: String): List<BotUiHistoryRow> =
    rows.filter { query.isBlank() || it.searchable.contains(query.trim(), ignoreCase = true) }

/** True while the inbox is docked beside the chat (wide window): the chat header then hides its inbox button. */
internal val LocalBotUiInboxDocked = staticCompositionLocalOf { false }

/** The local assistant's identity: blue, as in the inbox header and the unsaved new conversation. */
private val LocalAssistantProfile = BotUiProfile(color = 1, palette = 2)

private val InboxRowShape = RoundedCornerShape(24.dp)

/** Full-page alternative owned by ChatWithDrawer. Its content stays composed to retain task/composer state. */
@Composable
internal fun BotUiHistoryHost(
    vm: ChatViewModel,
    conversations: () -> List<ConversationSummary>,
    conversationChanges: Flow<String>,
    onPlans: () -> Unit, onMemory: () -> Unit, onBrowser: () -> Unit,
    onMcpServers: () -> Unit, onComputerAccess: () -> Unit, onScreens: () -> Unit,
    onSettings: () -> Unit, onAbout: () -> Unit, updateAvailable: Boolean,
    onBotServices: () -> Unit, onBotNotifications: () -> Unit, onBotAddService: () -> Unit = onBotServices, onBotFiles: (() -> Unit)?,
    reopen: Boolean, onReopened: () -> Unit, externalOpenRevision: Int,
    content: @Composable (() -> Unit) -> Unit,
) {
    val context = LocalContext.current
    val store = vm.botUiStore
    val prefs = remember(context) { context.applicationContext.getSharedPreferences("chat_draft", android.content.Context.MODE_PRIVATE) }
    val ui by vm.ui.collectAsState()
    val others by vm.otherRunning.collectAsState()
    val deleted by vm.deleted.collectAsState()
    var open by rememberSaveable { mutableStateOf(true) }
    var query by rememberSaveable { mutableStateOf("") }
    var revision by remember { mutableIntStateOf(0) }
    var handledRevision by rememberSaveable { mutableIntStateOf(externalOpenRevision) }
    LaunchedEffect(conversationChanges) { conversationChanges.collect { revision++ } }
    LaunchedEffect(store) { store.deletions.collect { botUiForgetDraft(prefs, it) } }
    LaunchedEffect(reopen) { if (reopen) { open = true; onReopened() } }
    LaunchedEffect(externalOpenRevision) {
        if (handledRevision != externalOpenRevision) { open = false; handledRevision = externalOpenRevision }
    }
    // WOOWTECH fork (owner 2026-11-28): from Adaptive.DockMin wide the inbox stays docked at the left, the same page as
    // on a phone, with the chat beside it. Narrowing (portrait, split screen) goes back to the full-page inbox; coming
    // from docked it shows the chat, not the inbox.
    val docked = Adaptive.docked(windowWidth())
    var wasDocked by rememberSaveable { mutableStateOf(docked) }
    LaunchedEffect(docked) { if (wasDocked && !docked) open = false; wasDocked = docked }
    val rows by produceState<List<BotUiHistoryRow>?>(null, open || docked, revision) {
        if (open || docked) {
            val pending = vm.botUiPendingDraftIds()
            val newTitle = context.getString(R.string.chat_new)
            value = withContext(Dispatchers.IO) {
                val saved = conversations()
                val drafts = prefs.all.keys.filter { it.startsWith("bot_ui_seen_") }.mapNotNull { key ->
                    val id = key.removePrefix("bot_ui_seen_")
                    val text = prefs.getString("bot_ui_text_$id", "").orEmpty()
                    val name = store.title(id)
                    if (saved.any { it.id == id } || (text.isBlank() && name == null && id !in pending)) null
                    else ConversationSummary(id, name ?: text.lineSequence().firstOrNull { it.isNotBlank() }?.take(80) ?: newTitle, prefs.getLong(key, 0L))
                }
                botUiHistoryRows(store, saved + drafts).map { row ->
                    val draft = prefs.getString("bot_ui_text_${row.summary.id}", "").orEmpty()
                    if (row.excerpt.isEmpty() && draft.isNotBlank()) row.copy(excerpt = draft, searchable = row.searchable + "\n" + draft) else row
                }
            }
        }
    }
    val listState = rememberLazyListState()
    var editing by remember { mutableStateOf<BotUiHistoryRow?>(null) }
    var confirming by remember { mutableStateOf<Pair<BotUiHistoryRow, DeleteImpact>?>(null) }
    var shortcuts by remember { mutableStateOf(false) }
    var accountMenu by remember { mutableStateOf(false) }
    var newMenu by remember { mutableStateOf(false) }
    var showFiles by remember { mutableStateOf(false) }
    fun leave(action: () -> Unit) { open = false; action() }
    // Only tools this app really has; settings and About sit under the top-left control instead.
    @Composable fun toolEntries(onDismiss: () -> Unit) {
        @Composable fun entry(icon: ImageVector, label: String, go: () -> Unit) {
            BotUiPopoverItem(icon, label, onClick = { onDismiss(); leave(go) })
        }
        entry(MikaIcons.Clock, stringResource(R.string.drawer_plans), onPlans)
        entry(MikaIcons.Heart, stringResource(R.string.memory_and_skills), onMemory)
        entry(MikaIcons.Link, stringResource(R.string.mcp_servers_title), onMcpServers)
        entry(MikaIcons.Desktop, stringResource(R.string.mcp_title), onComputerAccess)
        entry(MikaIcons.Globe, stringResource(R.string.drawer_browser), onBrowser)
        entry(MikaIcons.Screens, stringResource(R.string.drawer_screens), onScreens)
        entry(MikaIcons.Doc, stringResource(R.string.bot_ui_files)) {
            if (onBotFiles != null) onBotFiles() else { open = true; showFiles = true }
        }
    }
    LaunchedEffect(open) {
        if (!open) { accountMenu = false; newMenu = false; shortcuts = false }
    }
    val c = MikaTheme.colors
    // The website's list page, named 收件匣 like it (owner 2026-11-28); the same page on phones, tablets and iOS.
    @Composable
    fun inbox(modifier: Modifier) {
        Column(modifier.background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding().testTag("bot_ui_history")) {
            // Top row: 40 dp round buttons, 16 dp from the left edge with 12 dp between, 22 dp between the right two and 8 dp
            // from the right edge, as on the website (each circle sits in a 48 dp target, hence the smaller paddings).
            Row(Modifier.fillMaxWidth().height(64.dp).padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box {
                        BotUiRoundButton(MikaIcons.Gear, stringResource(R.string.settings_title)) { accountMenu = !accountMenu }
                        BotUiPopover(accountMenu, { accountMenu = false }, PopoverPlacement.BelowStart, minWidth = 220.dp) {
                            BotUiPopoverItem(MikaIcons.Gear, stringResource(R.string.settings_title), onClick = { accountMenu = false; leave(onSettings) })
                            BotUiPopoverDivider()
                            BotUiPopoverItem(MikaIcons.Info, AboutCopy.TITLE + if (updateAvailable) " •" else "", onClick = { accountMenu = false; leave(onAbout) })
                        }
                    }
                    BotUiRoundButton(MikaIcons.WorkspaceSwitch, stringResource(R.string.bot_ui_services)) { onBotServices() }
                }
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    BotUiRoundButton(MikaIcons.Bell, stringResource(R.string.bot_ui_notifications)) { onBotNotifications() }
                    Box {
                        BotUiRoundButton(MikaIcons.Plus, stringResource(R.string.chat_new)) { newMenu = !newMenu }
                        BotUiPopover(newMenu, { newMenu = false }, PopoverPlacement.BelowEnd, minWidth = 220.dp) {
                            BotUiPopoverItem(MikaIcons.New, stringResource(R.string.chat_new), enabled = vm.canSwitch(),
                                onClick = { newMenu = false; vm.newConversation(); open = false })
                            BotUiPopoverDivider()
                            BotUiPopoverItem(MikaIcons.Link, stringResource(R.string.bot_services_add), onClick = { newMenu = false; onBotAddService() })
                        }
                    }
                }
            }
            // The website's 收件匣 row: a 36 dp circle with the tray, then the 17 sp title. Back to the chat only when the
            // chat is not already beside it.
            Row(Modifier.fillMaxWidth().height(48.dp).padding(start = 20.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(c.fill), contentAlignment = Alignment.Center) {
                    Icon(MikaIcons.Inbox, null, Modifier.size(18.dp), tint = c.ink2)
                }
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.bot_ui_history), Modifier.weight(1f).semantics { heading() }, color = c.ink,
                    fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold)
                if (!docked) Row(Modifier.clip(RoundedCornerShape(12.dp)).clickable { open = false }.padding(horizontal = 4.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.bot_ui_back), color = c.ink3, fontSize = 12.sp, lineHeight = 16.sp)
                    Icon(MikaIcons.Chevron, null, Modifier.size(13.dp), tint = c.ink3)
                }
            }
            if (!vm.canSwitch()) Text(stringResource(R.string.drawer_busy), Modifier.padding(horizontal = 16.dp), color = c.ink3, style = MikaType.Hint)
            val visible = remember(rows, query, deleted, others, ui.conversationId, ui.composer) {
                botUiFilterHistory(rows.orEmpty().filter { it.summary.id !in deleted }, query).sortedWith(
                    compareByDescending<BotUiHistoryRow> { it.summary.id in others || (it.summary.id == ui.conversationId && ui.composer != ComposerMode.Idle) }
                        .thenByDescending { it.summary.pinnedAt ?: Long.MIN_VALUE }
                        .thenByDescending { it.summary.updatedAt })
            }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState,
                contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // The assistant's own header, like the website's bot header; it scrolls with the list and hides while searching.
                if (query.isBlank()) item("hero") {
                    Column(Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        BotUiAvatar(LocalAssistantProfile, Modifier.size(80.dp))
                        Text(stringResource(R.string.app_name), color = c.ink, fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.bot_ui_local_assistant), color = c.ink2, fontSize = 13.sp, lineHeight = 16.sp)
                    }
                }
                if (rows == null) item { Text(stringResource(R.string.bot_ui_loading), Modifier.padding(horizontal = 12.dp), color = c.ink3) }
                else if (visible.isEmpty() && query.isNotBlank()) item { Text(stringResource(R.string.bot_ui_no_results), Modifier.padding(horizontal = 12.dp), color = c.ink3) }
                // Fresh running conversations need an entry even before their first completed turn is persisted.
                if (ui.conversationId != null && rows.orEmpty().none { it.summary.id == ui.conversationId } && query.isBlank()) item("current") {
                    // The running conversation before its first save: the same row as the saved ones, shown selected, with
                    // nothing to rename, pin or delete yet (no ⋯).
                    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(InboxRowShape).background(c.fill).clickable { open = false }
                        .padding(start = 7.dp, top = 6.dp, bottom = 6.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        BotUiAvatar(LocalAssistantProfile, Modifier.size(38.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(ChatCopy.title(ui.exchanges).ifBlank { context.getString(R.string.chat_new) }, color = c.ink,
                                fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (ui.exchanges.isEmpty()) Text(stringResource(R.string.bot_ui_new_chat_hint, stringResource(R.string.app_name)),
                                color = c.ink2, fontSize = 13.sp, lineHeight = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                items(visible, key = { it.summary.id }) { row ->
                    var menu by remember { mutableStateOf(false) }
                    val selected = row.summary.id == ui.conversationId
                    val enabled = selected || vm.canSwitch()
                    val running = row.summary.id in others || (selected && ui.composer != ComposerMode.Idle)
                    // The website's thread row: 64 dp, 38 dp identity, 15 sp title with the time beside it, a 13 sp excerpt,
                    // the quiet ⋯ at the top right; only the selected row has a background.
                    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(InboxRowShape).background(if (selected) c.fill else Color.Transparent)
                        .clickable(enabled = enabled) {
                            if (!selected) { if (running) vm.switchTo(row.summary.id) else vm.openConversation(row.summary.id) }
                            open = false
                        }.padding(start = 7.dp, top = 6.dp, bottom = 6.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        BotUiAvatar(row.profile, Modifier.size(38.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                if (row.summary.pinnedAt != null) Icon(MikaIcons.Pin, stringResource(R.string.drawer_pinned), Modifier.size(14.dp), tint = c.ink3)
                                if (row.summary.branchOf != null) Icon(MikaIcons.Route, stringResource(R.string.chat_branch_origin), Modifier.size(14.dp), tint = c.ink3)
                                Text(ChatCopy.plainTitle(row.summary.title), modifier = Modifier.weight(1f), color = if (enabled) c.ink else c.ink3,
                                    fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(conversationTime(row.summary.updatedAt, System.currentTimeMillis()), color = c.ink3, fontSize = 12.sp,
                                    lineHeight = 17.sp, maxLines = 1, style = TextStyle(fontFeatureSettings = "tnum"))
                            }
                            Text(if (running) stringResource(R.string.drawer_running) else row.excerpt, color = if (running) c.accent else c.ink2,
                                fontSize = 13.sp, lineHeight = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            row.summary.page?.host?.let { Text(it, style = MikaType.Hint, color = c.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                        Box(Modifier.align(Alignment.Top)) {
                            // `···` as a quiet 18 dp glyph in secondary ink, inside a 40 dp target, at the row's top right.
                            Box(Modifier.size(40.dp).clip(CircleShape).clickable(role = Role.Button) { menu = !menu }, contentAlignment = Alignment.Center) {
                                Icon(MikaIcons.More, stringResource(R.string.drawer_actions), Modifier.size(18.dp), tint = c.ink2)
                            }
                            BotUiPopover(menu, { menu = false }, PopoverPlacement.BelowEnd, minWidth = 200.dp) {
                                BotUiPopoverItem(MikaIcons.Edit, stringResource(R.string.bot_ui_profile), onClick = { menu = false; editing = row })
                                BotUiPopoverItem(MikaIcons.Pin, stringResource(if (row.summary.pinnedAt == null) R.string.pin else R.string.unpin),
                                    onClick = { menu = false; vm.setPinned(row.summary.id, row.summary.pinnedAt == null) })
                                BotUiPopoverDivider()
                                BotUiPopoverItem(MikaIcons.Trash, stringResource(R.string.confirm_delete), destructive = true,
                                    onClick = { menu = false; confirming = row to vm.deleteImpact(row.summary.id) })
                            }
                        }
                    }
                }
            }
            // The website's phone bar: a 44 dp tools circle and the 44 dp search field, 12 dp from the edges, 8 dp apart.
            Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 12.dp, top = 4.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box {
                    BotUiRoundButton(MikaIcons.Apps, stringResource(R.string.bot_ui_shortcuts), diameter = 44.dp) { shortcuts = !shortcuts }
                    BotUiPopover(shortcuts, { shortcuts = false }, PopoverPlacement.AboveStart, minWidth = 240.dp) {
                        toolEntries { shortcuts = false }
                    }
                }
                BotUiSearchPill(query, { query = it }, stringResource(R.string.bot_ui_search_history), Modifier.weight(1f), testTag = "bot_ui_history_search")
            }
        }
    }
    if (docked) {
        BackHandler { context.findActivity()?.moveTaskToBack(true) }
        Row(Modifier.fillMaxSize()) {
            inbox(Modifier.width(Adaptive.DockWidth).fillMaxHeight())
            Box(Modifier.width(1.dp).fillMaxHeight().background(c.hair))
            Box(Modifier.weight(1f).fillMaxHeight()) {
                CompositionLocalProvider(LocalBotUiInboxDocked provides true) { content { } }
            }
        }
    } else {
        BackHandler { if (open) context.findActivity()?.moveTaskToBack(true) else open = true }
        Box(Modifier.fillMaxSize()) {
            Box(if (open) Modifier.fillMaxSize().clearAndSetSemantics {} else Modifier.fillMaxSize()) { content { open = true } }
            if (open) {
                inbox(Modifier.fillMaxSize())
                // Last registered handler wins over the still-composed chat's message/PIP handlers.
                BackHandler { context.findActivity()?.moveTaskToBack(true) }
            }
        }
    }
    editing?.let { row -> BotUiProfileEditor(store, row.summary.id, row.summary.title) { editing = null } }
    confirming?.let { (row, impact) -> DeleteConversationDialog(row.summary.title, impact,
        onConfirm = { confirming = null; botUiForgetDraft(prefs, row.summary.id); vm.deleteConversation(row.summary.id) }, onDismiss = { confirming = null }) }
    if (showFiles) BotUiFiles(ui.exchanges.flatMap { it.files }) { showFiles = false }
}
