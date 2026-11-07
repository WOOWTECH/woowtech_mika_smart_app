package com.wangzan101.mika.task

import android.app.Notification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * WOOWTECH fork: 要响铃、弹出的通知都放进有摘要的组([AlertGroup]),安卓 16 不会把它们叠进系统的自动组、标成静音。
 */
class AlertGroupTest {
    /** 组里的通知自己提醒、摘要不提醒;安静发的那条(悬浮胶囊显示时、静静备好的填码通知)连自己也不提醒。 */
    @Test fun childrenAlertAndTheSummaryNever() {
        assertEquals(Notification.GROUP_ALERT_CHILDREN, AlertGroup.alertBehavior(quiet = false))
        assertEquals(Notification.GROUP_ALERT_SUMMARY, AlertGroup.alertBehavior(quiet = true))
    }

    /** 每个任务一组:撤一个任务的通知连摘要一起撤,撤不到别的任务的。也不再用上游和 woow.2 那几个没有摘要的组。 */
    @Test fun groupsAreDistinctAndHaveSummaries() {
        val keys = listOf(AlertGroup.RESULTS.key, AlertGroup.PAIRING.key) + (0..2).map { AlertGroup.attention(it).key }
        assertEquals(keys.size, keys.toSet().size)
        assertEquals(AlertGroup.attention(1).key, AlertGroup.attention(1).key)
        val summaryless = setOf("com.wangzan101.mika.quiet", "com.wangzan101.mika.schedule", "pairing_quiet")
        assertTrue(keys.toString(), keys.none { it in summaryless })
    }

    /**
     * 一组一条的组,摘要和那一条一起自动消失(填码通知 10 分钟、配对成功 8 秒);那一条没设就不设。
     * 结果组不设:到时撤掉摘要,系统会把组里别的结果一起撤掉。
     */
    @Test fun onlySingleGroupsMirrorTheTimeout() {
        assertEquals(600_000L, AlertGroup.summaryTimeout(single = true, childTimeoutMs = 600_000L))
        assertNull(AlertGroup.summaryTimeout(single = true, childTimeoutMs = 0L))
        assertNull(AlertGroup.summaryTimeout(single = false, childTimeoutMs = 8_000L))
    }

    /**
     * 同一区段里只有 1~2 条通知的组满 6 个(AOSP NotificationManagerService 的 AUTOGROUP_SPARSE_GROUPS_AT_COUNT),系统照样把它们叠进
     * 自动组、标成静音。这里最多同时有:每个进行中的任务一组、结果一组、配对一组。
     */
    @Test fun staysBelowTheSystemsSparseGroupLimit() {
        val tasks = ParallelCapability.detect(sdk = 36, lowRam = false, userMax = Int.MAX_VALUE, secondDisplayFailed = false).max
        assertTrue("$tasks tasks", tasks + 2 < SYSTEM_SPARSE_GROUPS)
    }

    /**
     * 会提醒的频道上的通知都经 [AlertGroup] 发、撤。直接 notify 的没有组摘要,安卓 16 会把它叠进自动组、标成静音;
     * 直接 cancel 的会留下没有子通知的摘要。同步上游时这几行容易被改回去。
     */
    @Test fun alertingNotificationsGoThroughTheirGroups() {
        val files = File("src/main/java").walk().filter { it.extension == "kt" }.toList()
        // 确认真的找到了发通知的代码(路径不对、同名文件时不会悄悄通过)
        fun source(name: String) = files.single { it.name == name }.readText()
        assertTrue(source("AlertGroup.kt").isNotEmpty())
        // 在「需要你」、结果频道上建通知的只有这两个文件;新加的也要放进有摘要的组,再加进这里
        val alerting = Regex("""Notification\.Builder\([^)]*CHANNEL_(ATTENTION|RESULT)\b""")
        assertEquals(setOf("TaskService.kt", "TriggerRuntime.kt"), files.filter { alerting.containsMatchIn(it.readText()) }.map { it.name }.toSet())
        // 直接 notify、cancel 的只剩静音的进度通知和留页通知
        val raw = Regex("""(?:\b(?:nm|notifications)|NotificationManager::class\.java\))\.(?:notify|cancel)\(\s*([^,)]+)""")
        fun rawIds(name: String) = raw.findAll(source(name)).map { it.groupValues[1].trim() }.toSet()
        assertEquals(setOf("id(ID_PROGRESS", "ID_KEPT"), rawIds("TaskService.kt"))
        assertEquals(emptySet<String>(), rawIds("TriggerRuntime.kt"))
        assertEquals(emptySet<String>(), rawIds("PairingNotifier.kt"))
        // 要你同意的通知也放进任务的组
        assertTrue(source("TaskService.kt").contains("group = AlertGroup.attention(run.slot)"))
    }

    private companion object {
        const val SYSTEM_SPARSE_GROUPS = 6
    }
}
