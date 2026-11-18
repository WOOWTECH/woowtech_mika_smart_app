package com.wangzan101.mika.task

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.wangzan101.mika.MikaApp

/**
 * 开机(闹钟开机后就没了)、App 更新、改了时间或时区、准时闹钟的权限变了:把定时任务和提醒的闹钟重新布置好。
 * 开机和更新还会停掉电脑连接的前台服务:用户开着的远程网关连线在这里接回去(系统允许从这两个广播起前台服务)。
 * 只做这两件事:商店版没有操作手机,不经 BootRestoreHandler(那个会去恢复内置助手和无障碍)。
 */
class ScheduleRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        val app = context.applicationContext
        TriggerRuntime.rearm(app)
        // 换了时区:跟随设备时区的当地时间计划立刻按新时区重算(内部会重新布置闹钟),显式钉了其他时区的不动
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED) TriggerRuntime.syncTimeZone(app)
        // 电脑连接没开着时什么也不做
        if (intent.action in RESUMES_COMPUTER_CONNECTION) (app as? MikaApp)?.mcp?.ensureRunning()
    }

    internal companion object {
        /** 清单里登记的那几个系统广播。 */
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
        )

        /** 停掉了电脑连接前台服务的那两个(开机、App 更新)。 */
        val RESUMES_COMPUTER_CONNECTION = setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)
    }
}
