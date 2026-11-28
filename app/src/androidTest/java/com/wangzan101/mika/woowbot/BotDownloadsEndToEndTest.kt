package com.wangzan101.mika.woowbot

import android.content.ContentUris
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Owner 2026-11-28: every file type downloads. The real service screen opens tools/woowtechbot-ui/downloads-fixture.py
 * (run on the emulator's host, reached as http://10.0.2.2 with the trusted-LAN option) and each way of downloading is
 * triggered on the page: the website's own POST → Blob → revoke, a direct link, an attachment header, a redirect, a data:
 * URL, a Chinese name. Each file must land in Downloads byte for byte under its own name, and a download without a recent
 * tap is blocked. Skipped when the runner gives no fixture address (-e downloadsFixture).
 */
@RunWith(AndroidJUnit4::class)
class BotDownloadsEndToEndTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val fixture: String? = InstrumentationRegistry.getArguments().getString("downloadsFixture")
    private lateinit var service: BotService
    private var scenario: ActivityScenario<BotServiceActivity>? = null
    private val started = System.currentTimeMillis() / 1000 - 5
    private val saved = mutableListOf<Uri>()

    @Before fun setUp() {
        assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)
        assumeTrue("no downloads fixture given", fixture != null)
        var supported = false
        instrumentation.runOnMainSync { supported = BotServices.supportsIsolation() }
        assumeTrue("WebView provider has no MULTI_PROFILE support", supported)
        service = BotServices.registry(context).add("Downloads QA", fixture!!, allowHttpLan = true)
    }

    @After fun tearDown() {
        scenario?.close()
        if (::service.isInitialized) runCatching { BotServices.registry(context).remove(service.id) }
        saved.forEach { runCatching { context.contentResolver.delete(it, null, null) } }
    }

    private fun webView(activity: BotServiceActivity): WebView? {
        fun find(view: View): WebView? = when (view) {
            is WebView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        return find(activity.window.decorView)
    }

    private fun js(web: WebView, script: String): String? {
        var result: String? = null
        val done = CountDownLatch(1)
        instrumentation.runOnMainSync { web.evaluateJavascript(script) { result = it; done.countDown() } }
        assertTrue(done.await(20, TimeUnit.SECONDS))
        return result
    }

    /** A person's tap on the page (the app takes page downloads only shortly after one). */
    private fun tap(web: WebView) {
        val at = IntArray(2)
        instrumentation.runOnMainSync { web.getLocationOnScreen(at) }
        val x = at[0] + 20f; val y = at[1] + 20f
        val now = SystemClock.uptimeMillis()
        instrumentation.uiAutomation.injectInputEvent(MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0), true)
        instrumentation.uiAutomation.injectInputEvent(MotionEvent.obtain(now, now + 50, MotionEvent.ACTION_UP, x, y, 0), true)
        SystemClock.sleep(300)
    }

    private fun original(name: String): ByteArray =
        (URL("$fixture/files/" + Uri.encode(name)).openConnection() as HttpURLConnection).run { inputStream.use { it.readBytes() } }

    /** The newest Downloads item of this test whose name starts with [stem] and ends with [extension]: uri, type, name. */
    private fun awaitSaved(stem: String, extension: String, timeout: Long = 30_000): Triple<Uri, String, String> {
        val end = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < end) {
            context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE),
                "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.DATE_ADDED} >= ? AND ${MediaStore.MediaColumns.IS_PENDING} = 0",
                arrayOf("$stem%.$extension", started.toString()), "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use {
                while (it.moveToNext()) {
                    val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, it.getLong(0))
                    if (uri !in saved) { saved.add(uri); return Triple(uri, it.getString(2), it.getString(1)) }
                }
            }
            SystemClock.sleep(300)
        }
        fail("$stem.$extension was not saved into Downloads")
        error("unreachable")
    }

    private fun awaitText(text: String, timeout: Long = 20_000) =
        compose.waitUntil(timeout) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun everyWayOfDownloadingSavesTheFileIntoDownloads() {
        scenario = ActivityScenario.launch(BotServiceActivity.intent(context, service.id))
        var activity: BotServiceActivity? = null
        scenario!!.onActivity { activity = it }
        val screen = activity!!
        var web: WebView? = null
        val end = SystemClock.elapsedRealtime() + 30_000
        while (SystemClock.elapsedRealtime() < end) {
            instrumentation.runOnMainSync { web = webView(screen) }
            if (web != null && BotBlobReader.text(js(web!!, "document.title")) == "下載測試") break
            SystemClock.sleep(500)
        }
        val page = requireNotNull(web) { "service page did not open" }
        assertEquals("下載測試", BotBlobReader.text(js(page, "document.title")))

        // 1. A download the page starts without a recent tap is blocked.
        js(page, "site('sample.txt')")
        awaitText(screen.getString(R.string.bot_services_download_not_tapped))
        compose.onNodeWithText(screen.getString(R.string.bot_services_download_dismiss)).performClick()

        // 2. Each way, after a tap: the website's own (POST → Blob → revoked at once), direct, attachment, redirect, data:.
        val cases = listOf(
            Triple("site('sample.xlsx')", "sample" to "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            Triple("document.querySelector('a[href=\"/files/sample.pdf\"]').click()", "sample" to "pdf", "application/pdf"),
            Triple("document.querySelector('a[href=\"/attach/sample.docx\"]').click()", "sample" to "docx",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
            Triple("document.querySelector('a[href=\"/redirect/sample.zip\"]').click()", "sample" to "zip", "application/zip"),
            Triple("site('sample.html')", "sample" to "html", "text/html"),
            Triple("site('sample.png')", "sample" to "png", "image/png"),
            Triple("site('中文檔名 測試.pdf')", "中文檔名 測試" to "pdf", "application/pdf"),
        )
        for ((script, file, type) in cases) {
            tap(page)
            js(page, script)
            val (uri, savedType, savedName) = awaitSaved(file.first, file.second)
            assertEquals(script, type, savedType)
            assertEquals(script, "${file.first}.${file.second}", savedName)
            val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            assertArrayEquals(script, original("${file.first}.${file.second}"), bytes)
            // The row names the saved file and offers to open it; the next download starts after this one ended.
            awaitText(screen.getString(R.string.bot_services_download_saved, savedName))
            SystemClock.sleep(300)
        }
        tap(page)
        js(page, "document.querySelector('a[download=\"data-表格.csv\"]').click()")
        val (csv, csvType, csvName) = awaitSaved("data-表格", "csv")
        assertEquals("text/csv", csvType)
        assertEquals("data-表格.csv", csvName)
        assertEquals("項目,數量\n蘋果,3\n", context.contentResolver.openInputStream(csv)!!.use { String(it.readBytes(), Charsets.UTF_8) })

        // Another site's link never reaches the download step on Android: the WebView asks before it navigates, so the
        // service screen offers to open it in the browser instead (covered by the external-link dialog).
    }
}
