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

    /** 通知不渲染 Markdown:粗体、标题、反引号、表格的 | 都不露出来;挨着中文标点、CommonMark 认不成粗体的 ** 也去掉。 */
    @Test fun notificationTextDropsMarkdown() {
        assertEquals(
            "已找到三款 新台币 1,000 元以下的耳机。\n\n比较\n\n品名 · 价格\nA · NT$990\n\n用 code 搜",
            TaskService.notificationText(
                "已找到三款 **新台币 1,000 元以下**的耳机。\n\n## 比较\n\n| 品名 | 价格 |\n| --- | --- |\n| A | NT$990 |\n\n用 `code` 搜",
            ),
        )
        assertEquals("「重点」在这里", TaskService.notificationText("**「重点」**在这里"))
        // 本来就是纯文字的原样
        assertEquals("该喝水啰!\n记得起来走走", TaskService.notificationText("该喝水啰!\n记得起来走走"))
        assertEquals("", TaskService.notificationText(""))
    }
}
