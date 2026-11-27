package com.wangzan101.mika.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogProperties
import com.wangzan101.mika.R
import com.wangzan101.mika.ui.MarkdownText
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.menuRadius
import com.wangzan101.mika.ui.theme.MikaType

/**
 * App 内统一弹窗：保留调用方的内容、动作和测试标识，只统一容器、正文层级与操作区。
 * 操作仍由调用方提供；这里只给它们一致的浅色底、圆角和排布，不把确认逻辑收进组件。
 */
@Composable
fun MikaDialog(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null,
    confirmButton: @Composable () -> Unit = {},
    dismissButton: (@Composable () -> Unit)? = null,
    properties: DialogProperties = DialogProperties(),
) {
    val c = MikaTheme.colors
    // Direct WOOWTECH dialogs sit on the website's popover surface; their two buttons are 6 % / 10 % ink pills on it.
    val direct = com.wangzan101.mika.BuildConfig.WOOWTECHBOT_ENABLED
    AlertDialog(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        title = title?.let { content ->
            {
                CompositionLocalProvider(
                    LocalContentColor provides c.ink,
                    LocalTextStyle provides MikaType.Title.copy(fontSize = 20.sp, lineHeight = 26.sp),
                ) { content() }
            }
        },
        text = text?.let { content ->
            {
                CompositionLocalProvider(
                    LocalContentColor provides c.ink2,
                    LocalTextStyle provides MikaType.Body.copy(fontSize = 14.5.sp, lineHeight = 23.sp),
                ) { content() }
            }
        },
        confirmButton = {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (dismissButton != null) {
                    DialogAction(Modifier.weight(1f), if (direct) c.ink.copy(alpha = .06f) else c.fill, direct) { dismissButton() }
                }
                DialogAction(Modifier.weight(1f), if (direct) c.ink.copy(alpha = .1f) else c.accentSoft, direct) { confirmButton() }
            }
        },
        shape = RoundedCornerShape(if (direct) c.menuRadius.dp else 26.dp),
        containerColor = c.menu,
        titleContentColor = c.ink,
        textContentColor = c.ink2,
        tonalElevation = 0.dp,
        properties = properties,
    )
}

@Composable
private fun DialogAction(modifier: Modifier, background: Color, inkLabels: Boolean = false, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier.heightIn(min = 44.dp).background(background, shape).clip(shape),
        contentAlignment = Alignment.Center,
    ) {
        // The website's dialog buttons read in ink; destructive ones keep their own error colour. Text buttons take their
        // label colour from the scheme's primary, so only this button is given a scheme whose primary is the ink colour.
        if (inkLabels) MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(primary = MikaTheme.colors.ink)) { content() }
        else content()
    }
}

/** 通知型弹窗的正文和回答使用同一套 Markdown 排版，不把原始标记直接交给用户。 */
@Composable
fun MikaNoticeDialog(
    message: String,
    onDismiss: () -> Unit,
    title: String? = null,
    confirmText: String = stringResource(R.string.ok_got_it),
) {
    MikaDialog(
        onDismissRequest = onDismiss,
        title = title?.let { { Text(it) } },
        text = { MarkdownText(message, MikaType.Body.copy(color = MikaTheme.colors.ink2)) },
        confirmButton = { TextButton(onDismiss) { Text(confirmText) } },
    )
}
