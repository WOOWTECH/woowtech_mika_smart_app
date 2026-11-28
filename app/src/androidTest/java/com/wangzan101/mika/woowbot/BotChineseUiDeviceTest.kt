package com.wangzan101.mika.woowbot

import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.core.brand.Brand
import com.wangzan101.mika.i18n.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/**
 * iOS parity Q14 (owner 2026-11-28): following the system, a phone set to Simplified Chinese or Cantonese shows the
 * Traditional Chinese UI, as the iOS app does; English, and other languages without a UI, stay English. Checks what the APK
 * itself resolves for each system language (the Traditional strings the build copies for zh-Hans and yue), and the language
 * AppLanguage gives the app's own screens.
 */
@RunWith(AndroidJUnit4::class)
class BotChineseUiDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Before fun woowtechOnly() = assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)

    private fun resources(tags: String): Resources = context.createConfigurationContext(
        Configuration(context.resources.configuration).apply { setLocales(LocaleList.forLanguageTags(tags)) },
    ).resources

    @Test fun chinesePhonesGetTheTraditionalStrings() {
        val hant = resources("zh-Hant-TW")
        assertEquals("zh-Hant", hant.getString(R.string.ui_locale))
        // One string from each source: the brand's own, a brand-renamed upstream one, upstream's, and the woowtechbot screens'.
        val ids = listOf(R.string.app_name, R.string.about_data_note, R.string.takeover_move_back_failed, R.string.model_setup_title, R.string.bot_ui_profile)
        for (tags in listOf("zh-Hans-CN", "zh-CN", "zh-SG", "zh", "yue-HK", "ja-JP,zh-Hans-CN")) {
            val r = resources(tags)
            assertEquals(tags, "zh-Hant", r.getString(R.string.ui_locale))
            for (id in ids) assertEquals("$tags ${context.resources.getResourceEntryName(id)}", hant.getString(id), r.getString(id))
        }
        assertEquals("渥屋助理", resources("zh-Hans-CN").getString(R.string.app_name))
        // Upstream's Simplified UI is not shipped: nothing comes back in Simplified.
        assertEquals("設定模型", resources("zh-Hans-CN").getString(R.string.model_setup_title))
        for (tags in listOf("en-US", "fr-FR", "ja-JP", "en-US,zh-Hans-CN")) assertEquals(tags, "en", resources(tags).getString(R.string.ui_locale))
    }

    @Test fun appScreensSwitchToTraditionalChinese() {
        fun of(tags: String) = AppLanguage.followSystem(tags.split(',').map(Locale::forLanguageTag), Brand.chineseUi)?.toLanguageTag()
        for (tags in listOf("zh-Hans-CN", "zh-CN", "zh-SG", "zh", "yue-HK", "ja-JP,zh-Hans-CN")) assertEquals(tags, "zh-Hant-TW", of(tags))
        // Already Traditional, English first, or no Chinese at all: Android's own choice stands.
        for (tags in listOf("zh-TW", "zh-HK", "zh-MO", "zh-Hant-TW", "en-US", "fr-FR", "en-US,zh-Hans-CN", "ja-JP,en-US,zh-CN")) assertNull(tags, of(tags))
    }
}
