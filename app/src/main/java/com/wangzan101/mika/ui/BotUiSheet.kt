package com.wangzan101.mika.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogWindowProvider
import kotlinx.coroutines.delay
import com.wangzan101.mika.R
import com.wangzan101.mika.ui.theme.LocalMikaColors
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.WoowSheetDarkColors
import com.wangzan101.mika.ui.theme.WoowSheetLightColors
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.platform.LocalConfiguration
import com.wangzan101.mika.ui.components.Adaptive
import com.wangzan101.mika.ui.components.windowWidth

private val SheetEasing = CubicBezierEasing(.22f, 1f, .36f, 1f)

/**
 * The website's settings sheet (measured from its production capture at 390 css px): starts 12 dp below the status bar,
 * 16 dp top corners, a 32 x 4 grabber 8 dp from the top, a 44 dp header with a centred 16 sp title and the close button,
 * cards on the settings palette. Motion: the scrim fades in over 0.2 s and the panel runs `sheet-in` (0.26 s, opacity plus a
 * 32 px rise, cubic-bezier(.22, 1, .36, 1)). Tapping the scrim, Back, the close button or dragging the header down dismisses;
 * [onDismissRequest] fires after the exit motion, so hosts can simply finish or hide.
 */
@Composable
internal fun BotUiSheet(
    title: String,
    onDismissRequest: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = if (MikaTheme.colors.isDark) WoowSheetDarkColors else WoowSheetLightColors
    val visible = remember { MutableTransitionState(false) }
    var closing by remember { mutableStateOf(false) }
    val dismiss = { if (!closing) { closing = true; visible.targetState = false } }
    // The hosting activity or dialog window can take a few hundred milliseconds to appear (700 ms measured for the services
    // sheet on a debug build), and `sheet-in` ran unseen meanwhile. Start it when the window has focus, or after 400 ms anyway.
    val windowFocused = LocalWindowInfo.current.isWindowFocused
    LaunchedEffect(windowFocused) {
        if (!windowFocused) delay(400)
        if (!closing) visible.targetState = true
    }
    LaunchedEffect(closing, visible.currentState) { if (closing && !visible.currentState) onDismissRequest() }
    BackHandler(onBack = dismiss)
    val reduce = MikaTheme.reduceMotion
    val rise = with(LocalDensity.current) { 32.dp.roundToPx() }
    // WOOWTECH fork: on a tablet-wide window the sheet is a centred window 580 dp wide, like an iPad form sheet
    // (owner 2026-11-28); it keeps its header and close button, without the grabber or the drag-down gesture.
    val wide = Adaptive.sheetWindow(windowWidth())
    val windowHeight = LocalConfiguration.current.screenHeightDp.dp
    val shape = if (wide) RoundedCornerShape(16.dp) else RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
    CompositionLocalProvider(LocalMikaColors provides colors) {
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(
                visibleState = visible,
                enter = if (reduce) EnterTransition.None else fadeIn(tween(200)),
                exit = if (reduce) ExitTransition.None else fadeOut(tween(200)),
            ) {
                // `.glass-scrim`: #0000008c on Midnight, #0000002e on Daylight.
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (colors.isDark) .55f else .18f))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = dismiss))
            }
            AnimatedVisibility(
                visibleState = visible,
                modifier = Modifier.align(if (wide) Alignment.Center else Alignment.BottomCenter),
                enter = if (reduce) EnterTransition.None else fadeIn(tween(260, easing = SheetEasing)) +
                    slideInVertically(tween(260, easing = SheetEasing)) { rise },
                exit = if (reduce) ExitTransition.None else fadeOut(tween(200, easing = SheetEasing)) +
                    slideOutVertically(tween(200, easing = SheetEasing)) { rise },
            ) {
                Column(
                    (if (wide) Modifier.width(Adaptive.SheetWindow).heightIn(max = windowHeight * .86f)
                    else Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).padding(top = 12.dp))
                        .clip(shape).background(colors.bg).border(1.dp, colors.ink.copy(alpha = .12f), shape)
                        // Taps on the panel must not reach the scrim behind it.
                        .pointerInput(Unit) { detectTapGestures { } },
                ) {
                    var drag by remember { mutableFloatStateOf(0f) }
                    Column(
                        Modifier.fillMaxWidth().pointerInput(wide) {
                            if (wide) return@pointerInput
                            detectVerticalDragGestures(onDragEnd = { drag = 0f }, onDragCancel = { drag = 0f }) { _, dy ->
                                drag += dy
                                if (drag > 140f) { drag = 0f; dismiss() }
                            }
                        },
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        if (wide) Spacer(Modifier.height(8.dp))
                        else Box(Modifier.padding(top = 8.dp).size(width = 32.dp, height = 4.dp).clip(RoundedCornerShape(2.dp))
                            .background(colors.ink.copy(alpha = .15f)))
                        Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(44.dp))
                            Text(title, Modifier.weight(1f).semantics { heading() }, color = colors.ink, fontSize = 16.sp,
                                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Box(Modifier.size(44.dp).clip(CircleShape).clickable(role = Role.Button, onClick = dismiss), contentAlignment = Alignment.Center) {
                                Icon(MikaIcons.Close, stringResource(R.string.bot_ui_close), Modifier.size(18.dp), tint = colors.ink)
                            }
                        }
                    }
                    Column(
                        Modifier.weight(1f, fill = !wide).fillMaxWidth().verticalScroll(rememberScrollState())
                            .padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 24.dp)
                            .then(if (wide) Modifier else Modifier.navigationBarsPadding()).imePadding(),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        content = content,
                    )
                }
            }
        }
    }
}

