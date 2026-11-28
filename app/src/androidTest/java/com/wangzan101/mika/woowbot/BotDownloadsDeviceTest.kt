package com.wangzan101.mika.woowbot

import android.provider.MediaStore
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.R
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Owner 2026-11-28: files the woowtechbot page makes itself (blob:) failed to download. A real WebView page creates the file
 * the way the website does (Blob → object URL → <a download> → revoked at once); the app reads it back in chunks and saves
 * it into the real Downloads folder. No network.
 */
@RunWith(AndroidJUnit4::class)
class BotDownloadsDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val store = BotDownloadStore(context)
    private val saved = mutableListOf<android.net.Uri>()
    private var view: WebView? = null

    @After fun tearDown() {
        saved.forEach(store::discard)
        instrumentation.runOnMainSync { view?.destroy() }
    }

    private fun page(): WebView {
        val loaded = CountDownLatch(1)
        instrumentation.runOnMainSync {
            view = WebView(context).apply {
                settings.javaScriptEnabled = true
                webViewClient = object : WebViewClient() { override fun onPageFinished(v: WebView, url: String?) { loaded.countDown() } }
                loadDataWithBaseURL("https://downloads-qa.invalid/", "<html><body>qa</body></html>", "text/html", "utf-8", null)
            }
        }
        assertTrue("page did not load", loaded.await(20, TimeUnit.SECONDS))
        return view!!
    }

    private fun js(view: WebView, script: String): String? {
        var result: String? = null
        val done = CountDownLatch(1)
        instrumentation.runOnMainSync { view.evaluateJavascript(script) { result = it; done.countDown() } }
        assertTrue(done.await(20, TimeUnit.SECONDS))
        return result
    }

    private fun expected(size: Int) = ByteArray(size) { ((it * 31 + 7) and 255).toByte() }

    @Test fun aRevokedObjectUrlThePageMadeIsReadAndSavedIntoDownloads() = runBlocking {
        val web = page()
        val hook = BotWorkspaceDownloads.script(context)
        assertEquals("true", js(web, hook))
        val size = BotBlobReader.CHUNK * 3 + 4321
        val url = BotBlobReader.text(js(web, """(function(){
            const bytes = new Uint8Array($size); for (let i = 0; i < $size; i++) bytes[i] = (i * 31 + 7) & 255;
            const href = URL.createObjectURL(new Blob([bytes], {type: 'application/octet-stream'}));
            const a = document.createElement('a'); a.href = href; a.download = '季報 Q4.xlsx'; document.body.append(a);
            try { a.click(); } finally { a.remove(); }
            setTimeout(() => URL.revokeObjectURL(href), 0);
            return href; })()"""))!!
        Thread.sleep(100)
        val reader = BotBlobReader(web, hook) { true }
        val info = reader.open(url)
        assertEquals(size.toLong(), info.size)
        assertEquals("季報 Q4.xlsx", info.name)
        val (name, type) = BotDownloadNames.resolve(info.name, null, null, info.type, { BotDownloadStore.systemType(it) }, { BotDownloadStore.systemExtension(it) })
        assertEquals("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", type)
        val uri = store.create(name, type).also(saved::add)
        var reported = 0L
        store.output(uri).use { out -> reader.copy(info, out) { reported = it } }
        reader.close()
        assertEquals(size.toLong(), reported)
        val stored = store.finish(uri, name)
        assertTrue(stored, stored.endsWith(".xlsx"))
        val back = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
        assertArrayEquals(expected(size), back)
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.RELATIVE_PATH), null, null, null)!!.use {
            assertTrue(it.moveToFirst())
            assertEquals(type, it.getString(0))
            assertTrue(it.getString(1), it.getString(1).startsWith("Download"))
        }
        // The system can open what was saved, with the right type.
        val open = store.openIntent(uri, type)
        assertEquals(type, open.type)
    }

    @Test fun anObjectUrlTheHookNeverSawAndThatIsGoneFails() = runBlocking {
        val web = page()
        val reader = BotBlobReader(web, BotWorkspaceDownloads.script(context)) { true }
        val error = runCatching { reader.open("blob:https://downloads-qa.invalid/00000000-0000-0000-0000-000000000000") }.exceptionOrNull()
        assertEquals(R.string.bot_services_download_blob_failed, (error as BotDownloadException).reason)
    }

    @Test fun aPageThatWentAwayStopsTheRead() = runBlocking {
        val web = page()
        val error = runCatching { BotBlobReader(web, BotWorkspaceDownloads.script(context)) { false }.open("blob:https://downloads-qa.invalid/x") }.exceptionOrNull()
        assertTrue(error is BotDownloadException)
    }

    @Test fun dataUrlsAndEveryCommonTypeSaveUnderTheirOwnNames() {
        listOf("相片.png" to "image/png", "clip.mp4" to "video/mp4", "voice.m4a" to "audio/mp4", "manual.pdf" to "application/pdf",
            "letter.docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "page.html" to "text/html", "bundle.zip" to "application/zip").forEach { (file, expectedType) ->
            val (name, type) = BotDownloadNames.resolve(file, null, null, "application/octet-stream", { BotDownloadStore.systemType(it) }, { BotDownloadStore.systemExtension(it) })
            assertEquals(file, expectedType, type)
            val uri = store.create(name, type).also(saved::add)
            store.output(uri).use { it.write(file.toByteArray()) }
            val stored = store.finish(uri, name)
            assertTrue("$file stored as $stored", stored.endsWith("." + file.substringAfterLast('.')))
        }
        val decoded = BotDataUrl.decode("data:text/csv;charset=utf-8,a%2Cb%0A%E4%B8%AD,2")
        val (name, type) = BotDownloadNames.resolve(null, null, null, decoded.type, { BotDownloadStore.systemType(it) }, { BotDownloadStore.systemExtension(it) })
        assertEquals("download.csv" to "text/csv", name to type)
        val uri = store.create(name, type).also(saved::add)
        store.output(uri).use { it.write(decoded.bytes) }
        store.finish(uri, name)
        assertEquals("a,b\n中,2", context.contentResolver.openInputStream(uri)!!.use { String(it.readBytes(), Charsets.UTF_8) })
    }

    @Test fun aFailedDownloadLeavesNothingBehind() {
        val uri = store.create("partial.zip", "application/zip")
        store.output(uri).use { it.write(ByteArray(10)) }
        store.discard(uri)
        val left = context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)?.use { it.count } ?: 0
        assertEquals(0, left)
    }
}
