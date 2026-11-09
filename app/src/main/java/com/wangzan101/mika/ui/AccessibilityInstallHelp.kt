package com.wangzan101.mika.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.R
import com.wangzan101.mika.ui.components.ButtonKind
import com.wangzan101.mika.ui.components.ButtonSize
import com.wangzan101.mika.ui.components.MikaButton
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.theme.MikaType

/** Guidance only: neither opening Settings nor returning from it implies authorization. */
@Composable
internal fun AccessibilityInstallHelp(onAppInfo: () -> Unit, onAccessibility: () -> Unit) {
    Column(Modifier.padding(16.dp).testTag("accessibility-install-help")) {
        Text(stringResource(R.string.a11y_install_title), style = MikaType.Body, color = MikaTheme.colors.ink)
        Text(stringResource(R.string.a11y_install_steps), style = MikaType.Caption, color = MikaTheme.colors.ink2)
        Text(stringResource(R.string.a11y_install_missing), Modifier.padding(top = 8.dp), style = MikaType.Caption, color = MikaTheme.colors.ink2)
        MikaButton(
            stringResource(R.string.a11y_install_app_info), onAppInfo, Modifier.testTag("setup-app-info"),
            kind = ButtonKind.Tonal, size = ButtonSize.Small,
        )
        MikaButton(
            stringResource(R.string.a11y_install_open), onAccessibility, Modifier.testTag("a11y-install-open"),
            kind = ButtonKind.Text, size = ButtonSize.Small,
        )
    }
}
