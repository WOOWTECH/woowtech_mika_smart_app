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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
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
import kotlin.math.pow

internal class BotUiAvatarColor(val nameRes: Int, val argb: Long) {
    val color: Color get() = Color(argb)
}

/** woowtechbot's eleven bot colours in the website's order, then its pearl white; [BotUiProfile.colorIndex] indexes this list. */
internal val BotUiAvatarColors = listOf(
    BotUiAvatarColor(R.string.bot_ui_color_green, 0xFF009957),
    BotUiAvatarColor(R.string.bot_ui_color_blue, 0xFF377FE6),
    BotUiAvatarColor(R.string.bot_ui_color_red, 0xFFD94B52),
    BotUiAvatarColor(R.string.bot_ui_color_orange, 0xFFE78531),
    BotUiAvatarColor(R.string.bot_ui_color_purple, 0xFF8057C8),
    BotUiAvatarColor(R.string.bot_ui_color_cyan, 0xFF0EA5C6),
    BotUiAvatarColor(R.string.bot_ui_color_pink, 0xFFD84F8B),
    BotUiAvatarColor(R.string.bot_ui_color_yellow, 0xFFD8A729),
    BotUiAvatarColor(R.string.bot_ui_color_teal, 0xFF01A492),
    BotUiAvatarColor(R.string.bot_ui_color_coral, 0xFFE5634E),
    BotUiAvatarColor(R.string.bot_ui_color_silver, 0xFFA8ADB4),
    BotUiAvatarColor(R.string.bot_ui_color_pearl, 0xFFE6E8EC),
)

internal fun botUiAvatarColor(profile: BotUiProfile): BotUiAvatarColor =
    BotUiAvatarColors[profile.colorIndex().coerceIn(0, BotUiAvatarColors.lastIndex)]

private const val WHITE_INK = 0xFFFFFFFF
private const val DARK_INK = 0xFF111111

/** The face colour: white or #111111 as chosen; matching the body, dark on a light colour (relative luminance above 0.4). */
internal fun botUiInk(profile: BotUiProfile): Long = when (profile.faceMode()) {
    1 -> WHITE_INK
    2 -> DARK_INK
    else -> if (botUiLuminance(botUiAvatarColor(profile).argb) > .4) DARK_INK else WHITE_INK
}

/** Relative luminance of an sRGB colour, linearised as the reference component's `ink()` does. */
internal fun botUiLuminance(argb: Long): Double {
    fun linear(shift: Int): Double {
        val c = ((argb shr shift) and 0xFF) / 255.0
        return if (c <= .03928) c / 12.92 else ((c + .055) / 1.055).pow(2.4)
    }
    return .2126 * linear(16) + .7152 * linear(8) + .0722 * linear(0)
}

/** One of the bubble's outlines (the website's ten body shapes), as an SVG path in the 64-unit box. */
internal class BotUiHelmetOutline(val nameRes: Int, val path: String)

/** The website editor's order, top row then bottom row; [BotUiProfile.shape] indexes this list. */
internal val BotUiHelmetOutlines = listOf(
    BotUiHelmetOutline(R.string.bot_ui_outline_rounded_square, "M22 7h20a16 16 0 0 1 16 16v22a16 16 0 0 1 -16 16h-20a16 16 0 0 1 -16 -16v-22a16 16 0 0 1 16 -16z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_cloud, "M32.00 9.50A9.05 9.05 0 0 1 47.75 15.23A9.05 9.05 0 0 1 56.13 29.75A9.05 9.05 0 0 1 53.22 46.25A9.05 9.05 0 0 1 40.38 57.02A9.05 9.05 0 0 1 23.62 57.02A9.05 9.05 0 0 1 10.78 46.25A9.05 9.05 0 0 1 7.87 29.75A9.05 9.05 0 0 1 16.25 15.23A9.05 9.05 0 0 1 32.00 9.50Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_circle, "M5 34a27 27 0 1 0 54 0a27 27 0 1 0 -54 0Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_wide_rounded, "M21 11h22a18 18 0 0 1 18 18v11a18 18 0 0 1 -18 18h-22a18 18 0 0 1 -18 -18v-11a18 18 0 0 1 18 -18z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_egg, "M8 34a24 28 0 1 0 48 0a24 28 0 1 0 -48 0Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_drop, "M32 4C40 15 56 26 56 40A24 22 0 0 1 8 40C8 26 24 15 32 4Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_shield, "M32 5L55 12.5V33C55 47 45.5 56.5 32 62C18.5 56.5 9 47 9 33V12.5Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_hexagon, "M61.50 34.00L46.75 59.55L17.25 59.55L2.50 34.00L17.25 8.45L46.75 8.45Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_diamond, "M32 4L61 34L32 64L3 34Z"),
    BotUiHelmetOutline(R.string.bot_ui_outline_star, "M32.00 3.50L42.75 15.38L58.41 18.75L53.50 34.00L58.41 49.25L42.75 52.62L32.00 64.50L21.25 52.62L5.59 49.25L10.50 34.00L5.59 18.75L21.25 15.38Z"),
)

