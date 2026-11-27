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

internal data class BotUiHistoryRow(val summary: ConversationSummary, val profile: BotUiProfile, val excerpt: String, val searchable: String)

internal fun botUiHistoryRows(store: ConversationStore, summaries: List<ConversationSummary>): List<BotUiHistoryRow> = summaries.map { summary ->
    val turns = store.turns(summary.id)
    val text = turns.flatMap { t -> listOfNotNull(t.userText, t.outcome, t.result, t.note) + t.steers + t.finishedReplies + t.interruptedReplies }
    BotUiHistoryRow(summary, store.botUiProfile(summary.id), text.lastOrNull { it.isNotBlank() }.orEmpty(),
        (listOf(summary.title) + text).joinToString("\n"))
}

internal fun botUiFilterHistory(rows: List<BotUiHistoryRow>, query: String): List<BotUiHistoryRow> =
    rows.filter { query.isBlank() || it.searchable.contains(query.trim(), ignoreCase = true) }

/** Full-page alternative owned by ChatWithDrawer. Its content stays composed to retain task/composer state. */
@Composable
internal fun BotUiHistoryHost(
    vm: ChatViewModel,
    conversations: () -> List<ConversationSummary>,
    conversationChanges: Flow<String>,
    onPlans: () -> Unit, onMemory: () -> Unit, onBrowser: () -> Unit,
    onMcpServers: () -> Unit, onComputerAccess: () -> Unit, onScreens: () -> Unit,
    onSettings: () -> Unit, onAbout: () -> Unit,
    onBotFiles: (() -> Unit)? = null,
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
    val rows by produceState<List<BotUiHistoryRow>?>(null, open, revision) {
        if (open) {
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
    BackHandler { if (open) context.findActivity()?.moveTaskToBack(true) else open = true }
    Box(Modifier.fillMaxSize()) {
        Box(if (open) Modifier.fillMaxSize().clearAndSetSemantics {} else Modifier.fillMaxSize()) { content { open = true } }
        if (open) {
            val c = MikaTheme.colors
            Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding().testTag("bot_ui_history")) {
                Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        BotUiRoundButton(MikaIcons.Gear, stringResource(R.string.settings_title)) { accountMenu = !accountMenu }
                        BotUiPopover(accountMenu, { accountMenu = false }, PopoverPlacement.BelowStart, minWidth = 220.dp) {
                            BotUiPopoverItem(MikaIcons.Gear, stringResource(R.string.settings_title), onClick = { accountMenu = false; leave(onSettings) })
                            BotUiPopoverDivider()
                            BotUiPopoverItem(MikaIcons.Info, AboutCopy.TITLE, onClick = { accountMenu = false; leave(onAbout) })
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    Box {
                        BotUiRoundButton(MikaIcons.Plus, stringResource(R.string.chat_new)) { newMenu = !newMenu }
                        BotUiPopover(newMenu, { newMenu = false }, PopoverPlacement.BelowEnd, minWidth = 220.dp) {
                            BotUiPopoverItem(MikaIcons.New, stringResource(R.string.chat_new), enabled = vm.canSwitch(),
                                onClick = { newMenu = false; vm.newConversation(); open = false })
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.bot_ui_history), Modifier.weight(1f), color = c.ink, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
                    Row(Modifier.clip(RoundedCornerShape(12.dp)).clickable { open = false }.padding(horizontal = 8.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.bot_ui_back), color = c.ink3, fontSize = 11.sp, lineHeight = 15.sp)
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
                LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
                    if (rows == null) item { Text(stringResource(R.string.bot_ui_loading), color = c.ink3) }
                    else if (visible.isEmpty()) item { Text(stringResource(R.string.bot_ui_no_results), color = c.ink3) }
                    // Fresh running conversations need an entry even before their first completed turn is persisted.
                    if (ui.conversationId != null && rows.orEmpty().none { it.summary.id == ui.conversationId } && query.isBlank()) item("current") {
                        // The running conversation before its first save: the same row as the saved ones, shown as the selected one.
                        Row(Modifier.fillMaxWidth().background(c.fill, RoundedCornerShape(24.dp)).clickable { open = false }.padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BotUiAvatar(BotUiProfile(color = 1, palette = 2), Modifier.size(40.dp))
                            Text(ChatCopy.title(ui.exchanges).ifBlank { context.getString(R.string.chat_new) }, Modifier.weight(1f), color = c.ink,
                                fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    items(visible, key = { it.summary.id }) { row ->
                        var menu by remember { mutableStateOf(false) }
                        val selected = row.summary.id == ui.conversationId
                        val enabled = selected || vm.canSwitch()
                        val running = row.summary.id in others || (selected && ui.composer != ComposerMode.Idle)
                        Row(Modifier.fillMaxWidth().background(if (selected) c.fill else c.bg, RoundedCornerShape(24.dp))
                            .clickable(enabled = enabled) {
                                if (!selected) { if (running) vm.switchTo(row.summary.id) else vm.openConversation(row.summary.id) }
                                open = false
                            }.padding(start = 10.dp, top = 10.dp, bottom = 10.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BotUiAvatar(row.profile, Modifier.size(40.dp))
                            Column(Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    if (row.summary.pinnedAt != null) Icon(MikaIcons.Pin, stringResource(R.string.drawer_pinned), Modifier.size(14.dp), tint = c.ink3)
                                    if (row.summary.branchOf != null) Icon(MikaIcons.Route, stringResource(R.string.chat_branch_origin), Modifier.size(14.dp), tint = c.ink3)
                                    Text(ChatCopy.plainTitle(row.summary.title), modifier = Modifier.weight(1f), color = if (enabled) c.ink else c.ink3, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(conversationTime(row.summary.updatedAt, System.currentTimeMillis()), color = c.ink2, fontSize = 12.sp, lineHeight = 17.sp, maxLines = 1)
                                }
                                Text(if (running) stringResource(R.string.drawer_running) else row.excerpt, color = if (running) c.accent else c.ink2, fontSize = 13.sp, lineHeight = 22.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                row.summary.page?.host?.let { Text(it, style = MikaType.Hint, color = c.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                            }
                            Box {
                                // `···` as a quiet 18 dp glyph in secondary ink, inside a 40 dp target.
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
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        BotUiRoundButton(MikaIcons.Apps, stringResource(R.string.bot_ui_shortcuts)) { shortcuts = !shortcuts }
                        BotUiPopover(shortcuts, { shortcuts = false }, PopoverPlacement.AboveStart, minWidth = 240.dp) {
                            toolEntries { shortcuts = false }
                        }
                    }
                    BotUiSearchPill(query, { query = it }, stringResource(R.string.bot_ui_search_history), Modifier.weight(1f), testTag = "bot_ui_history_search")
                }
            }
            // Last registered handler wins over the still-composed chat's message/PIP handlers.
            BackHandler { context.findActivity()?.moveTaskToBack(true) }
        }
    }
    editing?.let { row -> BotUiProfileEditor(store, row.summary.id, row.summary.title) { editing = null } }
    confirming?.let { (row, impact) -> DeleteConversationDialog(row.summary.title, impact,
        onConfirm = { confirming = null; botUiForgetDraft(prefs, row.summary.id); vm.deleteConversation(row.summary.id) }, onDismiss = { confirming = null }) }
    if (showFiles) BotUiFiles(ui.exchanges.flatMap { it.files }) { showFiles = false }
}
