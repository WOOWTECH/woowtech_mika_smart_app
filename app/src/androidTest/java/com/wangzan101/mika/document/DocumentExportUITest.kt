package com.wangzan101.mika.document

import android.os.SystemClock
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.CloseComposeActivity
import com.wangzan101.mika.R
import com.wangzan101.mika.core.document.DocumentFormat
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.ui.viewer.FileViewerActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Native CSV dialog generation and FileViewer preview; no result/status mocks. */
@RunWith(AndroidJUnit4::class)
class DocumentExportUITest {
    @get:Rule val compose = createAndroidComposeRule<DocumentTestActivity>()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = CloseComposeActivity(compose)

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var scope: CoroutineScope
    private lateinit var session: DocumentExportSession
    private var ownedFile: File? = null
    private var viewer: FileViewerActivity? = null
    private val title = "DOC_UI_${UUID.randomUUID().toString().take(8)}"

    @Test fun csvDialogGeneratesAndOpensRealPreview() {
        try {
            listOf("ui-generated.png", "ui-preview.png", "ui-failure.png", "ui.csv").forEach {
                File(context.filesDir, "document-test-evidence/$it").delete()
            }
        // Real generation performs retention. Never let this fixture prune prior shares.
        val root = File(context.cacheDir, "attach/documents")
        assertTrue("Use a disposable test installation with an empty document cache",
            !root.exists() || root.listFiles()?.isEmpty() == true)
        onMain {
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            session = DocumentExportSession(scope, SOURCE, title, "zh-Hant", DocumentFormat.HTML)
        }
        val host = compose.activity
        compose.setContent {
            MikaTheme(dark = false, reduceMotion = true) {
                DocumentExportDialog(session) { host.finish() }
            }
        }
        compose.onNodeWithTag("document-export").assertIsDisplayed()
        compose.onNodeWithTag("document-csv")
            .performScrollTo().assertIsEnabled().performClick().assertIsSelected()
        compose.onNodeWithTag("document-generate")
            .performScrollTo().assertIsEnabled().performClick()

        val deadline = SystemClock.uptimeMillis() + 15_000
        while (onMain { session.busy } && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(50)
        onMain { assertTrue("Real generation timed out", !session.busy) }
        compose.onNodeWithTag("document-status").performScrollTo()
            .assertTextEquals(host.getString(R.string.document_ready))
        val document = requireNotNull(onMain { session.generated }) { "Generate must create a real artifact" }
        ownedFile = document.file
        assertEquals(DocumentFormat.CSV, document.format)
        assertEquals("$title.csv", document.file.name)
        assertTrue(document.file.isFile)
        assertArrayEquals(EXPECTED_BYTES.toByteArray(Charsets.UTF_8), document.file.readBytes())
        screenshot("ui-generated.png")
        document.file.copyTo(File(context.filesDir, "document-test-evidence/ui.csv"), overwrite = true)

        // Non-blocking observer: allow the real activity and existing URI plumbing.
        val monitor = instrumentation.addMonitor(FileViewerActivity::class.java.name, null, false)
        try {
            compose.onNodeWithTag("document-preview")
                .performScrollTo().assertIsEnabled().performClick()
            val actualViewer = requireNotNull(
                instrumentation.waitForMonitorWithTimeout(monitor, 15_000) as? FileViewerActivity,
            ) { "Preview button must open the real FileViewerActivity" }
            viewer = actualViewer
            onMain {
                assertEquals(document.uri, actualViewer.intent.data)
                assertEquals(document.file.name, actualViewer.intent.getStringExtra(FileViewerActivity.EXTRA_NAME))
            }
            compose.waitUntil(15_000) {
                compose.onAllNodesWithTag("viewer.text").fetchSemanticsNodes().size == 1
            }
            compose.onNodeWithTag("viewer.text").assertIsDisplayed()
            compose.onNodeWithText(EXPECTED_PREVIEW).assertIsDisplayed()
            screenshot("ui-preview.png")
        } finally {
            instrumentation.removeMonitor(monitor)
        }
        } catch (failure: Throwable) {
            runCatching { screenshot("ui-failure.png") }
            throw failure
        }
    }

    private fun screenshot(name: String) {
        val root = File(context.filesDir, "document-test-evidence").apply { mkdirs() }
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(root, name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) } }
        finally { bitmap.recycle() }
    }

    @After fun releaseOnlyThisFixture() {
        onMain {
            viewer?.let { if (!it.isDestroyed) it.finish() }
            if (::scope.isInitialized) scope.cancel()
            if (ownedFile == null && ::session.isInitialized) ownedFile = session.generated?.file
        }
        ownedFile?.let { file ->
            val directory = requireNotNull(file.parentFile)
            assertEquals(File(context.cacheDir, "attach/documents").canonicalFile, directory.parentFile?.canonicalFile)
            assertEquals("$title.csv", file.name)
            assertTrue("Could not delete this fixture CSV", !file.exists() || file.delete())
            assertTrue("Could not delete this fixture's empty UUID directory", !directory.exists() || directory.delete())
        }
    }

    private fun <T> onMain(block: () -> T): T {
        var outcome: Result<T>? = null
        instrumentation.runOnMainSync { outcome = runCatching(block) }
        return requireNotNull(outcome).getOrThrow()
    }

    companion object {
        private const val SOURCE = "| key | value |\n| --- | --- |\n| DOC_UI_ROW | local-only |"
        private const val EXPECTED_BYTES = "\uFEFF\"key\",\"value\"\r\n\"DOC_UI_ROW\",\"local-only\"\r\n"
        // FileViewer removes the BOM and displays lines joined with LF. Exported
        // bytes above are separately compared exactly, including BOM and CRLF.
        private const val EXPECTED_PREVIEW = "\"key\",\"value\"\n\"DOC_UI_ROW\",\"local-only\"\n"
    }
}
