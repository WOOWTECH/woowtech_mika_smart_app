package com.wangzan101.mika.i18n

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.icu.util.ULocale
import android.os.Build
import android.os.LocaleList
import java.util.Locale

/**
 * App 界面的语言:跟随系统,或者选定下面的一种。资源里英文是默认(`values/`),简体中文在 `values-zh/`、繁体中文在 `values-b+zh+Hant/`,
 * 阿拉伯语在 `values-ar/`,其他语言各在 `values-<语言>/`(印尼语沿用安卓的旧代码 `values-in/`)。安卓按语言和文字体系挑资源,
 * 所以「跟随系统」时系统语言有译文就显示它,没有就显示英文;某种语言缺了哪条,那条也显示英文。
 *
 * 安卓 13 起由系统的「应用语言」管(LocaleManager):系统记住选择、套到整个进程、重建界面,
 * 系统设置里的「应用语言」和这里的开关是同一个值。安卓 11、12 没有这项,由这里记在本地,
 * 经 [wrap] 套到界面的 Context、经 [resources] 套到界面以外取文字的地方,换了之后重建当前界面。
 */
enum class AppLanguage(val tag: String?, val speechTag: String?) {
    System(null, null),
    SimplifiedChinese("zh-Hans", "zh-CN"),
    TraditionalChinese("zh-Hant", "zh-TW"),
    Arabic("ar", "ar-MA"),
    English("en", "en-US"),
    Japanese("ja", "ja-JP"),
    Korean("ko", "ko-KR"),
    Spanish("es", "es-ES"),
    Portuguese("pt", "pt-BR"),
    Russian("ru", "ru-RU"),
    Indonesian("id", "id-ID");

    /** 语言代码(不带文字体系和地区);跟随系统时为 null。 */
    val language: String? get() = tag?.let { Locale.forLanguageTag(it).language.let(::modernCode) }

    companion object {
        private const val PREFS = "app_language"
        private const val KEY_TAG = "tag"

        /** 安卓 12 及以前选定的语言;null 表示跟随系统。进程里读一次,换的时候更新。 */
        @Volatile
        private var legacyTag: String? = null
        @Volatile
        private var legacyLoaded = false

        /** 安卓 12 及以前按选定语言建出的资源,跟着语言换。 */
        @Volatile
        private var cached: Pair<String, Resources>? = null

        private val systemManaged get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

        /** Brand default is applied once; a later choice to follow the system is preserved. */
        fun initializeBrandDefault(context: Context) {
            val tag = com.wangzan101.mika.core.brand.Brand.defaultLanguage ?: return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getBoolean("brand_default_initialized", false)) return
            val hasSelection = if (systemManaged) {
                !context.getSystemService(LocaleManager::class.java).applicationLocales.isEmpty
            } else prefs.contains(KEY_TAG)
            if (!hasSelection) set(context, fromTag(tag))
            prefs.edit().putBoolean("brand_default_initialized", true).commit()
        }

        fun current(context: Context): AppLanguage = fromTag(
            if (systemManaged) {
                context.getSystemService(LocaleManager::class.java).applicationLocales.takeUnless { it.isEmpty }?.get(0)?.toLanguageTag()
            } else {
                legacy(context)
            },
        )

        /** 语言标签对应哪一项:见 [fromTag];标签里没写文字体系时,按 ICU 的常见写法补出来。 */
        fun fromTag(tag: String?): AppLanguage = fromTag(tag) { ULocale.addLikelySubtags(ULocale.forLanguageTag(it)).script }

        /**
         * 中文按文字体系分:写的或 [likelyScript] 补出的是 Hant 就是繁體中文,别的中文是简体中文;
         * 其他语言按语言代码对上一项(地区不管),对不上的是英文。以前选「中文」存下的 zh-Hans 仍是简体中文。
         */
        internal fun fromTag(tag: String?, likelyScript: (String) -> String): AppLanguage {
            if (tag.isNullOrEmpty()) return System
            val l = Locale.forLanguageTag(tag)
            val code = modernCode(l.language)
            if (code == "zh") return if (l.script.ifEmpty { likelyScript(tag) } == "Hant") TraditionalChinese else SimplifiedChinese
            return entries.firstOrNull { it.tag != null && it.language == code } ?: English
        }

        /** 安卓上 java.util.Locale 仍给几种语言用旧代码(印尼语是 in、希伯来语是 iw…),统一成现行代码再比。 */
        internal fun modernCode(language: String): String = when (language) {
            "in" -> "id"
            "iw" -> "he"
            "ji" -> "yi"
            else -> language
        }

