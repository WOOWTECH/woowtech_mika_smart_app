package com.wangzan101.mika.task

import com.wangzan101.mika.cap.phone.setup.BootRestoreHandler
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * 商店版的开机广播只把定时任务的闹钟重新布置好、把开着的电脑连接接回去:接的广播和清单一致,
 * 也不是会去恢复手机操作的 BootRestoreHandler。
 */
class ScheduleRestoreReceiverTest {
    private val androidNs = "http://schemas.android.com/apk/res/android"

    @Test fun handlesTheManifestBroadcastsAndNothingOfPhoneRecovery() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val receivers = doc.getElementsByTagName("receiver")
        val restore = (0 until receivers.length).map { receivers.item(it) as Element }
            .single { it.getAttributeNS(androidNs, "name") == ".task.ScheduleRestoreReceiver" }
        val actions = restore.getElementsByTagName("action")
        val declared = (0 until actions.length).map { (actions.item(it) as Element).getAttributeNS(androidNs, "name") }.toSet()
        assertEquals(declared, ScheduleRestoreReceiver.ACTIONS)
        assertFalse(BootRestoreHandler::class.java.isAssignableFrom(ScheduleRestoreReceiver::class.java))
        // 电脑连接(远程网关)只在开机和 App 更新后接回去:改时间、时区、闹钟权限不碰它
        assertEquals(setOf("android.intent.action.BOOT_COMPLETED", "android.intent.action.MY_PACKAGE_REPLACED"),
            ScheduleRestoreReceiver.RESUMES_COMPUTER_CONNECTION)
        assertTrue(ScheduleRestoreReceiver.ACTIONS.containsAll(ScheduleRestoreReceiver.RESUMES_COMPUTER_CONNECTION))
    }
}
