package com.wangzan101.mika.ui

import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.about.MikaLinks
import com.wangzan101.mika.ui.components.GroupCard
import com.wangzan101.mika.ui.components.ListRow
import com.wangzan101.mika.ui.components.PageScaffold
import com.wangzan101.mika.ui.components.RowChevron
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.MikaType

/** 关于页上点开的底部面板。 */
private enum class AboutSheet { Feedback, Diagnostics }

/**
 * Play editions (BuildConfig.PLAY_EDITION: woowtech, apporoplay flavors): no GitHub entries (source code, guide,
 * GitHub issue). The repo documents the direct-download APK, which is not distributed through Google Play. The
 * licenses page stays.
 */
private val SHOW_GITHUB = !BuildConfig.PLAY_EDITION

/**
 * 关于 Mika:顶上图标、名字、一句话介绍、版本(Beta 标记、构建编号);下面是
 * 反馈问题、开源仓库与使用说明;一段数据说明;最底下许可证与作者。
 * 外部链接都交给 [onOpenUrl](系统浏览器)。
 * [diagnostics] 写出诊断信息(反馈面板里「复制诊断信息」点开预览时在后台线程调)。
 */
@Composable
fun AboutScreen(
    versionName: String,
    build: String,
    beta: Boolean,
    issueUrl: String,
    onOpenUrl: (String) -> Unit,
    onOpenLicense: () -> Unit,
    onBack: () -> Unit,
    diagnostics: () -> String = { "" },
) {
    val c = MikaTheme.colors
    var sheet by rememberSaveable { mutableStateOf<AboutSheet?>(null) }
    PageScaffold(AboutCopy.TITLE, onBack) {
        Hero(versionName, build, beta)

        GroupCard {
            ListRow(MikaIcons.Bug, AboutCopy.FEEDBACK, AboutCopy.FEEDBACK_SUB, first = true, onClick = { sheet = AboutSheet.Feedback }) { RowChevron() }
        }
        if (SHOW_GITHUB) GroupCard {
            ListRow(MikaIcons.Code, AboutCopy.REPO, AboutCopy.REPO_SUB, first = true, onClick = { onOpenUrl(MikaLinks.REPO) }) { ExternalMark() }
            ListRow(MikaIcons.Book, AboutCopy.GUIDE, AboutCopy.GUIDE_SUB, onClick = { onOpenUrl(MikaLinks.README) }) { ExternalMark() }
        }

        Row(
            Modifier.fillMaxWidth().padding(top = 2.dp).background(c.okSoft, RoundedCornerShape(14.dp)).padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(MikaIcons.Shield, null, Modifier.padding(top = 1.dp).size(18.dp), tint = c.ok)
            Text(AboutCopy.DATA_NOTE, style = MikaType.Caption, color = c.ink2)
        }

        Column(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                buildAnnotatedString {
                    val (before, after) = stringResource(R.string.about_released_under).split("%1\$s").let { it[0] to it.getOrElse(1) { "" } }
                    append(before)
                    withStyle(SpanStyle(color = c.accent)) { append(AboutCopy.LICENSE_LINK) }
                    append(after)
                },
                Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onOpenLicense).padding(horizontal = 6.dp, vertical = 2.dp)
                    .testTag("about-license"),
                style = MikaType.Hint, color = c.ink3, textAlign = TextAlign.Center,
            )
            Text(AboutCopy.AUTHOR, Modifier.padding(top = 2.dp), style = MikaType.Hint, color = c.ink3)
        }
    }

    val close = { sheet = null }
    when (sheet) {
        AboutSheet.Feedback -> FeedbackSheet(
            onGitHub = if (SHOW_GITHUB) ({ close(); onOpenUrl(issueUrl) }) else null,
            onDiagnostics = { sheet = AboutSheet.Diagnostics },
            onDismiss = close,
        )
        AboutSheet.Diagnostics -> DiagnosticsSheet(diagnostics, onDismiss = close)
        null -> Unit
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun Hero(versionName: String, build: String, beta: Boolean) {
    val c = MikaTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            painterResource(R.drawable.mika_launcher_art), contentDescription = null,
            Modifier.size(72.dp).clip(RoundedCornerShape(20.dp)),
        )
        Text(stringResource(R.string.app_name), Modifier.padding(top = 12.dp), style = MikaType.Title, fontWeight = FontWeight.Bold, color = c.ink)
        Text(AboutCopy.TAGLINE, Modifier.padding(top = 4.dp), style = MikaType.Caption, color = c.ink2, textAlign = TextAlign.Center)
        FlowRow(
            Modifier.fillMaxWidth().padding(top = 10.dp).testTag("about-version"),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(AboutCopy.version(versionName), style = MikaType.Hint, color = c.ink3, textAlign = TextAlign.Center)
            if (beta) {
                Text(
                    AboutCopy.BETA, Modifier.background(c.accentSoft, RoundedCornerShape(7.dp)).padding(horizontal = 7.dp, vertical = 1.dp),
                    style = MikaType.Hint, fontWeight = FontWeight.SemiBold, color = c.accent, maxLines = 1, softWrap = false,
                )
            }
            Text("· ${AboutCopy.buildLabel(build)}", style = MikaType.Hint, color = c.ink3)
        }
    }
}

@Composable
private fun ExternalMark() {
    Icon(MikaIcons.External, null, Modifier.size(15.dp), tint = MikaTheme.colors.ink3)
}

// ---------- 底部面板 ----------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AboutSheetFrame(title: String, sub: String?, tag: String, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val c = MikaTheme.colors
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = c.surface,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
    ) {
        // 面板内容太高(矮屏、大字号)时整体能滚,底下的按钮总够得着
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp).testTag(tag),
        ) {
            Text(title, style = MikaType.Title, color = c.ink)
            sub?.let { Text(it, Modifier.padding(top = 2.dp), style = MikaType.Caption, color = c.ink3) }
            content()
        }
    }
}

/** WOOWTECH fork: without [onGitHub] (Play edition) the sheet only offers copying diagnostics. */
@Composable
private fun FeedbackSheet(onGitHub: (() -> Unit)?, onDiagnostics: () -> Unit, onDismiss: () -> Unit) {
    AboutSheetFrame(AboutCopy.FEEDBACK, AboutCopy.FEEDBACK_SHEET_SUB, "feedback-sheet", onDismiss) {
        Column(Modifier.padding(top = 6.dp)) {
            onGitHub?.let { FeedbackOption(MikaIcons.Code, AboutCopy.FEEDBACK_GITHUB, AboutCopy.FEEDBACK_GITHUB_SUB, first = true, it) }
            FeedbackOption(MikaIcons.Copy, AboutCopy.DIAGNOSTICS, AboutCopy.DIAGNOSTICS_SUB, first = onGitHub == null, onDiagnostics)
        }
    }
}

@Composable
private fun FeedbackOption(icon: ImageVector, title: String, sub: String, first: Boolean, onClick: () -> Unit) {
    Box(Modifier.testTag("feedback-option")) {
        ListRow(icon, title, sub, first = first, onClick = onClick)
    }
}
