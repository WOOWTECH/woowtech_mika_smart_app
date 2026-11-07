package com.wangzan101.mika.task

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.util.Log
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr

/**
 * WOOWTECH fork: 要响铃、弹出的通知(接管、提问、要你同意、结果、定时提醒、配对码)放进 App 自己的通知组,组里一定有摘要。
 *
 * 安卓 16 系统的自动分组(NotificationManagerService、GroupHelper;和「通知冷却」不是一回事):
 * - 同一区段(会提醒的、静音的各一段)里 App 没分组的通知满 2 条(config_autoGroupAtCount),系统把它们叠进自己的组
 *   g:Aggregate_AlertingSection;那个组已经在时,新来的不分组通知发出当下就叠进去。16 第一版给叠进去的通知加上
 *   FLAG_SILENT:不响、不弹横幅(App 在背景时的〔要你同意〕就是这样,通知栏里还留着上一则〔任务完成〕)。
 * - 分了组、组里却没有摘要的通知,发出 3 秒后(DELAY_FORCE_REGROUP_TIME)被强制叠进去,也加上 FLAG_SILENT,
 *   已经弹出的横幅当场收掉(定时提醒响约 3 秒就静音);16 QPR1、17 只剩这一种还会加 FLAG_SILENT。
 * - 组里有摘要的不叠,除非同一区段有 6 个以上只有 1~2 条通知的组(AUTOGROUP_SPARSE_GROUPS_AT_COUNT);这里最多 5 组
 *   (同时进行的 3 个任务各一组、结果一组、配对一组)。
 *
 * 摘要只当组头、从不提醒:GROUP_ALERT_CHILDREN 让摘要不响不弹,组里的通知照各自频道响铃、弹出。setOnlyAlertOnce 照旧:
 * 同一条通知更新不再响;撤掉后再发的是新通知,照样提醒。组里只有一条时系统只显示那一条,看起来和不分组一样。
 * 摘要和组里的通知用同一个频道:频道被关时一起不显示,在通知栏里也在同一区段。
 *
 * 摘要不能自己留下:没有子通知的摘要会被系统当成一条通知显示出来。所以
 * - [single] 的组一组只放一条,由 App 自己撤([cancel] 连摘要一起撤);那一条设了自动消失时间,摘要也设一样的;
 * - 结果组的通知由用户滑掉或点开(自动撤),最后一条没了,系统顺手撤掉摘要;App 不撤结果组里的通知。
 */
class AlertGroup private constructor(val key: String, private val single: Boolean) {
    /** 把 [b] 放进这一组。[quiet] 为真时照发进通知栏,但不响、不弹:组里只让摘要提醒,摘要又从不提醒。 */
    fun join(b: Notification.Builder, quiet: Boolean = false): Notification.Builder =
        b.setGroup(key).setGroupAlertBehavior(alertBehavior(quiet))

    /** 发出组里的 [n](用 [join] 放进来的):先发它,再发或更新摘要;它没发成(抛错)就不发摘要。 */
    fun notify(context: Context, nm: NotificationManager, id: Int, n: Notification) {
        synchronized(LOCK) {
            if (n.group != key) Log.w(TAG, "notification $id is not in group $key")
            nm.notify(id, n)
            nm.notify(key, SUMMARY_ID, summary(context, n))
        }
    }

    /** 撤掉组里的 [id],连同摘要。只给 [single] 的组用:撤掉摘要时,系统会把组里别的通知一起撤掉。 */
    fun cancel(nm: NotificationManager, id: Int) {
        synchronized(LOCK) {
            nm.cancel(id)
            nm.cancel(key, SUMMARY_ID)
        }
    }

    private fun summary(context: Context, child: Notification): Notification =
        join(Notification.Builder(context, child.channelId))
            .setGroupSummary(true)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(tr(R.string.app_name))
            .setContentIntent(child.contentIntent)
            .setOnlyAlertOnce(true)
            .apply { summaryTimeout(single, child.timeoutAfter)?.let { setTimeoutAfter(it) } }
            .build()

    companion object {
        /** 摘要的编号;摘要的 tag 是组名,App 别的通知 tag 都是 null,不会撞号。 */
        const val SUMMARY_ID = 0
        private const val TAG = "MikaNotify"
        private const val ATTENTION_PREFIX = "com.wangzan101.mika.attention."
        private val LOCK = Any()

        /** 结果、提示(Notice)、定时任务自己的通知(到点的提醒、没能开始、结果待确认)、准时闹钟的引导。 */
        val RESULTS = AlertGroup("com.wangzan101.mika.results", single = false)

        /** 配对码通知:只有一条,App 自己撤,也会自动消失。 */
        val PAIRING = AlertGroup("com.wangzan101.mika.pairing", single = true)

        /** 第 [slot] 个任务(见 [TaskRun.slot])的「需要你」通知:接管、提问、要你同意。每个任务一组、一条,App 自己撤。 */
        fun attention(slot: Int) = AlertGroup("$ATTENTION_PREFIX$slot", single = true)

        /** 组里通知的提醒方式:平常 GROUP_ALERT_CHILDREN(摘要不提醒,它自己提醒);[quiet] 时 GROUP_ALERT_SUMMARY(它也不提醒)。 */
        fun alertBehavior(quiet: Boolean): Int =
            if (quiet) Notification.GROUP_ALERT_SUMMARY else Notification.GROUP_ALERT_CHILDREN

        /** 摘要的自动消失时间:一组一条的组跟那一条一样,一起消失;结果组不设,免得到时把组里别的通知一起撤掉。 */
        fun summaryTimeout(single: Boolean, childTimeoutMs: Long): Long? = childTimeoutMs.takeIf { single && it > 0 }
    }
}

/** WOOWTECH fork: 放进 [group],见 [AlertGroup.join]。 */
internal fun Notification.Builder.inGroup(group: AlertGroup, quiet: Boolean = false): Notification.Builder = group.join(this, quiet)
