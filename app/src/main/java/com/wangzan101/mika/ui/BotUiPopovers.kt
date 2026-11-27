package com.wangzan101.mika.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.menuRadius
import kotlinx.coroutines.delay

/**
 * woowtechbot's popover menus, measured from the production website: no scrim, anchored to the button that opened them
 * (the four-grid menu opens upwards from its left edge, the account menu downwards from its left edge, the plus menu
 * downwards from its right edge, 8 dp away), padding 6 / row gap 4, a 1 px hairline at 50 %, radius `--radius-menu`,
 * and the 0.2 s `pop-in` motion: opacity 0 to 1, scale .96 to 1 and a 6 px rise on cubic-bezier(.22, 1, .36, 1).
 */
internal enum class PopoverPlacement(val origin: TransformOrigin) {
    AboveStart(TransformOrigin(0f, 1f)),
    BelowStart(TransformOrigin(0f, 0f)),
    BelowEnd(TransformOrigin(1f, 0f)),
}

private val PopEasing = CubicBezierEasing(.22f, 1f, .36f, 1f)
private const val PopMs = 200
/** Transparent room around the surface inside the popup window so its shadow is not clipped. */
private val ShadowRoom = 20.dp

private class PopoverPosition(
    val placement: PopoverPlacement, val room: Int, val gap: Int, val margin: Int,
) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize,
    ): IntOffset {
        val w = popupContentSize.width - 2 * room
        val h = popupContentSize.height - 2 * room
        // "Start" is the left edge in left-to-right layouts and the right edge in right-to-left ones (Arabic ships).
        val alignLeft = (placement != PopoverPlacement.BelowEnd) == (layoutDirection == LayoutDirection.Ltr)
        val left = (if (alignLeft) anchorBounds.left else anchorBounds.right - w)
            .coerceIn(margin, (windowSize.width - w - margin).coerceAtLeast(margin))
        val top = when (placement) {
            PopoverPlacement.AboveStart -> anchorBounds.top - gap - h
            else -> anchorBounds.bottom + gap
        }.coerceIn(margin, (windowSize.height - h - margin).coerceAtLeast(margin))
        return IntOffset(left - room, top - room)
    }
}

/**
 * Place next to the trigger inside the same Box. Outside taps and Back dismiss it; the exit motion plays before the
 * window is removed. [expanded] is the only state: the host decides when it opens.
 */
@Composable
internal fun BotUiPopover(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    placement: PopoverPlacement,
    modifier: Modifier = Modifier,
    minWidth: Dp = 200.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val visible = remember { MutableTransitionState(false) }
    // Closing is immediate; opening is started from inside the popup window once that window is on screen (below).
    if (!expanded) visible.targetState = false
    if (!expanded && !visible.currentState && !visible.targetState) return
    val c = MikaTheme.colors
    val density = LocalDensity.current
    val provider = remember(placement, density) {
        with(density) { PopoverPosition(placement, ShadowRoom.roundToPx(), 8.dp.roundToPx(), 8.dp.roundToPx()) }
    }
    val rise = with(density) { 6.dp.roundToPx() }
    val reduce = MikaTheme.reduceMotion
    val origin = if (LocalLayoutDirection.current == LayoutDirection.Rtl) {
        TransformOrigin(1f - placement.origin.pivotFractionX, placement.origin.pivotFractionY)
    } else placement.origin
    val enter = if (reduce) EnterTransition.None else fadeIn(tween(PopMs, easing = PopEasing)) +
        scaleIn(tween(PopMs, easing = PopEasing), initialScale = .96f, transformOrigin = origin) +
        slideInVertically(tween(PopMs, easing = PopEasing)) { rise }
    val exit = if (reduce) ExitTransition.None else fadeOut(tween(PopMs, easing = PopEasing)) +
        scaleOut(tween(PopMs, easing = PopEasing), targetScale = .96f, transformOrigin = origin) +
        slideOutVertically(tween(PopMs, easing = PopEasing)) { rise }
    val shape = RoundedCornerShape(c.menuRadius.dp)
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp
    // clippingEnabled = false: the transparent shadow room around the surface may reach past the screen edge instead of
    // the system sliding the whole window inwards, which moved the menu off its anchor.
    Popup(popupPositionProvider = provider, onDismissRequest = onDismissRequest,
        properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        // A new window can take a few hundred milliseconds to appear (a debug build on a modest phone measured 300 ms), which
        // used to swallow the whole 0.2 s `pop-in`. The entrance starts when this window has focus, i.e. is on screen, and
        // after 350 ms regardless, so a window that never reports focus still shows.
        val windowFocused = LocalWindowInfo.current.isWindowFocused
        LaunchedEffect(expanded, windowFocused) {
            if (expanded) {
                if (!windowFocused) delay(350)
                visible.targetState = true
            }
        }
        AnimatedVisibility(visibleState = visible, enter = enter, exit = exit) {
            Box(Modifier.padding(ShadowRoom)) {
                Column(
                    modifier
                        .shadow(
                            elevation = 12.dp, shape = shape, clip = false,
                            ambientColor = Color.Black.copy(alpha = if (c.isDark) .5f else .1f),
                            spotColor = Color.Black.copy(alpha = if (c.isDark) .7f else .16f),
                        )
                        .clip(shape).background(c.menu).border(1.dp, c.hair.copy(alpha = .5f), shape)
                        .widthIn(min = minWidth, max = (screenWidth - 24.dp).coerceAtMost(320.dp))
                        .width(IntrinsicSize.Max)
                        .padding(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    content = content,
                )
            }
        }
    }
}

/** One row: 30 dp minimum, 14/18 text, 16 dp icon first, 8 dp gap, 6 dp corners (`.ui-menu-row`). */
@Composable
internal fun BotUiPopoverItem(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    destructive: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    val c = MikaTheme.colors
    val alpha = if (enabled) 1f else .6f
    Row(
        modifier.fillMaxWidth().heightIn(min = 30.dp).clip(RoundedCornerShape(6.dp))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp),
            tint = (if (destructive) c.bad else c.ink2).copy(alpha = alpha))
        Text(label, Modifier.weight(1f, fill = false), color = (if (destructive) c.bad else c.ink).copy(alpha = alpha),
            fontSize = 14.sp, lineHeight = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        trailing?.invoke()
    }
}

/** 1 px, 6 dp in from each side, hairline at 50 % (the website's `mx-1.5 h-px bg-hairline/50`). */
@Composable
internal fun BotUiPopoverDivider() {
    Box(Modifier.padding(horizontal = 6.dp).fillMaxWidth().height(1.dp).background(MikaTheme.colors.hair.copy(alpha = .5f)))
}