/** The white highlight on the bubble, top left. */
internal const val HELMET_HIGHLIGHT = "M19 23a18 18 0 0 1 10-7.5"

/** One mark of an expression, from the reference component's SVG: in the face colour, or outside the face in the helmet's. */
internal sealed interface BotUiHelmetMark {
    class Dot(val x: Float, val y: Float, val r: Float, val onFace: Boolean = true) : BotUiHelmetMark
    class Ring(val x: Float, val y: Float, val r: Float, val width: Float) : BotUiHelmetMark
    class Oval(val x: Float, val y: Float, val rx: Float, val ry: Float) : BotUiHelmetMark
    class Bar(val x: Float, val y: Float, val w: Float, val h: Float, val r: Float) : BotUiHelmetMark
    /** A stroke with round caps. */
    class Line(val path: String, val width: Float, val onFace: Boolean = true) : BotUiHelmetMark
    class Fill(val path: String, val onFace: Boolean = true) : BotUiHelmetMark
}

internal class BotUiHelmetExpression(val nameRes: Int, val marks: List<BotUiHelmetMark>)

/** The website's ten expressions, in its order; [BotUiProfile.expression] indexes this list. */
internal val BotUiHelmetExpressions = listOf(
    BotUiHelmetExpression(R.string.bot_ui_expression_idle, listOf(
        BotUiHelmetMark.Dot(26f, 34f, 3.2f), BotUiHelmetMark.Dot(38f, 34f, 3.2f), BotUiHelmetMark.Line("M29 40q3 2.4 6 0", 2f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_happy, listOf(
        BotUiHelmetMark.Line("M22.8 35.5q3.2-4 6.4 0M34.8 35.5q3.2-4 6.4 0", 2.4f), BotUiHelmetMark.Line("M27.5 39.5q4.5 4 9 0", 2.2f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_curious, listOf(
        BotUiHelmetMark.Dot(26f, 33.5f, 4f), BotUiHelmetMark.Dot(38f, 34f, 2.8f), BotUiHelmetMark.Ring(32f, 41.2f, 1.8f, 1.8f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_drowsy, listOf(
        BotUiHelmetMark.Line("M23 34.5q3 1.6 6 0M35 34.5q3 1.6 6 0", 2.4f), BotUiHelmetMark.Line("M30 41h4", 2f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_working, listOf(
        BotUiHelmetMark.Bar(24.5f, 30.5f, 3f, 6.5f, 1.5f), BotUiHelmetMark.Bar(36.5f, 30.5f, 3f, 6.5f, 1.5f), BotUiHelmetMark.Line("M28.5 41.5h7", 2f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_thinking, listOf(
        BotUiHelmetMark.Dot(26.5f, 33f, 2.8f), BotUiHelmetMark.Dot(37.5f, 33f, 2.8f), BotUiHelmetMark.Line("M29.5 41.5l5-1.2", 2f),
        BotUiHelmetMark.Dot(50.5f, 13.5f, 1.4f, onFace = false), BotUiHelmetMark.Dot(54.5f, 9.5f, 1.9f, onFace = false),
        BotUiHelmetMark.Dot(59f, 5f, 2.4f, onFace = false),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_listening, listOf(
        BotUiHelmetMark.Dot(25.5f, 33.5f, 3f), BotUiHelmetMark.Dot(36.5f, 33.5f, 3f), BotUiHelmetMark.Oval(31f, 41f, 2.2f, 2.6f),
        BotUiHelmetMark.Line("M5.5 28q-2.5 6 0 12M1.5 25q-3.5 9 0 18", 1.8f, onFace = false),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_sleeping, listOf(
        BotUiHelmetMark.Line("M23 33.5q3 2.6 6 0M35 33.5q3 2.6 6 0", 2.2f), BotUiHelmetMark.Line("M30.5 41h3", 2f),
        BotUiHelmetMark.Line("M48 9h5l-5 5h5M55.5 3h3.5l-3.5 3.5h3.5", 1.7f, onFace = false),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_doubtful, listOf(
        BotUiHelmetMark.Dot(26f, 34f, 2.9f), BotUiHelmetMark.Line("M35 34h6", 2.4f), BotUiHelmetMark.Line("M34.5 29.5l6-1.5", 1.8f),
        BotUiHelmetMark.Line("M28.5 41q1.75-1.6 3.5 0t3.5 0", 1.8f),
    )),
    BotUiHelmetExpression(R.string.bot_ui_expression_proud, listOf(
        BotUiHelmetMark.Line("M22.8 35q3.2-3.6 6.4 0M34.8 35q3.2-3.6 6.4 0", 2.4f), BotUiHelmetMark.Line("M27 39.5q5 3.6 10 0", 2.2f),
        BotUiHelmetMark.Fill("M48.5 7l1.1 3.4 3.4 1.1-3.4 1.1-1.1 3.4-1.1-3.4-3.4-1.1 3.4-1.1z", onFace = false),
    )),
)

/** Every path of the helmet, parsed once on first draw (Android paths, so never touched by the JVM tests). */
private object HelmetPaths {
    private fun parse(d: String): Path = PathParser().parsePathString(d).toPath()
    val outlines = BotUiHelmetOutlines.map { parse(it.path) }
    val highlight = parse(HELMET_HIGHLIGHT)
    val marks: Map<String, Path> = BotUiHelmetExpressions.flatMap { it.marks }.mapNotNull {
        when (it) {
            is BotUiHelmetMark.Line -> it.path
            is BotUiHelmetMark.Fill -> it.path
            else -> null
        }
    }.associateWith { parse(it) }
}

/**
 * The bubble helmet (owner 11/28, bubble-helmet-avatar-spec.md, the same drawing as iOS): in a 64-unit box, the outline filled at
 * 25 % and stroked 2.5, the highlight, the small face and the expression.
 */
private fun DrawScope.drawHelmet(profile: BotUiProfile) {
    val tile = botUiAvatarColor(profile).color
    val ink = Color(botUiInk(profile))
    val unit = size.minDimension / 64f
    withTransform({
        translate((size.width - 64f * unit) / 2f, (size.height - 64f * unit) / 2f)
        scale(unit, unit, pivot = Offset.Zero)
        // As the website's inline SVG, nothing is drawn outside the box: the star's lower point (64.5) is cut.
        clipRect(0f, 0f, 64f, 64f)
    }) {
        val outline = HelmetPaths.outlines[profile.shape.coerceIn(0, HelmetPaths.outlines.lastIndex)]
        drawPath(outline, tile, alpha = .25f)
        drawPath(outline, tile, style = Stroke(2.5f, join = StrokeJoin.Round))
        drawPath(HelmetPaths.highlight, Color.White, alpha = .7f, style = Stroke(2.5f, cap = StrokeCap.Round))
        drawRoundRect(tile, Offset(17f, 22f), Size(30f, 26f), CornerRadius(11f))
        for (mark in BotUiHelmetExpressions[profile.expression.coerceIn(0, BotUiHelmetExpressions.lastIndex)].marks) {
            when (mark) {
                is BotUiHelmetMark.Dot -> drawCircle(if (mark.onFace) ink else tile, mark.r, Offset(mark.x, mark.y))
                is BotUiHelmetMark.Ring -> drawCircle(ink, mark.r, Offset(mark.x, mark.y), style = Stroke(mark.width))
                is BotUiHelmetMark.Oval -> drawOval(ink, Offset(mark.x - mark.rx, mark.y - mark.ry), Size(2 * mark.rx, 2 * mark.ry))
                is BotUiHelmetMark.Bar -> drawRoundRect(ink, Offset(mark.x, mark.y), Size(mark.w, mark.h), CornerRadius(mark.r))
                // Only the sleeping z's have corners, and the reference joins those round.
                is BotUiHelmetMark.Line -> drawPath(HelmetPaths.marks.getValue(mark.path), if (mark.onFace) ink else tile,
                    style = Stroke(mark.width, cap = StrokeCap.Round, join = StrokeJoin.Round))
                is BotUiHelmetMark.Fill -> drawPath(HelmetPaths.marks.getValue(mark.path), if (mark.onFace) ink else tile)
            }
        }
    }
}

/** The helmet alone, without a description: for pickers whose button already says which choice it is. */
@Composable
internal fun BotUiHelmet(profile: BotUiProfile, modifier: Modifier) {
    Canvas(modifier) { drawHelmet(profile) }
}

/** A conversation's identity: the bubble helmet, or the uploaded picture cropped to a 27 % rounded square. */
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
    else BotUiHelmet(profile, modifier.semantics { contentDescription = description })
}
