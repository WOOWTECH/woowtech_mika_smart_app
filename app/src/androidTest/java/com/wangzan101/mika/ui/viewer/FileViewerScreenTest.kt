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

    @Test fun unsupportedFileFallsBackToOtherApps() {
        val uri = file("archive.zip", "PK")
        assertNull(FileViewer.kindOf(context, uri, "archive.zip"))
        show(uri, "archive.zip")
        compose.onNodeWithTag("viewer.unsupported").assertIsDisplayed()
        compose.onNodeWithText("用其他应用打开").assertIsDisplayed()
    }
}