/** `px-2 pb-1 pt-2 text-[12px] font-medium text-ink-secondary`. */
@Composable
internal fun BotUiSectionLabel(text: String) {
    Text(text, Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 4.dp), color = MikaTheme.colors.ink2,
        fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium)
}

/** Settings card: 12 dp corners on the card colour with the 0.5 px settings edge, rows separated by a 9 % ink line. */
@Composable
internal fun BotUiCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(modifier.fillMaxWidth().clip(shape).background(MikaTheme.colors.surface).border(0.5.dp, MikaTheme.colors.edge, shape), content = content)
}

@Composable
internal fun BotUiCardDivider() {
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(1.dp).background(MikaTheme.colors.edge))
}

/** Title 15 sp, optional 13 sp secondary line, optional leading icon and trailing control; the whole row is the target. */
@Composable
internal fun BotUiSettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val c = MikaTheme.colors
    Row(
        modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick) else Modifier)
            .alpha(if (enabled) 1f else .5f).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) Icon(icon, null, Modifier.size(20.dp), tint = if (destructive) c.bad else c.ink2)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = if (destructive) c.bad else c.ink, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
            if (subtitle != null) Text(subtitle, color = c.ink2, fontSize = 13.sp, lineHeight = 18.sp)
        }
        trailing?.invoke()
    }
}

/** The settings switch: 32 x 20 track, 16 dp knob 2 dp in, 0.15 s slide; on = ink track with a page-coloured knob. */
@Composable
internal fun BotUiSwitch(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val c = MikaTheme.colors
    val knob by animateDpAsState(if (checked) 14.dp else 2.dp, tween(150), label = "switch-knob")
    Box(
        modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).alpha(if (enabled) 1f else .5f)
            .toggleable(value = checked, enabled = enabled && onCheckedChange != null, role = Role.Switch,
                onValueChange = { onCheckedChange?.invoke(it) }),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(width = 32.dp, height = 20.dp).clip(CircleShape)
                .background(if (checked) c.ink else c.ink.copy(alpha = .22f))
                .then(if (checked) Modifier else Modifier.border(1.dp, c.ink.copy(alpha = if (c.isDark) .4f else .5f), CircleShape)),
        ) {
            Box(Modifier.offset(x = knob, y = 2.dp).size(16.dp).shadow(1.dp, CircleShape)
                .background(if (checked) c.bg else Color.White, CircleShape))
        }
    }
}

/** `.ui-button`: 40 dp pill. Primary = ink fill with page-coloured text; otherwise a 5 % ink fill. */
@Composable
internal fun BotUiPillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    primary: Boolean = false,
    enabled: Boolean = true,
    fill: Boolean = true,
) {
    val c = MikaTheme.colors
    val fg = if (primary) c.bg else c.ink
    Row(
        modifier.then(if (fill) Modifier.fillMaxWidth() else Modifier).height(40.dp).alpha(if (enabled) 1f else .5f).clip(CircleShape)
            .background(if (primary) c.ink else c.ink.copy(alpha = .05f))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) { Icon(icon, null, Modifier.size(16.dp), tint = fg); Box(Modifier.size(8.dp)) }
        Text(text, color = fg, fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** `.field`: a 13 sp label over a 16 sp input on the inset colour with a hairline and 9 dp corners. */
@Composable
internal fun BotUiTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    val c = MikaTheme.colors
    var focused by remember { mutableStateOf(false) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(label, color = c.ink2, fontSize = 13.sp, lineHeight = 18.sp)
        BasicTextField(
            value, onValueChange, singleLine = true,
            textStyle = TextStyle(color = c.ink, fontSize = 16.sp, lineHeight = 22.sp),
            cursorBrush = SolidColor(c.accent),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }.semantics { contentDescription = label }
                .clip(RoundedCornerShape(9.dp)).background(c.inset)
                .border(1.dp, if (focused) c.accent else c.hair, RoundedCornerShape(9.dp))
                .padding(horizontal = 12.dp, vertical = 11.dp),
        )
    }
}

/** The website's search dock: a 44 dp pill on the card colour with a hairline; focus draws a 2 dp accent ring. */
@Composable
internal fun BotUiSearchPill(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    testTag: String? = null,
) {
    val c = MikaTheme.colors
    var focused by remember { mutableStateOf(false) }
    Row(
        modifier.height(44.dp).clip(CircleShape).background(c.surface)
            .border(if (focused) 2.dp else 1.dp, if (focused) c.accent else c.hair, CircleShape).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(MikaIcons.Search, null, Modifier.size(20.dp), tint = c.ink2)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (query.isEmpty()) Text(placeholder, color = c.ink2, fontSize = 15.sp, lineHeight = 22.sp, maxLines = 1)
            BasicTextField(query, onQueryChange,
                Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }.then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
                singleLine = true, textStyle = TextStyle(color = c.ink, fontSize = 15.sp, lineHeight = 22.sp), cursorBrush = SolidColor(c.accent))
        }
        if (query.isNotEmpty()) Box(Modifier.size(28.dp).clip(CircleShape).clickable { onQueryChange("") }, contentAlignment = Alignment.Center) {
            Icon(MikaIcons.Close, stringResource(R.string.bot_ui_close), Modifier.size(16.dp), tint = c.ink2)
        }
    }
}

/**
 * Full-screen dialogs (name and icon, find, files, the service sheets) paint their own page or scrim, so the dialog window
 * must not dim what is behind it: the default dim left a darker band under the status bar.
 */
@Composable
internal fun NoDialogDim() {
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
    SideEffect { window?.setDimAmount(0f) }
}
