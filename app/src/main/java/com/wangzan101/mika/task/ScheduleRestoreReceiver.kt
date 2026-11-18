package com.wangzan101.mika.task

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机(闹钟开机后就没了)、App 更新、改了时间或时区、准时闹钟的权限变了:把定时任务和提醒的闹钟重新布置好。
 * 只做这一件事:商店版没有操作手机,不经 BootRestoreHandler(那个会去恢复内置助手和无障碍)。
 */
class ScheduleRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        val app = context.applicationContext
        TriggerRuntime.rearm(app)
        // 换了时区:跟随设备时区的当地时间计划立刻按新时区重算(内部会重新布置闹钟),显式钉了其他时区的不动
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED) TriggerRuntime.syncTimeZone(app)
    }

    internal companion object {
        /** 清单里登记的那几个系统广播。 */
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
        )
    }
}