        /** 换语言并重建界面。安卓 13 起交给系统(系统自己重建);之前记在本地,重建 [context] 所在的界面。 */
        fun set(context: Context, language: AppLanguage) {
            if (systemManaged) {
                context.getSystemService(LocaleManager::class.java).applicationLocales =
                    language.tag?.let(LocaleList::forLanguageTags) ?: LocaleList.getEmptyLocaleList()
                // WOOWTECH fork: 进程的默认语言马上跟着换:无障碍服务在跑时系统不再替进程换(见 [applyDefaultLocale])
                LocaleList.setDefault(language.tag?.let(LocaleList::forLanguageTags) ?: Resources.getSystem().configuration.locales)
                return
            }
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TAG, language.tag).commit()
            legacyTag = language.tag
            legacyLoaded = true
            cached = null
            applyDefaultLocale(context)
            context.activity()?.recreate()
        }

        /**
         * App 启动时调:安卓 12 及以前选了语言时,把进程的默认 Locale(日期、数字的格式)也换成它。
         *
         * WOOWTECH fork: 进程配置变了时(MikaApp.onConfigurationChanged)也调;安卓 13 起选了语言时也设。本来系统会把选的语言
         * 套到整个进程,但同一进程里的无障碍服务一启动,系统就不再让进程的配置跟着界面走(AOSP 的 WindowProcessController.onServiceStarted
         * 对 BIND_ACCESSIBILITY_SERVICE 清掉进程的覆盖配置),进程的默认语言退回系统语言:界面的字照旧(界面和 [resources] 各按
         * App 语言取),排版、字形却按系统语言——繁中的全形「，。」不再置中,内置浏览器向网站要的页面语言也跟着变。
         * 跟随系统时不动。
         */
        fun applyDefaultLocale(context: Context) {
            if (systemManaged) {
                val app = context.getSystemService(LocaleManager::class.java).applicationLocales
                if (!app.isEmpty && LocaleList.getDefault()[0] != app[0]) LocaleList.setDefault(app)
                return
            }
            val locales = legacyLocales(context) ?: Resources.getSystem().configuration.locales
            Locale.setDefault(locales[0])
        }

        /** Apply the selected locale even while Android is delivering a first-launch locale change. */
        fun wrap(base: Context): Context {
            val locales = if (systemManaged) {
                base.getSystemService(LocaleManager::class.java).applicationLocales.takeUnless { it.isEmpty }
            } else legacyLocales(base)
            if (locales == null || base.resources.configuration.locales == locales) return base
            return base.createConfigurationContext(Configuration().apply { setLocales(locales) })
        }

        /**
         * WOOWTECH fork: 无障碍浮层(OverlayHost)建界面用的 Context:同 [wrap],但安卓 13 起也套上 App 语言。浮层借的是无障碍服务的
         * Context,服务一启动,系统就不再把 App 语言套到进程上(见 [applyDefaultLocale]),服务的资源退回系统语言:
         * 浮层里 stringResource 取的字(按住说话、屏幕分享的同意框、胶囊上的按钮)就成了系统语言。跟随系统时原样返回。
         */
        fun wrapOverlay(base: Context): Context {
            val locales = if (systemManaged) {
                base.getSystemService(LocaleManager::class.java).applicationLocales.takeUnless { it.isEmpty }
            } else {
                legacyLocales(base)
            }
            return locales?.let { base.createConfigurationContext(Configuration().apply { setLocales(it) }) } ?: base
        }

        /**
         * 界面以外取文字用的资源:跟着 App 语言。安卓 13 起也按系统记下的应用语言另建一份,
         * 不直接用 Application 的资源:进程不是系统按 App 正常拉起时(如测试启动),那份资源还是系统语言。
         */
        fun resources(app: Context): Resources {
            val tag = if (systemManaged) {
                app.getSystemService(LocaleManager::class.java).applicationLocales.takeUnless { it.isEmpty }?.toLanguageTags()
            } else {
                legacy(app)
            }
            if (tag == null) return app.resources
            cached?.takeIf { it.first == tag }?.let { return it.second }
            val r = app.createConfigurationContext(Configuration().apply { setLocales(LocaleList.forLanguageTags(tag)) }).resources
            cached = tag to r
            return r
        }

        private fun legacyLocales(context: Context): LocaleList? =
            if (systemManaged) null else legacy(context)?.let(LocaleList::forLanguageTags)

        private fun legacy(context: Context): String? {
            if (!legacyLoaded) {
                legacyTag = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TAG, null)
                legacyLoaded = true
            }
            return legacyTag
        }

        private fun Context.activity(): Activity? {
            var c: Context? = this
            while (c is ContextWrapper) {
                if (c is Activity) return c
                c = c.baseContext
            }
            return null
        }
    }
}
