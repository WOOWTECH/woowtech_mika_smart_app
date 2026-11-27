package com.wangzan101.mika.ui.theme

import com.wangzan101.mika.core.brand.Brand
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * 界面用到的全部颜色。页面一律从 [MikaTheme.colors] 取,不写死色值。
 * 实色只用在强调(主按钮、选中、开关、用户消息)和状态(成功、需要你、出错);图标块一律中性。
 */
@Immutable
data class MikaColors(
    /** 页面背景。 */
    val bg: Color,
    /** 卡片、分组。 */
    val surface: Color,
    /** 浅填充:次按钮、分段控件底、代码块底。 */
    val fill: Color,
    /** 文字三级:正文、次要、辅助。 */
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    /** 分隔线。 */
    val hair: Color,
    /** 卡片描边。 */
    val edge: Color,
    val accent: Color,
    val accentSoft: Color,
    /** 强调色上的文字和图标。 */
    val onAccent: Color,
    val ok: Color,
    val okSoft: Color,
    /** 「需要你」:[warn] 用于文字,[warnSolid] 用于圆点、描边。 */
    val warn: Color,
    val warnSolid: Color,
    val warnSoft: Color,
    val bad: Color,
    val badSoft: Color,
    /** 图标块的底。 */
    val neutralSoft: Color,
    /** Mika 回答的底:比页面背景深一点点的灰,和用户的蓝色气泡区分开。 */
    val answer: Color,
    /** 灰色胶囊、关着的开关。 */
    val greySoft: Color,
    /** 悬浮玻璃(输入栏、浮在内容上的按钮)的底和描边。 */
    val glass: Color,
    val glassEdge: Color,
    /** 卡片阴影;深色下卡片只靠描边,为透明。 */
    val cardShadow: Color,
    /** 悬浮元素的阴影。 */
    val floatShadow: Color,
    /** 开关的圆钮。 */
    val thumb: Color,
    /**
     * 图表里分类的颜色(例如每家服务商一种),按固定的先后取;超出的归到 [seriesOther]。
     * 只给图形上色,文字一律用 ink 三级。
     */
    val series: List<Color>,
    val seriesOther: Color,
    /** 图表的网格线。 */
    val grid: Color,
    val isDark: Boolean,
    /**
     * woowtechbot surfaces (Direct WOOWTECH). Every other brand keeps the shared tokens above, so these default to them.
     * panel = sheets, menu = popovers and dialogs, control = round buttons and chips, inset = recessed fields.
     */
    val panel: Color = bg,
    val menu: Color = surface,
    val menuHover: Color = fill,
    val menuActive: Color = fill,
    val control: Color = fill,
    val inset: Color = surface,
    val raisedHover: Color = fill,
)

val LightColors = MikaColors(
    bg = Color(0xFFF7F7F8),
    surface = Color(0xFFFFFFFF),
    fill = Color(0x0A000000),
    ink = Color(0xFF1C1C1E),
    ink2 = Color(0xFF5F6068),
    ink3 = Color(0xFF9A9BA3),
    hair = Color(0x12000000),
    edge = Color(0x0D000000),
    accent = Color(Brand.argb("accent.light", 0xFF0A7CFF)),
    accentSoft = Color(Brand.argb("accent.light.soft", 0x1A0A7CFF)),
    onAccent = Color(Brand.argb("accent.light.on", 0xFFFFFFFF)),
    ok = Color(0xFF1F9D55),
    okSoft = Color(0x1F1F9D55),
    warn = Color(0xFFB86E00),
    warnSolid = Color(0xFFFF9F0A),
    warnSoft = Color(0x1FFF9F0A),
    bad = Color(0xFFE5483D),
    badSoft = Color(0x1AE5483D),
    neutralSoft = Color(0x0B000000),
    answer = Color(0x09000000),
    greySoft = Color(0x1F767680),
    glass = Color(0xB8FFFFFF),
    glassEdge = Color(0x0F000000),
    cardShadow = Color(0xFF000000),
    floatShadow = Color(0xFF000000),
    thumb = Color(0xFFFFFFFF),
    series = listOf(Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A)),
    seriesOther = Color(0xFFB4B5BC),
    grid = Color(0x0F000000),
    isDark = false,
)

val DarkColors = MikaColors(
    bg = Color(0xFF0E0E10),
    surface = Color(0xFF1A1A1D),
    fill = Color(0x0FFFFFFF),
    ink = Color(0xFFF2F2F4),
    ink2 = Color(0xFFA4A5AD),
    ink3 = Color(0xFF6C6D75),
    hair = Color(0x14FFFFFF),
    edge = Color(0x0FFFFFFF),
    accent = Color(Brand.argb("accent.dark", 0xFF3D97FF)),
    accentSoft = Color(Brand.argb("accent.dark.soft", 0x293D97FF)),
    onAccent = Color(Brand.argb("accent.dark.on", 0xFFFFFFFF)),
    ok = Color(0xFF3CCF7A),
    okSoft = Color(0x243CCF7A),
    warn = Color(0xFFFFB340),
    warnSolid = Color(0xFFFF9F0A),
    warnSoft = Color(0x29FF9F0A),
    bad = Color(0xFFFF6961),
    badSoft = Color(0x24FF6961),
    neutralSoft = Color(0x12FFFFFF),
    answer = Color(0x0DFFFFFF),
    greySoft = Color(0x38767680),
    glass = Color(0xB81A1A1D),
    glassEdge = Color(0x14FFFFFF),
    cardShadow = Color.Transparent,
    floatShadow = Color(0xFF000000),
    thumb = Color(0xFFFFFFFF),
    series = listOf(Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70)),
    seriesOther = Color(0xFF5A5B62),
    grid = Color(0x12FFFFFF),
    isDark = true,
)

