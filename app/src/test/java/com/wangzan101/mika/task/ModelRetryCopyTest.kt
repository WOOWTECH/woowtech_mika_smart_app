package com.wangzan101.mika.task

import com.wangzan101.mika.core.agent.RetryNotice
import com.wangzan101.mika.i18n.ChineseTexts
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** 重试时任务卡片上说一声:断线和服务忙分开说,写明第几次。 */
class ModelRetryCopyTest {
    @get:Rule val texts = ChineseTexts()

    @Test fun saysWhetherTheConnectionDroppedOrTheServiceIsBusy() {
        assertEquals("连接中断,正在重试(第 1 次)…", ModelRetryCopy.note(RetryNotice("main", "network", 1, 1000)))
        assertEquals("连接中断,正在重试(第 2 次)…", ModelRetryCopy.note(RetryNotice("main", "stream_cut", 2, 2000)))
        assertEquals("模型服务繁忙,正在重试(第 3 次)…", ModelRetryCopy.note(RetryNotice("light", "rate_limited", 3, 4000)))
    }
}
