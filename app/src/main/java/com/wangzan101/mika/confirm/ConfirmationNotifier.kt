package com.wangzan101.mika.confirm

import com.wangzan101.mika.core.cap.root.ROOT_CONFIRM_APP
import com.wangzan101.mika.i18n.tr
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.wangzan101.mika.R
import com.wangzan101.mika.task.AlertGroup
import com.wangzan101.mika.task.alertQuietly
import com.wangzan101.mika.task.inGroup
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.gate.ConfirmationRequest
import com.wangzan101.mika.core.risk.IrrevAction

/**
 * 确认卡片和通知上的文字。字段都是模型写的:只当纯文本用(不解析任何标记);
 * 换行、行分隔符压成空格,去掉控制字符、零宽字符和文字方向控制符;
 * 字段里的「·」和冒号换成别的符号,拼不出假的「· 金额:」一类字段。
 */
object ConfirmationCopy {
    /** 收起时那一行里内容显示的字数。 */
    const val CONTENT_MAX = 60
    /** 展开的卡片和通知里内容最多显示的字数(和申报时的上限一致)。 */
    const val DETAIL_MAX = 200
    /** WOOWTECH fork: 通知标题里金额显示的字数;更长的截断加「…」(标题只有一行;收起的一行和展开的大字里金额是完整的)。 */
    const val TITLE_AMOUNT_MAX = 30
    /** 确认卡片上的说明:只有花钱的操作要你同意,每次只同意这一次。 */
    val NOTE: String get() = tr(R.string.confirm_note)

    fun actionLabel(action: IrrevAction): String = when (action) {
        IrrevAction.send -> tr(R.string.chat_send)
        IrrevAction.pay -> tr(R.string.confirm_pay)
        IrrevAction.delete -> tr(R.string.confirm_delete)
        IrrevAction.order -> tr(R.string.confirm_order)
        IrrevAction.submit -> tr(R.string.confirm_submit)
        IrrevAction.other -> tr(R.string.confirm_other)
    }

    /** root 命令不在哪个 App 里:卡片标题说是 root 命令,「在哪里」说整部手机,命令整条显示(会改动东西的才问)。 */
    private fun root(r: ConfirmationRequest) = r.app == ROOT_CONFIRM_APP

    fun title(r: ConfirmationRequest) = tr(R.string.confirm_title, if (root(r)) tr(R.string.confirm_root) else actionLabel(r.action))

    /** 收起的一行:「在 <App 名> · 对象:<对谁> · 内容:<前 60 字> · 金额:<多少>」;空的字段不写。 */
    fun body(r: ConfirmationRequest, appName: String): String = fields(r, appName, CONTENT_MAX).joinToString(" · ")

    /** 展开的卡片和通知大字:一行一个字段,内容显示完整(最多 200 字)。 */
    fun detail(r: ConfirmationRequest, appName: String): String = fields(r, appName, if (root(r)) Int.MAX_VALUE else DETAIL_MAX).joinToString("\n")

    /**
     * WOOWTECH fork: 确认通知收起的那一行(横幅、折叠的通知),和 [body] 一样,只是金额排最前:「金额:<多少> · 在 <App 名> · 对象:… · 内容:…」。
     * 这一行放不下全部字段,金额排最后就被截掉,可横幅上的〔同意〕点一下就生效。其余字段的顺序不变,没有金额时和 [body] 一样。
     * 进度通知([com.wangzan101.mika.task.TaskService.describe])等别的调用方仍用 [body]。
     */
    fun notificationBody(r: ConfirmationRequest, appName: String): String =
        fields(r, appName, CONTENT_MAX, amountFirst = true).joinToString(" · ")

    /**
     * WOOWTECH fork: 确认通知的标题,有金额时带上:「要你同意:下单 NT$590」;没有金额时和 [title] 一样。锁屏上的公开版本不用它(不露金额)。
     * 金额是模型写的,和别的字段一样当纯文本消毒([plain]);标题只有一行,超过 [TITLE_AMOUNT_MAX] 个字的截断加「…」。
     */
    fun notificationTitle(r: ConfirmationRequest): String {
        val amount = amountText(r) ?: return title(r)
        // 按码点数截,不劈开代理对(同 StatusCopy.sandboxLine);截在空格后时去掉空格再加「…」
        val shown = if (amount.codePointCount(0, amount.length) <= TITLE_AMOUNT_MAX) amount
        else amount.substring(0, amount.offsetByCodePoints(0, TITLE_AMOUNT_MAX)).trimEnd() + "…"
        return tr(R.string.confirm_title_amount, if (root(r)) tr(R.string.confirm_root) else actionLabel(r.action), shown)
    }

    /** WOOWTECH fork: 申报里的金额(模型写的)消毒后的纯文字;没写、或消毒后是空的为 null。 */
    private fun amountText(r: ConfirmationRequest): String? = r.amount?.let(::plain)?.takeIf { it.isNotEmpty() }

