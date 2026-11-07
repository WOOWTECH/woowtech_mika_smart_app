// WOOWTECH fork: the in-progress notification names the tool by its label. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.task

import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.i18n.ChineseTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ProgressNoteTest {
    @get:Rule val texts = ChineseTexts()

    /** 模型这一步没写话时 note 是工具名:进行中的通知写工具在界面上的说法,不写工具名;写了话照原话。 */
    @Test fun progressNotificationNamesTheToolByItsLabel() {
        assertEquals("第 2 步:设闹钟", TaskService.describe(TaskState.Running(2, "phone_set_alarm", "phone_set_alarm")).second)
        // 这一步还在等模型回复时 note 是上一步的(一次连做几步的 do_steps 也有说法)
        assertEquals("第 3 步:连续做几步", TaskService.describe(TaskState.Running(3, "do_steps")).second)
        assertEquals("第 2 步:先打开时钟", TaskService.describe(TaskState.Running(2, "先打开时钟", "phone_launch_app")).second)
        UiText.source = ResFileTexts.english
        assertEquals("Step 2: Set alarm", TaskService.describe(TaskState.Running(2, "phone_set_alarm", "phone_set_alarm")).second)
    }
}
