package com.wangzan101.mika.i18n

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * WOOWTECH fork: 发通知的代码里,界面文字一律经 [tr] 按 App 语言取。服务、广播的 Context 取到的资源可能还是系统语言:
 * App 选繁中、系统是英文时,通知写成「Needs you: Payment」「Reply」。
 */
class NotificationTextsTest {
    private val lookup = Regex("""\bget(String|Text|QuantityString)\(R\.""")

    @Test fun notificationCodeTakesTextsInTheAppLanguage() {
        val builders = File("src/main/java").walk().filter { it.extension == "kt" && "Notification.Builder(" in it.readText() }.toList()
        // 确认真的找到了发通知的代码(路径不对时不会悄悄通过)
        assertTrue(builders.any { it.name == "TaskService.kt" })
        assertEquals(emptyList<String>(), builders.filter { lookup.containsMatchIn(it.readText()) }.map { it.name })
    }
}
