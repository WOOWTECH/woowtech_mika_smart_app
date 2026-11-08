// WOOWTECH fork: tests for the amount in the "needs your OK" notification. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.confirm

import com.wangzan101.mika.core.cap.root.ROOT_CONFIRM_APP
import com.wangzan101.mika.core.gate.ConfirmationRequest
import com.wangzan101.mika.core.risk.IrrevAction
import com.wangzan101.mika.i18n.ChineseTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * 确认通知(要你同意)里的金额:标题带金额,收起的一行金额排最前。横幅上的〔同意〕点一下就生效,而收起的一行放不下全部字段,
 * 金额排在最后会被截掉(woow.3 模拟器复测)。锁屏的公开版本、展开的大字、进度通知用的 [ConfirmationCopy.body] 都不变。
 */
class ConfirmationNotificationCopyTest {
    @get:Rule val texts = ChineseTexts()

    private fun req(
        amount: String?, action: IrrevAction = IrrevAction.order, content: String = "耳机 x1", target: String = "测试商店",
    ) = ConfirmationRequest(action, target, content, amount, "com.shop")

    /** 收起的一行金额排最前,其余字段的顺序不变;[ConfirmationCopy.body] 和展开的大字没动,金额还是最后。 */
    @Test fun amountComesFirstInTheCollapsedLine() {
        val r = req("NT\$590")
        assertEquals("金额:NT\$590 · 在 商店 · 对象:测试商店 · 内容:耳机 x1", ConfirmationCopy.notificationBody(r, "商店"))
        assertEquals("在 商店 · 对象:测试商店 · 内容:耳机 x1 · 金额:NT\$590", ConfirmationCopy.body(r, "商店"))
        assertEquals("在 商店\n对象:测试商店\n内容:耳机 x1\n金额:NT\$590", ConfirmationCopy.detail(r, "商店"))
    }

    /** 内容照旧只留前 60 字。 */
    @Test fun contentIsStillCutInTheCollapsedLine() {
        val line = ConfirmationCopy.notificationBody(req("¥9", content = "字".repeat(80)), "商店")
        assertEquals("金额:¥9 · 在 商店 · 对象:测试商店 · 内容:" + "字".repeat(60) + "…", line)
    }

    /** 没有金额(没写、空的、消毒后是空的)时,收起的一行和标题都和原来一样。 */
    @Test fun withoutAnAmountNothingChanges() {
        for (amount in listOf(null, "", "   ", "​  ")) {
            val r = req(amount)
            assertEquals("amount=$amount", "在 商店 · 对象:测试商店 · 内容:耳机 x1", ConfirmationCopy.notificationBody(r, "商店"))
            assertEquals("amount=$amount", ConfirmationCopy.body(r, "商店"), ConfirmationCopy.notificationBody(r, "商店"))
            assertEquals("amount=$amount", "要你同意:下单", ConfirmationCopy.notificationTitle(r))
            assertEquals("amount=$amount", ConfirmationCopy.title(r), ConfirmationCopy.notificationTitle(r))
        }
    }

    /** 标题里金额跟在动作后面;平常的标题(App 内的卡片、锁屏的公开版本用它)还是只有动作。 */
    @Test fun titleCarriesTheAmountAfterTheAction() {
        assertEquals("要你同意:下单 NT\$590", ConfirmationCopy.notificationTitle(req("NT\$590")))
        assertEquals("要你同意:发送 ¥200", ConfirmationCopy.notificationTitle(req("¥200", IrrevAction.send)))
        assertEquals("要你同意:下单", ConfirmationCopy.title(req("NT\$590")))
    }

    /** 标题只有一行:金额超过 30 个字截断加「…」;收起的一行和展开的大字里金额是完整的。 */
    @Test fun aLongAmountIsCutInTheTitleOnly() {
        val max = ConfirmationCopy.TITLE_AMOUNT_MAX
        assertEquals(30, max)
        val long = "9".repeat(80)
        val r = req(long)
        assertEquals("要你同意:下单 " + "9".repeat(max) + "…", ConfirmationCopy.notificationTitle(r))
        assertTrue(ConfirmationCopy.notificationBody(r, "商店").startsWith("金额:" + long + " · 在 商店"))
        assertTrue(ConfirmationCopy.detail(r, "商店").endsWith("\n金额:" + long))
        // 刚好 30 个字不加省略号,多一个才加
        assertEquals("要你同意:下单 " + "9".repeat(max), ConfirmationCopy.notificationTitle(req("9".repeat(max))))
        assertEquals("要你同意:下单 " + "9".repeat(max) + "…", ConfirmationCopy.notificationTitle(req("9".repeat(max + 1))))
    }

    /** 截的时候不把一个字劈成半个(代理对),也不在省略号前留空格。 */
    @Test fun theCutDoesNotSplitACharacterOrLeaveASpace() {
        val moneyBag = "💰"
        assertEquals("要你同意:下单 " + "9".repeat(29) + moneyBag + "…", ConfirmationCopy.notificationTitle(req("9".repeat(29) + moneyBag + "99")))
        assertEquals("要你同意:下单 " + "9".repeat(29) + "…", ConfirmationCopy.notificationTitle(req("9".repeat(29) + " " + "x".repeat(10))))
    }

