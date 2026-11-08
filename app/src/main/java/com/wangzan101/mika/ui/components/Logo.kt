package com.wangzan101.mika.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.booleanResource
import androidx.compose.ui.unit.Dp
import com.wangzan101.mika.R
import com.wangzan101.mika.ui.theme.MikaTheme

/** Mika 的标志:圆角方块里的图标画。圆角默认按边长的 0.28(36dp 约 10,76dp 约 22)。 */
@Composable
fun MikaLogo(size: Dp, modifier: Modifier = Modifier, corner: Dp = size * 0.28f) {
    Image(
        painterResource(R.drawable.mika_launcher_art), contentDescription = null,
        modifier.size(size).clip(RoundedCornerShape(corner)),
        contentScale = ContentScale.Crop,
        // App appearance can differ from the system drawable-night configuration.
        colorFilter = if (booleanResource(R.bool.brand_monochrome_logo)) {
            ColorFilter.tint(if (MikaTheme.colors.isDark) Color.White else Color(0xFF4D4D4D))
        } else null,
    )
}
