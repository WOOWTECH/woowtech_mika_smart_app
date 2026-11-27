package com.wangzan101.mika.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.wangzan101.mika.R
import com.wangzan101.mika.chat.BotUiProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Base64

internal class BotUiAvatarColor(val nameRes: Int, val color: Color)

/** woowtechbot's eleven bot colours, in the website's order; [BotUiProfile.colorIndex] indexes this list. */
internal val BotUiAvatarColors = listOf(
    BotUiAvatarColor(R.string.bot_ui_color_green, Color(0xFF009957)),
    BotUiAvatarColor(R.string.bot_ui_color_blue, Color(0xFF377FE6)),
    BotUiAvatarColor(R.string.bot_ui_color_red, Color(0xFFD94B52)),
    BotUiAvatarColor(R.string.bot_ui_color_orange, Color(0xFFE78531)),
    BotUiAvatarColor(R.string.bot_ui_color_purple, Color(0xFF8057C8)),
    BotUiAvatarColor(R.string.bot_ui_color_cyan, Color(0xFF0EA5C6)),
    BotUiAvatarColor(R.string.bot_ui_color_pink, Color(0xFFD84F8B)),
    BotUiAvatarColor(R.string.bot_ui_color_yellow, Color(0xFFD8A729)),
    BotUiAvatarColor(R.string.bot_ui_color_teal, Color(0xFF01A492)),
    BotUiAvatarColor(R.string.bot_ui_color_coral, Color(0xFFE5634E)),
    BotUiAvatarColor(R.string.bot_ui_color_silver, Color(0xFFA8ADB4)),
)

/** Orange, yellow and silver are too light for a white robot, so the automatic face is dark there. */
private val DarkInkColors = setOf(3, 7, 10)
private val DarkInk = Color(0xFF111111)

/** The design's robot, drawn in its own 32-unit space exactly as in the preview (24-unit body at translate(5,5) scale(.92)). */
private object RobotPaths {
    private fun parse(d: String): Path = PathParser().parsePathString(d).toPath()
    val classicBody = parse("M10 7h4a7 7 0 0 1 7 7v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-6a7 7 0 0 1 7-7Z")
    val squareEars = parse("M4 9 2 4h2l3 4M20 9l2-5h-2l-3 4")
    val eyes = parse("M6.3 14.6q1.7-3 3.4 0M14.3 14.6q1.7-3 3.4 0")
}

private fun DrawScope.drawRobot(profile: BotUiProfile) {
    val index = profile.colorIndex().coerceIn(0, BotUiAvatarColors.size - 1)
    val tile = BotUiAvatarColors[index].color
    val ink = when (profile.faceMode()) {
        1 -> Color.White
        2 -> DarkInk
        else -> if (index in DarkInkColors) DarkInk else Color.White
    }
    val unit = size.minDimension / 32f
    drawRoundRect(tile, cornerRadius = CornerRadius(8.5f * unit))
    withTransform({
        translate(5f * unit, 5f * unit)
        scale(.92f * unit, .92f * unit, pivot = Offset.Zero)
    }) {
        val eyeLine = Stroke(width = 1.6f)
        when (profile.robot) {
            0 -> {
                drawPath(RobotPaths.classicBody, ink)
                drawRoundRect(ink, Offset(1f, 14f), Size(3f, 5f), CornerRadius(1f))
                drawRoundRect(ink, Offset(20f, 14f), Size(3f, 5f), CornerRadius(1f))
                drawRect(ink, Offset(11f, 4f), Size(2f, 5f))
                drawCircle(ink, 2f, Offset(12f, 4f))
                drawPath(RobotPaths.eyes, tile, style = eyeLine)
            }
            1 -> {
                drawRoundRect(ink, Offset(3f, 7f), Size(18f, 14f), CornerRadius(4f))
                drawPath(RobotPaths.squareEars, ink)
                drawPath(RobotPaths.eyes, tile, style = eyeLine)
                drawRoundRect(tile, Offset(9f, 18f), Size(6f, 1.4f), CornerRadius(.7f))
            }
            else -> {
                drawRoundRect(ink, Offset(3f, 6f), Size(18f, 16f), CornerRadius(8f))
                drawRect(ink, Offset(11f, 3f), Size(2f, 5f))
                drawCircle(ink, 1.5f, Offset(12f, 3f))
                drawPath(RobotPaths.eyes, tile, style = eyeLine)
                drawCircle(tile, 1.2f, Offset(12f, 18f))
            }
        }
    }
}

/** A conversation's identity tile: a coloured rounded square with the design's robot, or the uploaded picture cropped the same way. */
@Composable
internal fun BotUiAvatar(profile: BotUiProfile, modifier: Modifier = Modifier.size(32.dp)) {
    val bitmap by produceState<Bitmap?>(null, profile.image) {
        value = withContext(Dispatchers.Default) { runCatching {
            profile.image?.let { Base64.getDecoder().decode(it) }?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        }.getOrNull() }
    }
    val description = stringResource(R.string.bot_ui_avatar)
    val picture = bitmap
    if (picture != null) Image(picture.asImageBitmap(), description, modifier.clip(RoundedCornerShape(percent = 27)), contentScale = ContentScale.Crop)
    else Canvas(modifier.semantics { contentDescription = description }) { drawRobot(profile) }
}
