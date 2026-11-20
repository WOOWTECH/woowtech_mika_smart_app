package com.wangzan101.mika.document

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream

/** Independent of the browser's settings/cookies/bridges. No resource fetch or navigation is allowed. */
internal object StaticDocumentPreview {
    @Suppress("DEPRECATION")
    fun restrict(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = false
            javaScriptCanOpenWindowsAutomatically = false
            domStorageEnabled = false
            databaseEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            blockNetworkLoads = true
            blockNetworkImage = true
            loadsImagesAutomatically = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_NO_CACHE
            setSupportMultipleWindows(false)
        }
        view.setNetworkAvailable(false)
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = true
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean = true
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse = blocked()
            override fun shouldInterceptRequest(view: WebView?, url: String?): WebResourceResponse = blocked()
            private fun blocked() = WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
        }
    }
}
