package com.wangzan101.mika.task

import com.wangzan101.mika.core.agent.FailKind
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.i18n.ChineseTexts
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** WOOWTECH fork: 任务通知上的说法。 */
class TaskNotificationCopyTest {
    @get:Rule val texts = ChineseTexts()

    /** 电脑端取消了它交来的任务:照实说是电脑停的,不写「你停止了这个任务」;别的结局同 [TaskService.describe]。 */
    @Test fun stoppedFromTheComputerSaysSo() {
        assertEquals("任务已停止" to "电脑端停止了这个任务", TaskService.describeResult(TaskState.Cancelled, fromComputer = true))
        assertEquals("任务已停止" to "你停止了这个任务", TaskService.describeResult(TaskState.Cancelled, fromComputer = false))
        val failed = TaskState.Failed("没办成", FailKind.GaveUp)
        assertEquals(TaskService.describe(failed), TaskService.describeResult(failed, fromComputer = true))
    }
}