    private fun fields(r: ConfirmationRequest, appName: String, contentMax: Int, amountFirst: Boolean = false): List<String> {
        val content = plain(r.content).let { if (it.length > contentMax) it.take(contentMax) + "…" else it }
        val amount = amountText(r)?.let { tr(R.string.payment_amount, it) }
        val others = listOfNotNull(
            tr(R.string.confirm_in_app, if (root(r)) tr(R.string.confirm_root_where) else plain(appName)),
            plain(r.target).takeIf { it.isNotEmpty() }?.let { tr(R.string.confirm_target, it) },
            content.takeIf { it.isNotEmpty() }?.let { tr(R.string.confirm_content, it) },
        )
        // WOOWTECH fork: [amountFirst] 时金额排最前([notificationBody]);上游和别的调用方金额排最后
        return if (amountFirst) listOfNotNull(amount) + others else others + listOfNotNull(amount)
    }

    private val INVISIBLE = Regex("[\\u061C\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u2069\\uFEFF]")
    private val SPACES = Regex("[\\s\\u2028\\u2029\\u0085\\u00A0\\u3000]+")

    private fun plain(s: String) = s.replace(INVISIBLE, "").replace(SPACES, " ")
        .filterNot { Character.isISOControl(it) }
        .replace('·', '/').replace(':', '∶').replace('：', '∶')
        .trim()
}

/** 确认关卡的醒目通知:和接管同一个高优先级频道,按钮「同意」「不同意」。 */
object ConfirmationNotifier {
    /** 通知按钮和卡片按钮带上它,服务据此丢掉点在旧通知、旧卡片上的回答。 */
    const val EXTRA_REQUEST = "confirmation_request"

    /** App 的显示名;读不到(没装、包不可见)时用包名。 */
    fun appLabel(context: Context, packageName: String): String = if (packageName == ROOT_CONFIRM_APP) tr(R.string.confirm_root_where) else try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString().ifBlank { packageName }
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    /** 每次申报一个编号:循环每次申报都新建一个等待状态,同一进程里的服务和界面拿到的是同一个对象。 */
    fun requestKey(state: TaskState.WaitingConfirmation): Int = System.identityHashCode(state)

    /** 按钮 Intent 的 data:每次申报、每个按钮各不相同,系统不会把旧通知上的按钮换成新申报的。 */
    fun intentData(key: Int, approve: Boolean) = "mika-confirm://request/$key/" + if (approve) "approve" else "decline"

    fun build(
        context: Context, channel: String, state: TaskState.WaitingConfirmation, service: Class<*>, approveAction: String, declineAction: String,
        contentIntent: PendingIntent,
        /** 几个任务同时等确认时各用一段请求码,按钮再带上 [runExtra] 标明是哪个任务的。 */
        codeOffset: Int = 0,
        runExtra: Pair<String, String>? = null,
        /** 照发但不响、不弹横幅(悬浮胶囊正在显示时),见 [alertQuietly]。 */
        quiet: Boolean = false,
        /** WOOWTECH fork: 放进这个通知组(组里有摘要,见 [AlertGroup]),[quiet] 时在组里不提醒;不给时照上游的做法。 */
        group: AlertGroup? = null,
    ): Notification {
        val r = state.request
        val key = requestKey(state)
        val app = appLabel(context, r.app)
        fun button(title: Int, action: String, approve: Boolean, code: Int): Notification.Action {
            val pi = PendingIntent.getService(
                context, code + codeOffset,
                Intent(context, service).setAction(action).setData(Uri.parse(intentData(key, approve))).putExtra(EXTRA_REQUEST, key)
                    .apply { runExtra?.let { (k, v) -> putExtra(k, v) } },
                // The data URI already separates requests. Refreshing this same request must
                // preserve a button the notification shade may still be displaying.
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            // WOOWTECH fork: 按钮和锁屏上的字经 tr() 按 App 语言取(context 是任务服务,getString 可能还是系统语言)
            return Notification.Action.Builder(null, tr(title), pi).apply {
                // 锁屏上点「同意」要先解锁
                if (approve && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setAuthenticationRequired(true)
            }.build()
        }
        // 锁屏上只露出要同意哪一类操作,对象和内容解锁后才看得到
        val public = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(ConfirmationCopy.title(r))
            .setContentText(tr(R.string.confirmation_locked_hint))
            .build()
        return Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            // WOOWTECH fork: 标题和收起的一行都带金额、金额排最前:横幅上的〔同意〕点一下就生效,金额不能被截掉;锁屏的公开版本(上面的 public)照旧不写金额
            .setContentTitle(ConfirmationCopy.notificationTitle(r))
            .setContentText(ConfirmationCopy.notificationBody(r, app))
            .setStyle(Notification.BigTextStyle().bigText(ConfirmationCopy.detail(r, app)))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(button(R.string.action_approve, approveAction, true, 20))
            .addAction(button(R.string.action_decline, declineAction, false, 21))
            // WOOWTECH fork: 有组时放进组里(组里有摘要,安卓 16 不会把它叠进系统的自动组、标成静音)
            .apply { if (group != null) inGroup(group, quiet) else if (quiet) alertQuietly() }
            .build()
    }
}
