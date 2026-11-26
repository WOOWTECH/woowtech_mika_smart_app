package com.wangzan101.mika.woowbot

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.webkit.*
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.theme.MikaTheme
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream

/** Hosts the unmodified mobile website. No JS interfaces, remote phone tools, or token extraction. */
class BotServiceActivity : ComponentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var webView: WebView? = null
    private val destroyed = java.util.Collections.newSetFromMap(java.util.WeakHashMap<WebView, Boolean>())
    private val owners = java.util.WeakHashMap<WebView, BotService>()
    private var activeService: BotService? = null
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var fileOwner: String? = null
    private var pendingDownload: Download? = null
    private var sessionHints: Job? = null
    private var status by mutableStateOf<Int?>(null)
    private var loading by mutableStateOf(false)
    private var reload by mutableIntStateOf(0)
    private var confirmLogout by mutableStateOf(false)
    private var confirmRemove by mutableStateOf(false)
    private var externalUrl by mutableStateOf<String?>(null)
    private var pairing by mutableStateOf<Pair<BotService, String>?>(null)
    private var scanning by mutableStateOf(false)
    private data class Download(val service: BotService, val url: String, val cookie: String?)

    private val filePicker = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val callback = fileCallback
        fileCallback = null
        val valid = result.resultCode == RESULT_OK && webView != null && activeService?.profileName == fileOwner &&
            activeService?.policy?.allows(webView?.url.orEmpty()) == true
        val uris = if (valid) WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
            ?.filter { it.scheme == "content" }?.take(16)?.toTypedArray() else null
        callback?.onReceiveValue(uris)
        fileOwner = null
    }
    private val saveDocument = registerForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val download = pendingDownload
        pendingDownload = null
        if (uri != null && download != null && current(download.service)) scope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    requireNotNull(contentResolver.openOutputStream(uri, "wt")).use {
                        BotWebTransfers.download(download.service, download.url, download.cookie, it)
                    }
                }.isSuccess
            }
            status = if (ok) R.string.bot_services_download_done else R.string.bot_services_download_failed
        }
    }

    override fun attachBaseContext(newBase: Context) = super.attachBaseContext(AppLanguage.wrap(newBase))
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA", "activityCreate restored=" + (savedInstanceState != null))
        if (!BuildConfig.WOOWTECHBOT_ENABLED) { finish(); return }
        setContent {
            MikaTheme {
                val registry = remember { runCatching { BotServices.registry(this) }.getOrNull() }
                if (registry == null) BotUnavailableScreen(R.string.bot_services_storage_error) { finish() }
                else ServiceContent(registry)
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun ServiceContent(registry: BotServiceRegistry) {
        val state by registry.state.collectAsState()
        val service = state.services.find { it.id == intent.getStringExtra(EXTRA_SERVICE) }
        val isolated = remember { BotServices.supportsIsolation() }
        LaunchedEffect(registry) { runCatching { BotServices.cleanRetired(registry) } }
        if (service == null) {
            BotUnavailableScreen(status ?: R.string.bot_services_missing) {
                startActivity(BotServicesActivity.intent(this)); finish()
            }
            return
        }
        BackHandler { val view = webView; if (view?.canGoBack() == true) view.goBack() else finish() }
        Scaffold(topBar = { TopAppBar(title = { Text(service.name, maxLines = 1) }, navigationIcon = {
            TextButton(onClick = { finish() }) { Text(stringResource(R.string.bot_services_local)) }
        }, actions = {
            TextButton(onClick = { startActivity(BotServicesActivity.intent(this@BotServiceActivity)); finish() }) {
                Text(stringResource(R.string.bot_services_switch))
            }
            var menu by remember { mutableStateOf(false) }
            TextButton(onClick = { menu = true }) { Text(stringResource(R.string.bot_services_more)) }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_scan_qr)) }, enabled = service.enabled && !scanning, onClick = {
                    menu = false
                    scanPairing(service)
                })
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_reload)) }, onClick = { menu = false; retry() })
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_share)) }, onClick = {
                    menu = false
                    // Share only the configured origin, never one-time sign-in links or private conversation IDs.
                    runCatching { startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, service.origin), getString(R.string.bot_services_share))) }
                })
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_disconnect)) }, onClick = {
                    menu = false
                    runCatching { registry.setEnabled(service.id, false); destroyWebView() }.onFailure { status = R.string.bot_services_action_error }
                })
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_logout)) }, onClick = { menu = false; confirmLogout = true })
                DropdownMenuItem(text = { Text(stringResource(R.string.bot_services_remove)) }, onClick = { menu = false; confirmRemove = true })
            }
        }) }) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
                Text(service.origin, Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.labelSmall)
                status?.let { message ->
                    Row(Modifier.padding(horizontal = 12.dp)) {
                        Text(stringResource(message), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { status = null; retry() }) { Text(stringResource(R.string.bot_services_retry)) }
                    }
                }
                if (!isolated) Text(stringResource(R.string.bot_services_unsupported), Modifier.padding(16.dp))
                else if (!service.enabled) {
                    Text(stringResource(R.string.bot_services_disconnected), Modifier.padding(16.dp))
                    Button(onClick = {
                        runCatching { registry.setEnabled(service.id, true) }.onFailure { status = R.string.bot_services_action_error }
                    }, modifier = Modifier.padding(16.dp)) { Text(stringResource(R.string.bot_services_connect)) }
                } else {
                    if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                    key(service.profileName, reload) {
                        val view = remember(service.profileName, reload) {
                            runCatching { createWebView(service) }.getOrElse { status = R.string.bot_services_load_failed; null }
                        }
                        if (view != null) {
                            AndroidView(factory = { view }, modifier = Modifier.fillMaxSize())
                            DisposableEffect(view) { onDispose { destroy(view) } }
                        }
                    }
                }
            }
        }
        if (confirmLogout || confirmRemove) AlertDialog(
            onDismissRequest = { confirmLogout = false; confirmRemove = false },
            title = { Text(stringResource(if (confirmRemove) R.string.bot_services_remove else R.string.bot_services_logout)) },
            text = { Text(stringResource(R.string.bot_services_logout_help)) },
            confirmButton = { TextButton(onClick = {
                val remove = confirmRemove
                confirmLogout = false; confirmRemove = false
                logout(registry, service, remove)
            }) { Text(stringResource(R.string.bot_services_confirm)) } },
            dismissButton = { TextButton(onClick = { confirmLogout = false; confirmRemove = false }) { Text(stringResource(R.string.bot_services_cancel)) } },
        )
        pairing?.let { (captured, url) -> AlertDialog(
            onDismissRequest = { pairing = null },
            title = { Text(stringResource(R.string.bot_services_pair_confirm)) },
            text = { Text(captured.name + "\n" + captured.origin) },
            confirmButton = { TextButton(onClick = {
                pairing = null
                if (current(captured) && activeService?.profileName == captured.profileName && webView != null) {
                    BotWebSessions.clear(captured.profileName)
                    webView?.loadUrl(url)
                } else status = R.string.bot_services_qr_failed
            }) { Text(stringResource(R.string.bot_services_connect)) } },
            dismissButton = { TextButton(onClick = { pairing = null }) { Text(stringResource(R.string.bot_services_cancel)) } },
        ) }
        externalUrl?.let { url -> AlertDialog(onDismissRequest = { externalUrl = null },
            title = { Text(stringResource(R.string.bot_services_external)) },
            text = { Text(runCatching { java.net.URI(url).host }.getOrNull().orEmpty()) },
            confirmButton = { TextButton(onClick = {
                externalUrl = null
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)) }
                    .onFailure { status = R.string.bot_services_load_failed }
            }) { Text(stringResource(R.string.bot_services_open)) } },
            dismissButton = { TextButton(onClick = { externalUrl = null }) { Text(stringResource(R.string.bot_services_cancel)) } },
        ) }
    }

    private fun scanPairing(service: BotService) {
        if (scanning || !current(service)) return
        scanning = true
        runCatching { BotQrScanner.create().scan(this, { raw ->
            scanning = false
            if (!isDestroyed && raw != null && current(service) && activeService?.profileName == service.profileName) {
                val validated = runCatching { BotPairingQr.validate(raw, service.policy) }.getOrNull()
                if (validated == null) status = R.string.bot_services_qr_invalid
                else pairing = service to validated
            }
        }, { scanning = false; if (!isDestroyed) status = R.string.bot_services_qr_failed }) }
            .onFailure { scanning = false; status = R.string.bot_services_qr_failed }
    }

    @Suppress("SetJavaScriptEnabled")
    private fun createWebView(service: BotService): WebView {
        check(BotServices.supportsIsolation())
        val requestedBot = intent.getStringExtra(EXTRA_BOT)
        val requestedThread = intent.getStringExtra(EXTRA_THREAD)
        val view = WebView(this)
        try {
            // Must be the first call on this WebView. Never fall back to the default cookie profile.
            WebViewCompat.setProfile(view, service.profileName)
            // WebView uses LayoutParams to resolve percentage-height HTML. The default
            // WRAP_CONTENT can collapse the document even when Compose measures a viewport.
            view.layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            )
            view.isSaveEnabled = false
            view.isSaveFromParentEnabled = false
            owners[view] = service
            activeService = service
            webView = view
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs = false
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                setGeolocationEnabled(false)
                mediaPlaybackRequiresUserGesture = true
                builtInZoomControls = true
                displayZoomControls = false
            }
            WebViewCompat.getProfile(view).cookieManager.setAcceptThirdPartyCookies(view, false)
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url.toString()
                    if (service.policy.allows(url)) return false
                    if (request.isForMainFrame && request.hasGesture() && safeExternal(url)) externalUrl = url
                    else if (request.isForMainFrame) status = R.string.bot_services_navigation_blocked
                    return true
                }
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS && service.policy.allows(request.url.toString()) &&
                        request.url.path?.matches(Regex("/api/bots/[^/]+/tasks/[^/]+")) == true) {
                        android.util.Log.i("BotRouteQA", "switchTask method=" + request.method +
                            " expectedTarget=" + (request.url.path == "/api/bots/$requestedBot/tasks/$requestedThread"))
                    }
                    // Web content keeps its ordinary HTTPS dependencies. No native privilege is granted to them.
                    val scheme = request.url.scheme
                    val allowed = if (request.isForMainFrame) service.policy.allows(request.url.toString())
                        else scheme == "https" || service.policy.allows(request.url.toString())
                    return if (allowed) null else WebResourceResponse("text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(byteArrayOf()))
                }
                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    loading = true
                    if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) {
                        val uri = runCatching { Uri.parse(url) }.getOrNull()
                        android.util.Log.i("BotRouteQA", "pageStart sameOrigin=" + service.policy.allows(url.orEmpty()) +
                            " targetQueryMatches=" + (requestedThread != null && uri?.getQueryParameter("thread") == requestedThread &&
                            uri?.getQueryParameter("bot") == requestedBot))
                    }
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    loading = false
                    if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) view.postDelayed({
                        if (webView === view && current(service) && service.policy.allows(view.url.orEmpty())) {
                            view.evaluateJavascript(BotViewportDiagnostics.script) { result ->
                                // Fixed geometry-only script: no URL, text, input, cookie or storage reads.
                                result.chunked(2800).forEachIndexed { index, chunk ->
                                    android.util.Log.i("BotViewportQA", "part=" + index + " " + chunk)
                                }
                            }
                        }
                    }, 2000)
                    if (service.policy.allows(url.orEmpty())) runCatching { BotServices.onSessionMayHaveChanged(service) }
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) { loading = false; status = R.string.bot_services_load_failed }
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    if (request.isForMainFrame && response.statusCode >= 500) { loading = false; status = R.string.bot_services_load_failed }
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel(); loading = false; status = R.string.bot_services_tls_error
                }
                override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) { handler.cancel() }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    destroy(view); status = R.string.bot_services_load_failed; return true
                }
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) { callback.invoke(origin, false, false) }
                override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                    if (!current(service) || !service.policy.allows(view.url.orEmpty())) return false
                    fileCallback?.onReceiveValue(null)
                    fileCallback = callback
                    fileOwner = service.profileName
                    val types = params.acceptTypes.filter { it.matches(Regex("[A-Za-z0-9.+*-]+/[A-Za-z0-9.+*-]+")) }.take(16)
                    val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                        .setType(types.singleOrNull() ?: "*/*")
                        .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == FileChooserParams.MODE_OPEN_MULTIPLE)
                    if (types.isNotEmpty()) picker.putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                    runCatching { filePicker.launch(picker) }.onFailure { fileCallback = null; callback.onReceiveValue(null) }
                    return true
                }
            }
            view.setDownloadListener { url, _, disposition, mime, _ ->
                if (!current(service) || !service.policy.allows(url) || url.length > BotOrigin.MAX_URL) {
                    status = R.string.bot_services_download_unsupported
                } else if (pendingDownload == null) {
                    pendingDownload = Download(service, url, WebViewCompat.getProfile(view).cookieManager.getCookie(url))
                    val filename = URLUtil.guessFileName(url, disposition, mime).substringAfterLast('/').substringAfterLast('\\')
                        .filterNot { it.isISOControl() }.take(120).ifBlank { "download" }
                    runCatching { saveDocument.launch(filename) }.onFailure { pendingDownload = null; status = R.string.bot_services_download_failed }
                }
            }
            val url = runCatching { BotWebTarget.url(service, intent.getStringExtra(EXTRA_BOT), intent.getStringExtra(EXTRA_THREAD)) }
                .getOrElse { status = R.string.bot_services_navigation_blocked; BotWebTarget.url(service) }
            val explicitTarget = intent.hasExtra(EXTRA_BOT) || intent.hasExtra(EXTRA_THREAD)
            val restored = !explicitTarget && BotWebSessions.restore(service, view)
            if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA",
                "initial explicitTarget=$explicitTarget restored=$restored threadPresent=" + (requestedThread != null))
            if (!restored) view.loadUrl(url)
            // Consume only after choosing the initial page so later recreation restores the current route.
            intent.removeExtra(EXTRA_BOT); intent.removeExtra(EXTRA_THREAD)
            return view
        } catch (error: Exception) { destroy(view); throw error }
    }

    private fun logout(registry: BotServiceRegistry, service: BotService, remove: Boolean) {
        if (!BotServices.supportsIsolation()) { status = R.string.bot_services_unsupported; return }
        runCatching {
            val profile = ProfileStore.getInstance().getOrCreateProfile(service.profileName)
            val cookie = profile.cookieManager.getCookie(service.origin + "/api/auth/logout")
            pairing = null
            runCatching { BotServices.beforeSessionCleared(service) }
            status = R.string.bot_services_logging_out
            if (remove) registry.remove(service.id) else registry.logout(service.id)
            BotWebSessions.clear(service.profileName)
            destroyWebView()
            pendingDownload = null
            runCatching { profile.cookieManager.removeAllCookies { profile.cookieManager.flush() } }
            runCatching { profile.webStorage.deleteAllData() }
            cleanupScope.launch {
                // Retire locally immediately, then DELETE with the captured old cookie before logout.
                // A failed DELETE keeps its ledger; logout still attempts server-side session revocation.
                val pushCleared = runCatching { BotServices.beforeRemoteLogout(service) }.getOrDefault(false)
                val revoked = BotWebTransfers.revoke(service, cookie)
                withContext(Dispatchers.Main.immediate) {
                    if (!isDestroyed) status = if (revoked && pushCleared) R.string.bot_services_logged_out else R.string.bot_services_logout_offline
                }
            }
        }.onFailure { status = R.string.bot_services_action_error }
    }
    private fun current(service: BotService): Boolean = runCatching {
        val latest = BotServices.registry(this).find(service.id)
        latest?.enabled == true && latest.profileName == service.profileName
    }.getOrDefault(false)
    private fun destroyWebView() { webView?.let(::destroy) }
    private fun retry() { webView?.reload() ?: run { reload++ } }
    private fun destroy(view: WebView) {
        if (!destroyed.add(view)) return
        owners.remove(view)?.let { service ->
            if (current(service)) runCatching { BotWebSessions.save(service, view) }
            else BotWebSessions.clear(service.profileName)
        }
        if (webView === view) {
            fileCallback?.onReceiveValue(null); fileCallback = null
            webView = null; activeService = null
        }
        (view.parent as? android.view.ViewGroup)?.removeView(view)
        view.stopLoading()
        view.webChromeClient = null
        view.destroy()
    }
    override fun onPause() { sessionHints?.cancel(); webView?.onPause(); super.onPause() }
    override fun onResume() {
        super.onResume(); webView?.onResume()
        // Pairing can complete inside the SPA without navigation. Parent may re-check /api/auth/session.
        sessionHints?.cancel()
        sessionHints = scope.launch {
            while (isActive) {
                activeService?.let { if (current(it)) runCatching { BotServices.onSessionMayHaveChanged(it) } }
                delay(15_000)
            }
        }
    }
    override fun onDestroy() {
        if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA", "activityDestroy configChange=$isChangingConfigurations")
        destroyWebView(); scope.cancel(); super.onDestroy()
    }

    companion object {
        private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private const val EXTRA_SERVICE = "woowbot.serviceId"
        private const val EXTRA_BOT = "woowbot.botId"
        private const val EXTRA_THREAD = "woowbot.threadId"
        fun intent(context: Context, serviceId: String, botId: String? = null, threadId: String? = null): Intent =
            Intent(context, BotServiceActivity::class.java).putExtra(EXTRA_SERVICE, serviceId)
                .apply {
                    if (botId != null) putExtra(EXTRA_BOT, botId)
                    if (threadId != null) putExtra(EXTRA_THREAD, threadId)
                }

        private fun safeExternal(url: String): Boolean = runCatching {
            val uri = java.net.URI(url)
            url.length <= BotOrigin.MAX_URL && uri.scheme == "https" && uri.host != null && uri.rawUserInfo == null
        }.getOrDefault(false)
    }
}
