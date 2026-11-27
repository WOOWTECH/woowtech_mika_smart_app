package com.wangzan101.mika.task

import com.wangzan101.mika.i18n.ChineseTexts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

/** 外部 MCP server 没连上:任务卡片上说一句,用设置里的名字(认不出的用编号);都连上了不说。 */
class McpRunNoticeTest {
    @get:Rule val texts = ChineseTexts()

    @Test fun namesTheServersThatFailedToConnect() {
        val failures = listOf("a1" to "connect timed out", "zz" to "HTTP 401")
        assertEquals("MCP 服务器连接失败:Notion, zz", McpRunNotice.text(failures, mapOf("a1" to "Notion", "b2" to "GitHub")))
    }

    @Test fun saysNothingWhenEveryServerConnected() {
        assertNull(McpRunNotice.text(emptyList(), mapOf("a1" to "Notion")))
    }
}