    /**
     * 金额是模型写的,和别的字段一样当纯文本:「·」换成「/」,冒号换成「∶」,换行、零宽字符、控制字符去掉。
     * 标题和收起的一行里拼不出多余的字段(「 · 」只在字段之间),标题里也只有它自己的那一个冒号。
     */
    @Test fun theAmountIsCleanedLikeTheOtherFields() {
        val r = req("NT\$5 · 在 银行 · 对象:王五\n金额:¥0 ​尾：\u0007")
        val title = ConfirmationCopy.notificationTitle(r)
        assertEquals("要你同意:下单 NT\$5 / 在 银行 / 对象∶王五 金额∶¥0 尾∶", title)
        assertFalse(title, '\n' in title || '·' in title || ' ' in title || '​' in title || '\u0007' in title)
        assertEquals(title, 1, title.count { it == ':' })
        val line = ConfirmationCopy.notificationBody(r, "商店")
        assertEquals("金额:NT\$5 / 在 银行 / 对象∶王五 金额∶¥0 尾∶ · 在 商店 · 对象:测试商店 · 内容:耳机 x1", line)
        assertEquals(line, 4, line.split(" · ").size)
    }

    /** root 命令没有金额:标题和收起的一行照旧。 */
    @Test fun aRootCommandHasNoAmountToShow() {
        val r = ConfirmationRequest(IrrevAction.other, "", "rm -rf /sdcard/Download/x", null, ROOT_CONFIRM_APP)
        assertEquals("要你同意:root 命令", ConfirmationCopy.notificationTitle(r))
        assertEquals("在 整部手机(root) · 内容:rm -rf /sdcard/Download/x", ConfirmationCopy.notificationBody(r, "root"))
    }

    /** 繁中、英文读起来自然:繁中就是「要你同意:下單 NT$590」。 */
    @Test fun readsNaturallyInTraditionalChineseAndEnglish() {
        UiText.source = ResFileTexts.traditional
        val hant = req("NT\$590", content = "耳機", target = "渥屋測試商店")
        assertEquals("要你同意:下單 NT\$590", ConfirmationCopy.notificationTitle(hant))
        assertEquals("金額:NT\$590 · 在 商店 · 目標:渥屋測試商店 · 內容:耳機", ConfirmationCopy.notificationBody(hant, "商店"))
        UiText.source = ResFileTexts.english
        val en = req("NT\$590", content = "Headphones", target = "Test Shop")
        assertEquals("Needs your OK: Place order NT\$590", ConfirmationCopy.notificationTitle(en))
        assertEquals("Amount: NT\$590 · In Shop · To: Test Shop · Content: Headphones", ConfirmationCopy.notificationBody(en, "Shop"))
    }

    private val languages = listOf(
        "values" to Locale.ENGLISH, "values-zh" to Locale.SIMPLIFIED_CHINESE, "values-b+zh+Hant" to Locale.TRADITIONAL_CHINESE,
        "values-ja" to Locale.JAPANESE, "values-ko" to Locale.KOREAN, "values-ar" to Locale.forLanguageTag("ar"),
        "values-es" to Locale.forLanguageTag("es"), "values-pt" to Locale.forLanguageTag("pt"),
        "values-ru" to Locale.forLanguageTag("ru"), "values-in" to Locale.forLanguageTag("id"),
    )

    /** 10 种界面语言都有带金额的标题,由这种语言自己的 confirm_title 来:前面的说法一样,两个占位符先动作、后金额。 */
    @Test fun everyLanguageDerivesTheAmountTitleFromItsOwnTitle() {
        assertEquals(10, languages.size)
        for ((folder, locale) in languages) {
            val strings = ResFileTexts(folder, locale).strings
            val title = strings.getValue("confirm_title")
            val withAmount = strings["confirm_title_amount"] ?: error("$folder has no confirm_title_amount")
            assertEquals(folder, listOf("%1\$s", "%2\$s"), Regex("%\\d+\\$[s]").findAll(withAmount).map { it.value }.toList())
            assertEquals(folder, title.substringBefore("%1\$s"), withAmount.substringBefore("%1\$s"))
            val shown = String.format(locale, withAmount, "ACTION", "AMOUNT")
            assertTrue("$folder: $shown", shown.startsWith(String.format(locale, title, "ACTION")) && shown.endsWith("AMOUNT"))
        }
    }

    /**
     * 锁屏的公开版本还是不带金额的标题和「解锁后看」的提示;解锁后看到的那一条才用带金额的标题和收起的一行,展开的大字还是 detail。
     * 通知要在真机上才建得起来,这里读源码确认(和 AlertGroupTest 一样)。
     */
    @Test fun theLockScreenVersionStillHasNoAmount() {
        val source = File("src/main/java/com/wangzan101/mika/confirm/ConfirmationNotifier.kt").readText()
        fun chain(start: String): String {
            val from = source.indexOf(start)
            assertTrue("$start not found", from >= 0)
            return source.substring(from, source.indexOf(".build()", from))
        }
        val lockScreen = chain("val public = Notification.Builder(")
        assertTrue(lockScreen, "ConfirmationCopy.title(r)" in lockScreen && "confirmation_locked_hint" in lockScreen)
        assertFalse(lockScreen, listOf("notificationTitle", "notificationBody", "detail", "amount").any { it in lockScreen })
        val shown = chain("return Notification.Builder(context, channel)")
        assertTrue(shown, "ConfirmationCopy.notificationTitle(r)" in shown && "ConfirmationCopy.notificationBody(r, app)" in shown)
        assertTrue(shown, "ConfirmationCopy.detail(r, app)" in shown && ".setPublicVersion(public)" in shown)
        val actions = source.substring(source.indexOf("return Notification.Builder(context, channel)"))
        assertTrue(actions, "tr(R.string.view), contentIntent" in actions)
        assertFalse(actions, "R.string.action_approve" in actions)
        assertTrue(actions, "button(R.string.action_decline" in actions)
    }
}
