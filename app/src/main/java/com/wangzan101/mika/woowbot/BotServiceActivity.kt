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
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.wangzan101.mika.chat.BotUiProfile
import com.wangzan101.mika.ui.BotUiAvatar
import com.wangzan101.mika.ui.BotUiRoundButton
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wangzan101.mika.ui.BotUiCard
import com.wangzan101.mika.ui.BotUiCardDivider
import com.wangzan101.mika.ui.BotUiSettingsRow
import com.wangzan101.mika.ui.BotUiSheet
import com.wangzan101.mika.ui.NoDialogDim
import com.wangzan101.mika.ui.components.MikaDialog
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.appearanceDark
import com.wangzan101.mika.ui.theme.systemBarsFor
import com.wangzan101.mika.woowbot.push.BotPushSettingsActivity
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.AppLanguage
import com.wangzan101.mika.ui.theme.MikaTheme
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream
import kotlin.coroutines.resume

/** Hosts the complete mobile website with two bounded, presentation-only host actions. No native JS interface. */
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
    private var integrated by mutableStateOf(false)
    /**
     * Owner 2026-11-27: no connecting screen and no bare bar with the address while a service opens; a transition page covers
     * them. Opening or switching to a service lands on its bot list ([landOnList]): the phone website always starts on the
     * selected bot's chat with its list closed, so the list is opened once with the site's own button. A push target, a reload
     * and a recreated activity keep the page the website shows.
     */
    private var revealed by mutableStateOf(false)
    private var landOnList = true
    private var transitionText by mutableIntStateOf(R.string.bot_services_opening_list)
    private var transition by mutableIntStateOf(0)
    /** Main-frame page starts in the shown web view; a transition only reads pages started after [transitionFrom]. */
    private var pageStarts = 0
    private var transitionFrom = 0
    private var finishedAt = 0L
    private var touchedAt = 0L
    private var darkAppearance = false
    private var choosing by mutableStateOf(false)
    private var managing by mutableStateOf(false)
    private var selectedService by mutableStateOf<String?>(null)
    private val parked = LinkedHashMap<String, WebView>()
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
        selectedService = intent.getStringExtra(EXTRA_SERVICE)
        // Reopening the app returns to the page the user left (BotResumeEntry): the website shows its last bot, and in the
        // same process the saved page itself.
        val resuming = intent.getBooleanExtra(EXTRA_RESUME, false)
        landOnList = savedInstanceState == null && !resuming && !intent.hasExtra(EXTRA_BOT) && !intent.hasExtra(EXTRA_THREAD)
        if (resuming) transitionText = R.string.bot_services_resuming
        else if (!landOnList) transitionText = R.string.bot_services_opening_chat
        managing = intent.getBooleanExtra(EXTRA_MANAGE, false)
        if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA", "activityCreate restored=" + (savedInstanceState != null))
        if (!BuildConfig.WOOWTECHBOT_ENABLED) { finish(); return }
        setContent {
            val dark = appearanceDark()
            SideEffect { darkAppearance = dark; systemBarsFor(dark) }
            MikaTheme(dark = dark) {
                LaunchedEffect(dark) { webView?.let(::applyAppearance) }
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
        val service = state.services.find { it.id == selectedService }
        val isolated = remember { BotServices.supportsIsolation() }
        LaunchedEffect(registry) { runCatching { BotServices.cleanRetired(registry) } }
        if (service == null) {
            BotUnavailableScreen(status ?: R.string.bot_services_missing) {
                startActivity(BotServicesActivity.intent(this)); finish()
            }
            return
        }
        BackHandler { val view = webView; if (revealed && view?.canGoBack() == true) view.goBack() else finish() }
        // While the transition page is up the page is asked every 0.2 s what it shows (structure only). It goes when the bot list
        // is open, or the page is a sign-in page or not a woowtechbot workspace, or after 20 s. For 2.5 s after that the list is
        // opened again if the website closes it by itself (until the first touch). After a sign-in page, or a workspace still
        // starting or connecting at 20 s, the list is still opened once, when the workspace appears.
        LaunchedEffect(service.profileName, transition) {
            // A newer transition (switch, reload) replaces this one; an answer that arrives after that changes nothing.
            val round = transition
            val started = System.currentTimeMillis()
            var openSeen = 0
            var emptySince = 0L
            var settleFrom = 0L
            var last: String? = null
            while (!revealed || landOnList) {
                delay(if (!revealed || settleFrom != 0L) 200L else 1_000L)
                if (transition != round) break
                if (!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) continue
                val now = System.currentTimeMillis()
                if (settleFrom != 0L && (touchedAt > settleFrom || now - settleFrom > 2_500L)) { landOnList = false; break }
                if (status != null || now - started > 600_000L) { landOnList = false; revealed = true; break }
                if (!revealed && now - started > 20_000L) { revealed = true; if (last != "boot" && last != "connecting") landOnList = false }
                val view = webView ?: continue
                if (pageStarts <= transitionFrom) continue
                applyAppearance(view)
                val shown = evaluate(view, BotWorkspaceList.script(this@BotServiceActivity, open = landOnList))
                if (transition != round) break
                if (shown != null) last = shown
                if (shown != "app") emptySince = 0L
                if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA", "transition shown=$shown ms=" + (now - started) +
                    " list=$landOnList revealed=$revealed integrated=$integrated")
                when (shown) {
                    "form" -> revealed = true
                    "none" -> if (finishedAt != 0L && now - finishedAt > 4_000L) { landOnList = false; revealed = true }
                    // The app without bots in its list and without its loading screen (an onboarding page, say) shows after 5 s.
                    "app" -> if (emptySince == 0L) emptySince = now
                        else if (now - emptySince > 5_000L) { landOnList = false; revealed = true }
                    "wide", "closed" -> { landOnList = false; revealed = true }
                    "opening" -> openSeen = 0
                    "open" -> if (!landOnList) revealed = true
                        else if (++openSeen >= 2 && settleFrom == 0L) { revealed = true; settleFrom = now }
                }
            }
        }
        // A site that is not a woowtechbot workspace keeps a bar of its own, in the app's style: services, name, more.
        // Without a page (unsupported device, disconnected service) there is nothing to wait for, so the bar shows at once.
        val chrome = (revealed || !isolated || !service.enabled) && !integrated
        Scaffold(containerColor = MikaTheme.colors.bg, topBar = {
            if (chrome) Row(Modifier.fillMaxWidth().statusBarsPadding().height(64.dp).padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                BotUiRoundButton(MikaIcons.WorkspaceSwitch, stringResource(R.string.bot_services_switch)) { choosing = true }
                Column(Modifier.weight(1f).padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(service.name, color = MikaTheme.colors.ink, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(service.origin, color = MikaTheme.colors.ink3, fontSize = 12.sp, lineHeight = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                BotUiRoundButton(MikaIcons.More, stringResource(R.string.bot_services_more)) { managing = true }
            }
        }) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
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
                        startTransition(list = true, R.string.bot_services_opening_list)
                        runCatching { registry.setEnabled(service.id, true) }.onFailure { status = R.string.bot_services_action_error }
                    }, modifier = Modifier.padding(16.dp)) { Text(stringResource(R.string.bot_services_connect)) }
                } else {
                    if (loading && revealed) LinearProgressIndicator(Modifier.fillMaxWidth())
                    // Notes the first touch (without taking it) so the list is never reopened against the user.
                    Box(Modifier.fillMaxSize().pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) {
                                if (awaitPointerEvent(PointerEventPass.Initial).type == PointerEventType.Press) touchedAt = System.currentTimeMillis()
                            }
                        }
                    }) {
                    key(service.profileName, reload) {
                        val view = remember(service.profileName, reload) {
                            runCatching {
                                parked.remove(service.profileName)?.also {
                                    webView = it; activeService = service; it.onResume()
                                    if (landOnList) { transitionFrom = pageStarts; it.loadUrl(BotWebTarget.url(service)) } else applyAppearance(it)
                                }
                                    ?: createWebView(service)
                            }.getOrElse { status = R.string.bot_services_load_failed; null }
                        }
                        if (view != null) {
                            AndroidView(factory = { view }, modifier = Modifier.fillMaxSize())
                            DisposableEffect(view) { onDispose {
                                if (current(service) && !isFinishing && !isDestroyed && !destroyed.contains(view)) {
                                    (view.parent as? android.view.ViewGroup)?.removeView(view)
                                    view.onPause()
                                    parked[service.profileName] = view
                                } else destroy(view)
                            } }
                        }
                    }
                    ServiceTransitionOverlay(!revealed, service.name, stringResource(transitionText))
                    }
                }
            }
        }
        // Both sheets draw their own scrim and motion, so the dialog windows neither dim nor close themselves on Back.
        val sheetWindow = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)
        if (choosing) Dialog(onDismissRequest = { choosing = false }, properties = sheetWindow) {
            NoDialogDim()
            BotServicesScreen(registry, onLocal = { choosing = false; finish() }, onOpen = { id ->
                choosing = false
                if (id != selectedService) {
                    selectedService = id; intent = intent(this, id); integrated = false; status = null
                    startTransition(list = true, R.string.bot_services_opening_list)
                }
            }, onClose = { choosing = false }, selectedId = service.id, onManage = { id ->
                choosing = false
                if (id != selectedService) {
                    selectedService = id; intent = intent(this, id); integrated = false; status = null
                    startTransition(list = true, R.string.bot_services_opening_list)
                }
                managing = true
            })
        }
        if (managing) Dialog(onDismissRequest = { managing = false }, properties = sheetWindow) {
            NoDialogDim()
            BotUiSheet(service.name, onDismissRequest = { managing = false }) {
                val c = MikaTheme.colors
                Text(service.origin, Modifier.padding(horizontal = 8.dp), color = c.ink2, fontSize = 13.sp, lineHeight = 18.sp)
                BotUiCard {
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_scan_qr), icon = MikaIcons.Camera,
                        enabled = service.enabled && !scanning, onClick = { managing = false; scanPairing(service) })
                    BotUiCardDivider()
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_reload), icon = MikaIcons.Refresh, onClick = { managing = false; retry() })
                    BotUiCardDivider()
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_share), icon = MikaIcons.Share, onClick = {
                        managing = false
                        runCatching { startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, service.origin), getString(R.string.bot_services_share))) }
                    })
                    BotUiCardDivider()
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_disconnect), icon = MikaIcons.Link,
                        onClick = { managing = false; registry.setEnabled(service.id, false); destroyWebView() })
                    BotUiCardDivider()
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_logout), icon = MikaIcons.Lock, onClick = { managing = false; confirmLogout = true })
                    BotUiCardDivider()
                    BotUiSettingsRow(title = stringResource(R.string.bot_services_remove), icon = MikaIcons.Trash, destructive = true,
                        onClick = { managing = false; confirmRemove = true })
                }
            }
        }
        // Same dialog family as the rest of the app: popover surface, ink pill buttons, removal in red.
        if (confirmLogout || confirmRemove) MikaDialog(
            onDismissRequest = { confirmLogout = false; confirmRemove = false },
            title = { Text(stringResource(if (confirmRemove) R.string.bot_services_remove else R.string.bot_services_logout)) },
            text = { Text(stringResource(R.string.bot_services_logout_help)) },
            confirmButton = { TextButton(onClick = {
                val remove = confirmRemove
                confirmLogout = false; confirmRemove = false
                logout(registry, service, remove)
            }) { Text(stringResource(R.string.bot_services_confirm), color = if (confirmRemove) MikaTheme.colors.bad else Color.Unspecified) } },
            dismissButton = { TextButton(onClick = { confirmLogout = false; confirmRemove = false }) { Text(stringResource(R.string.bot_services_cancel)) } },
        )
        pairing?.let { (captured, url) -> MikaDialog(
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
        externalUrl?.let { url -> MikaDialog(onDismissRequest = { externalUrl = null },
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

    /** Runs a fixed script on the service's own shown page; null when the page changed or went away meanwhile. */
    private suspend fun evaluate(view: WebView, script: String): String? {
        val owner = owners[view] ?: return null
        if (destroyed.contains(view) || !current(owner) || !owner.policy.allows(view.url.orEmpty())) return null
        val page = pageStarts
        val result = withTimeoutOrNull(2_000L) {
            suspendCancellableCoroutine<String> { done -> view.evaluateJavascript(script) { if (done.isActive) done.resume(it) } }
        }
        return result?.takeIf { webView === view && pageStarts == page }?.removeSurrounding("\"")
    }

    private fun startTransition(list: Boolean, text: Int) {
        landOnList = list; transitionText = text; transitionFrom = pageStarts; revealed = false; transition++
    }

    private fun applyAppearance(view: WebView) {
        val owner = owners[view] ?: return
        if (destroyed.contains(view) || !current(owner) || !owner.policy.allows(view.url.orEmpty())) return
        view.setBackgroundColor(if (darkAppearance) 0xff121212.toInt() else 0xfffcfcfc.toInt())
        val page = pageStarts
        view.evaluateJavascript(BotWorkspaceAppearance.script(this, darkAppearance)) { result ->
            if (webView === view && pageStarts == page) integrated = result == "true"
        }
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
            // The page colour from the first frame, not white until the page has loaded.
            view.setBackgroundColor(if (darkAppearance) 0xff121212.toInt() else 0xfffcfcfc.toInt())
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
                    val hostAction = BotWorkspaceAppearance.action(url, request.isForMainFrame, request.hasGesture(),
                        webView === view && current(service) && service.policy.allows(view.url.orEmpty()))
                    if (hostAction != null) {
                        if (hostAction == "services") choosing = true
                        else startActivity(BotPushSettingsActivity.intent(this@BotServiceActivity))
                        return true
                    }
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
                    if (webView === view) {
                        pageStarts++; loading = true; integrated = false; finishedAt = 0L
                        // A sign-in page was shown; the next page is the workspace, whose list opens behind the transition page.
                        if (revealed && landOnList) {
                            transitionFrom = pageStarts - 1; transitionText = R.string.bot_services_opening_list; revealed = false; transition++
                        }
                    }
                    if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) {
                        val uri = runCatching { Uri.parse(url) }.getOrNull()
                        android.util.Log.i("BotRouteQA", "pageStart sameOrigin=" + service.policy.allows(url.orEmpty()) +
                            " targetQueryMatches=" + (requestedThread != null && uri?.getQueryParameter("thread") == requestedThread &&
                            uri?.getQueryParameter("bot") == requestedBot))
                    }
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    if (webView === view) { loading = false; finishedAt = System.currentTimeMillis() }
                    applyAppearance(view)
                    for (delay in listOf(250L, 1000L, 3000L)) view.postDelayed({
                        if (webView === view && !isDestroyed) applyAppearance(view)
                    }, delay)
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
            transitionFrom = pageStarts
            val restored = !explicitTarget && !landOnList && BotWebSessions.restore(service, view)
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
    private fun retry() {
        startTransition(list = false, R.string.bot_services_reloading)
        webView?.reload() ?: run { reload++ }
    }
    private fun destroy(view: WebView) {
        if (!destroyed.add(view)) return
        parked.entries.removeAll { it.value === view }
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
        super.onResume(); webView?.onResume(); webView?.let(::applyAppearance)
        // Pairing can complete inside the SPA without navigation. Parent may re-check /api/auth/session.
        sessionHints?.cancel()
        sessionHints = scope.launch {
            while (isActive) {
                activeService?.let { if (current(it)) runCatching { BotServices.onSessionMayHaveChanged(it) } }
                delay(15_000)
            }
        }
    }
    override fun onStart() { super.onStart(); BotResumeEntry.returned(this) }
    override fun onStop() {
        // Left for the home screen or another app, not closed: opening the app again comes back here.
        if (!isFinishing && !isChangingConfigurations) selectedService?.let { BotResumeEntry.left(this, it) }
        super.onStop()
    }
    override fun onDestroy() {
        if (BuildConfig.BOT_VIEWPORT_DIAGNOSTICS) android.util.Log.i("BotRouteQA", "activityDestroy configChange=$isChangingConfigurations")
        parked.values.toList().forEach(::destroy); destroyWebView(); scope.cancel(); super.onDestroy()
    }

    companion object {
        private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        const val EXTRA_MANAGE = "woowbot.manage"
        private const val EXTRA_SERVICE = "woowbot.serviceId"
        private const val EXTRA_BOT = "woowbot.botId"
        private const val EXTRA_THREAD = "woowbot.threadId"
        private const val EXTRA_RESUME = "woowbot.resume"
        fun resumeIntent(context: Context, serviceId: String): Intent = intent(context, serviceId).putExtra(EXTRA_RESUME, true)
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

/**
 * Outside any layout scope, so the plain AnimatedVisibility is the one used. It covers at once (a fade-in would show the new
 * page's first frame, and HyperOS then turns the status bar white for a moment) and fades out onto the bot list.
 */
@Composable
private fun ServiceTransitionOverlay(visible: Boolean, name: String, text: String) {
    AnimatedVisibility(visible, enter = EnterTransition.None, exit = fadeOut(tween(220))) { ServiceTransition(name, text, blocking = visible) }
}

/**
 * Shown while a service opens, instead of the website's own connecting screen and a bare bar with the address: the page
 * colour, the robot tile, the service name and a quiet spinner. While it is up it takes the taps meant for the page under
 * it; while it fades out they reach the page, so a bot tapped right after the list shows opens.
 */
@Composable
private fun ServiceTransition(name: String, text: String, blocking: Boolean) {
    val c = MikaTheme.colors
    Column(Modifier.fillMaxSize().background(c.bg).then(if (blocking) Modifier.pointerInput(Unit) { detectTapGestures { } } else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        BotUiAvatar(BotUiProfile(color = 1, palette = 2), Modifier.size(56.dp))
        Spacer(Modifier.height(16.dp))
        Text(name, Modifier.padding(horizontal = 32.dp), color = c.ink, fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(6.dp))
        Text(text, Modifier.padding(horizontal = 32.dp), color = c.ink2, fontSize = 14.sp, lineHeight = 20.sp)
        Spacer(Modifier.height(20.dp))
        CircularProgressIndicator(Modifier.size(20.dp), color = c.ink3, strokeWidth = 2.dp, trackColor = Color.Transparent)
    }
}
