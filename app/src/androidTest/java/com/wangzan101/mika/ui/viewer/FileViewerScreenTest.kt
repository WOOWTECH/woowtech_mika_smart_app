package com.wangzan101.mika.ui.viewer

import com.wangzan101.mika.ChineseUi
import android.net.Uri
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.ui.theme.MikaTheme
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FileViewerScreenTest {
    @get:Rule(order = Int.MIN_VALUE) val chinese = ChineseUi()

    @get:Rule val compose = createComposeRule()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = com.wangzan101.mika.CloseComposeActivity(compose)

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun file(name: String, content: String): Uri =
        Uri.fromFile(File(context.cacheDir, name).apply { writeText(content) })

    private fun show(uri: Uri, name: String) {
        val kind = FileViewer.kindOf(context, uri, name)
        compose.setContent { MikaTheme { FileViewerScreen(uri, name, kind, onBack = {}) } }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("viewer.loading").fetchSemanticsNodes().isEmpty() }
    }

    @Test fun markdownFileIsRendered() {
        show(file("notes.md", "# 周报\n\n本周完成了 **三件事**。\n\n- 第一项\n- 第二项\n"), "notes.md")
        compose.onNodeWithTag("viewer.markdown").assertIsDisplayed()
        compose.onNodeWithText("周报").assertIsDisplayed()
        compose.onNodeWithText("第一项").assertIsDisplayed()
        compose.onNodeWithText("notes.md").assertIsDisplayed()
    }

    @Test fun textFileIsShownAsIs() {
        show(file("run.log", "line one\nline two: ok\n"), "run.log")
        compose.onNodeWithTag("viewer.text").assertIsDisplayed()
        compose.onNodeWithText("line two: ok", substring = true).assertIsDisplayed()
    }

    @Test fun saveCopyCanOpenSystemPickerAndCancel() {
        show(file("document-save.csv", "中文,123\r\n"), "document-save.csv")
        compose.onNodeWithContentDescription(context.getString(com.wangzan101.mika.R.string.viewer_save_as)).performClick()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val deadline = android.os.SystemClock.uptimeMillis() + 10000
        var opened = false
        while (android.os.SystemClock.uptimeMillis() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString()?.contains("documentsui") == true) { opened = true; break }
            android.os.SystemClock.sleep(100)
        }
        org.junit.Assert.assertTrue("System document picker did not open", opened)
        val cancelDeadline = android.os.SystemClock.uptimeMillis() + 5000
        while (android.os.SystemClock.uptimeMillis() < cancelDeadline &&
            instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() != context.packageName) {
            instrumentation.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            android.os.SystemClock.sleep(300)
        }
        compose.onNodeWithTag("viewer.text").assertIsDisplayed()
    }

    private fun clickSystemNode(find: (android.view.accessibility.AccessibilityNodeInfo) -> Boolean) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun search(node: android.view.accessibility.AccessibilityNodeInfo?): android.view.accessibility.AccessibilityNodeInfo? {
            if (node == null) return null
            if (find(node)) return node
            for (i in 0 until node.childCount) search(node.getChild(i))?.let { return it }
            return null
        }
        val deadline = android.os.SystemClock.uptimeMillis() + 15_000
        while (android.os.SystemClock.uptimeMillis() < deadline) {
            var found = search(automation.rootInActiveWindow)
            while (found != null && !found.isClickable) found = found.parent
            if (found?.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK) == true) return
            android.os.SystemClock.sleep(100)
        }
        throw AssertionError("System control not found; active package=${automation.rootInActiveWindow?.packageName}")
    }

    private fun sample(extension: String): ByteArray {
        val document = com.wangzan101.mika.core.document.Document("文件交付驗收", listOf(
            com.wangzan101.mika.core.document.Document.Section("table", columns = listOf("中文", "數值"),
                rows = listOf(listOf("完整內容", "123")))))
        return when (extension) {
            "pdf" -> com.wangzan101.mika.document.DocumentPdf.render(document)
            "html" -> document.html().toByteArray()
            else -> document.csv(null).toByteArray()
        }
    }

    private fun verifyPreview(extension: String) {
        val tag = when (extension) { "html" -> "viewer.html"; "pdf" -> "viewer.pdf"; else -> "viewer.text" }
        compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag(tag).assertIsDisplayed()
        // Preserve the synthetic sample preview for visual acceptance on each device/brand.
        android.os.SystemClock.sleep(1_000)
        val screenshot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        org.junit.Assert.assertNotNull("Preview screenshot unavailable", screenshot)
        File(context.cacheDir, "document-preview-$extension.png").outputStream().use {
            screenshot!!.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        screenshot!!.recycle()
    }

    @Test fun saveCopyWritesExactBytes() = saveCopy("csv")
    @Test fun saveHtmlWritesExactBytes() = saveCopy("html")
    @Test fun savePdfWritesExactBytes() = saveCopy("pdf")

    private fun saveCopy(extension: String) {
        val name = "document-save-${System.currentTimeMillis()}.$extension"
        val content = sample(extension)
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        show(Uri.fromFile(File(context.cacheDir, name).apply { writeBytes(content) }), name)
        verifyPreview(extension)
        try {
            compose.onNodeWithContentDescription(context.getString(com.wangzan101.mika.R.string.viewer_save_as)).performClick()
            clickSystemNode { node ->
                node.packageName?.toString()?.contains("documentsui") == true &&
                    (node.text?.toString()?.equals("SAVE", ignoreCase = true) == true || node.viewIdResourceName == "android:id/button1")
            }
            val deadline = android.os.SystemClock.uptimeMillis() + 10_000
            var bytes = byteArrayOf()
            while (android.os.SystemClock.uptimeMillis() < deadline) {
                bytes = android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    automation.executeShellCommand("cat /sdcard/Download/$name")
                ).use { it.readBytes() }
                if (bytes.contentEquals(content)) break
                android.os.SystemClock.sleep(200)
            }
            org.junit.Assert.assertArrayEquals(content, bytes)
            compose.onNodeWithText(name).assertIsDisplayed()
        } finally {
            automation.executeShellCommand("rm -f /sdcard/Download/$name").close()
            File(context.cacheDir, name).delete()
        }
    }

    @Test fun shareReceiverReadsGrantedAttachment() = shareAttachment("csv")
    @Test fun shareHtmlReceiverReadsGrantedAttachment() = shareAttachment("html")
    @Test fun sharePdfReceiverReadsGrantedAttachment() = shareAttachment("pdf")

    private fun shareAttachment(extension: String) = kotlinx.coroutines.runBlocking {
        val dir = File(context.cacheDir, "share-receiver-test").apply { mkdirs() }
        val content = sample(extension)
        val source = File(dir, "receiver.$extension").apply { writeBytes(content) }
        val card = com.wangzan101.mika.cap.sandbox.AndroidFdSys.gate.openRead(dir, source.name).use {
            com.wangzan101.mika.cap.sandbox.ShareExporter(context).export(it, source.name)
        }
        val uri = Uri.parse(card.uri)
        val received = java.util.concurrent.CountDownLatch(1)
        var result: android.content.Intent? = null
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(c: android.content.Context, intent: android.content.Intent) {
                result = intent
                received.countDown()
            }
        }
        androidx.core.content.ContextCompat.registerReceiver(context, receiver,
            android.content.IntentFilter("document.test.SHARE_RECEIVED"), androidx.core.content.ContextCompat.RECEIVER_EXPORTED)
        try {
            show(uri, card.name)
            compose.onNodeWithContentDescription(context.getString(com.wangzan101.mika.R.string.share)).performClick()
            clickSystemNode { it.text?.toString() == "Document test receiver" }
            org.junit.Assert.assertTrue("Receiver did not report", received.await(10, java.util.concurrent.TimeUnit.SECONDS))
            org.junit.Assert.assertNull(result?.getStringExtra("error"))
            org.junit.Assert.assertEquals(uri.toString(), result?.getStringExtra("uri"))
            org.junit.Assert.assertArrayEquals(content, result?.getByteArrayExtra("bytes"))
        } finally {
            context.unregisterReceiver(receiver)
            context.contentResolver.delete(uri, null, null)
            dir.deleteRecursively()
        }
    }

    @Test fun unsupportedFileFallsBackToOtherApps() {
        val uri = file("archive.zip", "PK")
        assertNull(FileViewer.kindOf(context, uri, "archive.zip"))
        show(uri, "archive.zip")
        compose.onNodeWithTag("viewer.unsupported").assertIsDisplayed()
        compose.onNodeWithText(context.getString(com.wangzan101.mika.R.string.viewer_open_elsewhere)).assertIsDisplayed()
    }
}