/** 没有包在 [MikaTheme] 里时(比如界面测试)按浅色。 */
val LocalMikaColors = staticCompositionLocalOf { LightColors }

/** Apporo's Play edition keeps its brand accent (gold) on the shared workspace surfaces. */
private val ApporoAccent = com.wangzan101.mika.BuildConfig.FLAVOR == "apporoplay"

/**
 * Play editions (WOOWTECH and Apporo), aligned with the direct-download WOOWTECH edition. Values are the woowtechbot website's own tokens
 * (measured from the production stylesheet 0.1.169, 2026-11-27): on phones only Midnight has a dedicated set
 * (page #141414, popover #2c2c2e, card #242426, hairline #3a3a3c); Daylight keeps its desktop values.
 */
val WoowLightColors = LightColors.copy(
    bg = Color(0xFFFCFCFC), surface = Color(0xFFEFEFEF), fill = Color(0xFFE3E3E3),
    ink = Color(0xFF1C1C1C), ink2 = Color(0xAD1C1C1C), ink3 = Color(0xA61C1C1C),
    hair = Color(0x3D1C1C1C), edge = Color(0x1F1C1C1C),
    accent = if (ApporoAccent) LightColors.accent else Color(0xFF0B69CC), accentSoft = Color(0xFFE4E4E4),
    onAccent = if (ApporoAccent) LightColors.onAccent else Color.White,
    answer = Color(0xFFEFEFEF), glass = Color(0xFFE3E3E3), glassEdge = Color(0x1F1C1C1C),
    ok = Color(0xFF007A44), bad = Color(0xFFCD2834),
    panel = Color(0xFFF5F5F5), menu = Color(0xFFFFFFFF), menuHover = Color(0x0F1C1C1C), menuActive = Color(0x141C1C1C),
    control = Color(0xFFE3E3E3), inset = Color(0xFFE9E9E9), raisedHover = Color(0xFFD8D8D8),
)
val WoowDarkColors = DarkColors.copy(
    bg = Color(0xFF141414), surface = Color(0xFF242426), fill = Color(0xFF2C2C2E),
    ink = Color(0xFFF5F5F5), ink2 = Color(0xA8F5F5F5), ink3 = Color(0x91F5F5F5),
    hair = Color(0xFF3A3A3C), edge = Color(0x0FF5F5F5),
    accent = if (ApporoAccent) DarkColors.accent else Color(0xFF7FC0FF), accentSoft = Color(0xFF2C2C2E),
    onAccent = if (ApporoAccent) DarkColors.onAccent else Color(0xFF141414),
    answer = Color(0xFF242426), glass = Color(0xFF2C2C2E), glassEdge = Color(0xFF3A3A3C),
    ok = Color(0xFF38D591), bad = Color(0xFFFF5667),
    panel = Color(0xFF1C1C1E), menu = Color(0xFF2C2C2E), menuHover = Color(0x0FF5F5F5), menuActive = Color(0x14F5F5F5),
    control = Color(0xFF2C2C2E), inset = Color(0xFF1C1C1E), raisedHover = Color(0xFF3A3A3C),
)

/**
 * The website's settings dialogs ([data-settings-look]) use their own palette on every width: page #121212, cards #1f1f1f,
 * 9% ink edges. Native sheets that mirror those dialogs (services, notifications) wrap their content in this set.
 */
val WoowSheetDarkColors = WoowDarkColors.copy(
    bg = Color(0xFF121212), surface = Color(0xFF1F1F1F), fill = Color(0xFF282828),
    hair = Color(0xFF383838), edge = Color(0x17F5F5F5),
    accentSoft = Color(0xFF202020), onAccent = Color(0xFF121212),
    answer = Color(0xFF1F1F1F), glass = Color(0xFF282828), glassEdge = Color(0xFF383838),
    panel = Color(0xFF121212), menu = Color(0xFF1F1F1F), control = Color(0xFF282828),
    inset = Color(0xFF1B1B1B), raisedHover = Color(0xFF2C2C2C),
)
val WoowSheetLightColors = WoowLightColors.copy(surface = Color(0xFFFFFFFF), menu = Color(0xFFFFFFFF), edge = Color(0x1A1C1C1C))

/** Popover and dialog corner radius: 22 on phone Midnight, 12 elsewhere (--radius-menu). */
val MikaColors.menuRadius get() = if (isDark) 22 else 12
