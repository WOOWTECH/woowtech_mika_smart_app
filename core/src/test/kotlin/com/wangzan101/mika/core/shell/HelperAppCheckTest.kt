// WOOWTECH fork: the helper notices that its app was uninstalled or replaced. Not part of upstream Mika.
package com.wangzan101.mika.core.shell

import com.wangzan101.mika.core.shell.HelperAppCheck.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HelperAppCheckTest {
    private val uid = 10_214
    private val pin = HelperHandoff.certPin(listOf(byteArrayOf(1, 2, 3)))!!
    private val otherPin = HelperHandoff.certPin(listOf(byteArrayOf(9, 9, 9)))!!

    @Test
    fun sameUidAndCertificateIsStillTheApp() {
        assertEquals(State.Same, HelperAppCheck.state(uid, pin, pinnedUid = uid, pinnedCert = pin))
        // 多个签名者:指纹排好序再比(见 HelperHandoff.certPin),顺序不同也是同一个
        val two = HelperHandoff.certPin(listOf(byteArrayOf(1), byteArrayOf(2)))!!
        assertEquals(State.Same, HelperAppCheck.state(uid, HelperHandoff.certPin(listOf(byteArrayOf(2), byteArrayOf(1))), uid, two))
    }

    @Test
    fun anotherUidOrCertificateIsAnotherApp() {
        // 卸载后再装(哪怕是同一份 APK)拿到的是新 uid:助手要服务的那个 App 已经不在了
        assertEquals(State.Replaced, HelperAppCheck.state(uid + 1, pin, uid, pin))
        // 同名、换了签名证书
        assertEquals(State.Replaced, HelperAppCheck.state(uid, otherPin, uid, pin))
        assertEquals(State.Replaced, HelperAppCheck.state(uid + 1, otherPin, uid, pin))
        // 原来一个签名者,现在多了一个:也不是同一份证书
        val more = HelperHandoff.certPin(listOf(byteArrayOf(1, 2, 3), byteArrayOf(9, 9, 9)))
        assertEquals(State.Replaced, HelperAppCheck.state(uid, more, uid, pin))
    }

    @Test
    fun unreadableUidOrCertificateIsUnknown() {
        assertEquals(State.Unknown, HelperAppCheck.state(null, pin, uid, pin))
        assertEquals(State.Unknown, HelperAppCheck.state(uid, null, uid, pin))
        // uid 已经对不上时,证书读不到也确定是另一个 App
        assertEquals(State.Replaced, HelperAppCheck.state(uid + 1, null, uid, pin))
    }

    @Test
    fun onlyDefiniteAnswersEndTheHelper() {
        assertTrue(HelperAppCheck.exits(State.Gone))
        assertTrue(HelperAppCheck.exits(State.Replaced))
        assertFalse(HelperAppCheck.exits(State.Same))
        // 查不清时不退出:误退出的话,经电脑 USB 起的助手要用户再插线
        assertFalse(HelperAppCheck.exits(State.Unknown))
    }

    @Test
    fun checksOftenRightAfterDeathThenEveryTenSeconds() {
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 10_000L, 10_000L, 10_000L), (0..6).map { HelperAppCheck.delayMs(it) })
        assertEquals(HelperAppCheck.MAX_DELAY_MS, HelperAppCheck.delayMs(Int.MAX_VALUE))
        assertEquals(HelperAppCheck.FIRST_DELAY_MS, HelperAppCheck.delayMs(-1))
    }

    @Test
    fun anUninstallIsNoticedWithinSecondsHoweverLongAfterDeathItHappens() {
        // 死亡通知当下查第 0 次,之后第 n 次等 delayMs(n):死后 1、3、7、15、25、35… 秒各查一次
        val checks = generateSequence(0L to 0) { (at, n) -> (at + HelperAppCheck.delayMs(n)) to (n + 1) }
            .map { it.first }.takeWhile { it <= HOUR_MS + HelperAppCheck.MAX_DELAY_MS }.toList()
        // 卸载时系统先结束 App、随后才删包:死亡通知当下还查得到的话,一秒后那次就看到包没了
        assertEquals(listOf(0L, 1_000L, 3_000L, 7_000L, 15_000L, 25_000L), checks.take(6))
        // App 死了很久之后才被卸载(之前被系统清掉、用户强行停止过):最多 MAX_DELAY_MS 就发现
        for (goneAt in 0L..HOUR_MS step 500L) {
            val seenAt = checks.first { it >= goneAt }
            assertTrue("gone at $goneAt ms, noticed at $seenAt ms", seenAt - goneAt <= HelperAppCheck.MAX_DELAY_MS)
        }
        // App 不回来时一小时只查几百次(手机深度睡眠时 Handler 的计时也停)
        assertTrue(checks.size < 400)
    }

    private companion object {
        const val HOUR_MS = 3_600_000L
    }
}
