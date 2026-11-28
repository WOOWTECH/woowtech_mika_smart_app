package com.wangzan101.mika.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * WOOWTECH fork: large-screen layout, the same rules as the iPad app (owner 2026-11-28; iOS parity Q23 and k8, and the
 * tablet decisions agreed with the iOS line). Only the window width counts, never the device: a tablet in split screen
 * narrower than [ContentMax] lays out exactly like a phone.
 */
object Adaptive {
    /** Reading content (chat, inbox list, settings pages) is at most this wide and centred; top bars stay full width. */
    val ContentMax = 720.dp

    /** Dialogs are centred and at most this wide. */
    val DialogMax = 420.dp

    /** From [SheetWindowMin] up, sheets become a centred window this wide (the iPad's form sheet measures 580 pt). */
    val SheetWindow = 580.dp
    val SheetWindowMin = 600.dp

    /**
     * From this window width up the inbox stays docked beside the chat. Every iPad in landscape is at least 1133 pt wide
     * and the 12.9/13-inch iPad Pro is 1024/1032 pt in portrait; Android tablets are about 800–930 dp in portrait.
     */
    val DockMin = 1100.dp
    val DockWidth = 360.dp

    /** Side padding that keeps a full-width list's content at most [ContentMax] wide and centred, never less than [base]. */
    fun side(available: Dp, base: Dp): Dp = maxOf(base, (available - ContentMax) / 2)

    fun docked(window: Dp): Boolean = window >= DockMin

    fun sheetWindow(window: Dp): Boolean = window >= SheetWindowMin
}

/** The window's width (Configuration.screenWidthDp is the app window, so split screen counts, not the display). */
@Composable
@ReadOnlyComposable
fun windowWidth(): Dp = LocalConfiguration.current.screenWidthDp.dp

/** Full width, with the content inside at most [Adaptive.ContentMax] wide and centred (for a column inside a full-width scroll). */
fun Modifier.contentColumn(): Modifier =
    fillMaxWidth().wrapContentWidth(Alignment.CenterHorizontally).widthIn(max = Adaptive.ContentMax)
