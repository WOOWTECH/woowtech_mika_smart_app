package com.wangzan101.mika.woowbot

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewCompat
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Requires a provider with MULTI_PROFILE. Same origin, different profiles, no real service/network needed. */
class BotProfileIsolationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun main(action: () -> Unit) = instrumentation.runOnMainSync(action)
    private fun waitFor(latch: CountDownLatch) = assertTrue("WebView callback timed out", latch.await(15, TimeUnit.SECONDS))

    @Test fun explicitLanOriginAcceptsOnlyItsOwnRequestsOnAndroid() {
        val origin = BotOrigin.parse("http://192.168.2.10:18531", true)
        assertTrue(origin.value, origin.allows("http://192.168.2.10:18531/"))
        assertTrue(origin.allows("http://192.168.2.10:18531/api/auth/session"))
        assertFalse(origin.allows("http://192.168.2.10:18532/"))
    }

    @Test fun sameOriginCookiesAndLocalStorageNeverCrossProfiles() {
        var supported = false
        main { supported = BotServices.supportsIsolation() }
        assumeTrue("WebView provider has no MULTI_PROFILE support", supported)
        val views = mutableListOf<WebView>()
        val profileNames = listOf("woowbot_isolation_test_work", "woowbot_isolation_test_home")
        val origin = "https://woowbot-isolation.invalid/"
        try {
            repeat(2) { index ->
                val loaded = CountDownLatch(1)
                main {
                    val view = WebView(instrumentation.targetContext)
                    WebViewCompat.setProfile(view, profileNames[index])
                    views += view
                    view.settings.javaScriptEnabled = true
                    view.settings.domStorageEnabled = true
                    view.webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView, url: String) { loaded.countDown() }
                    }
                    view.loadDataWithBaseURL(origin, "<html><body>profile test</body></html>", "text/html", "UTF-8", null)
                }
                waitFor(loaded)
            }
            fun js(view: WebView, script: String): String? {
                var result: String? = null
                val done = CountDownLatch(1)
                main { view.evaluateJavascript(script) { result = it; done.countDown() } }
                waitFor(done)
                return result
            }
            val cookieReady = CountDownLatch(1)
            main { WebViewCompat.getProfile(views[0]).cookieManager.setCookie(origin, "session=work; Secure; Path=/") { cookieReady.countDown() } }
            waitFor(cookieReady)
            js(views[0], "localStorage.setItem('draft','work draft')")
            assertEquals("\"work draft\"", js(views[0], "localStorage.getItem('draft')"))
            assertEquals("null", js(views[1], "localStorage.getItem('draft')"))
            main {
                assertTrue(WebViewCompat.getProfile(views[0]).cookieManager.getCookie(origin).orEmpty().contains("session=work"))
                assertFalse(WebViewCompat.getProfile(views[1]).cookieManager.getCookie(origin).orEmpty().contains("session=work"))
            }
            // Switching away destroys the view; opening the same service keeps its own saved web storage.
            val reopened = CountDownLatch(1)
            main {
                views[0].destroy()
                val replacement = WebView(instrumentation.targetContext)
                WebViewCompat.setProfile(replacement, profileNames[0])
                views[0] = replacement
                replacement.settings.javaScriptEnabled = true
                replacement.settings.domStorageEnabled = true
                replacement.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String) { reopened.countDown() }
                }
                replacement.loadDataWithBaseURL(origin, "<html><body>reopened</body></html>", "text/html", "UTF-8", null)
            }
            waitFor(reopened)
            assertEquals("\"work draft\"", js(views[0], "localStorage.getItem('draft')"))
            js(views[1], "localStorage.setItem('draft','home draft')")
            val homeCookieReady = CountDownLatch(1)
            main { WebViewCompat.getProfile(views[1]).cookieManager.setCookie(origin, "session=home; Secure; Path=/") { homeCookieReady.countDown() } }
            waitFor(homeCookieReady)
            val cleared = CountDownLatch(1)
            main { WebViewCompat.getProfile(views[0]).cookieManager.removeAllCookies { cleared.countDown() } }
            waitFor(cleared)
            js(views[0], "localStorage.clear()")
            assertEquals("\"home draft\"", js(views[1], "localStorage.getItem('draft')"))
            assertEquals("null", js(views[0], "localStorage.getItem('draft')"))
            main { assertTrue(WebViewCompat.getProfile(views[1]).cookieManager.getCookie(origin).orEmpty().contains("session=home")) }
        } finally {
            main {
                views.forEach {
                    WebViewCompat.getProfile(it).cookieManager.removeAllCookies(null)
                    WebViewCompat.getProfile(it).webStorage.deleteAllData()
                    it.destroy()
                }
                // Loaded profiles cannot be deleted in this process; isolated test names never hold real credentials.
            }
        }
    }
}
