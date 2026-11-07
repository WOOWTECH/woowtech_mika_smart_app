package com.wangzan101.mika.task

import android.app.NotificationManager
import android.content.Context
import android.util.Log
import com.wangzan101.mika.cap.phone.setup.PairingChannel
import com.wangzan101.mika.cap.sandbox.SandboxForeground
import com.wangzan101.mika.ui.PhoneSetupCopy

/**
 * WOOWTECH fork: 让已经存在的「配对」「背景准备」通知频道的名字跟着 App 语言走。
 *
 * 安卓在建频道时把名字存下来,之后 App 换了语言它不会自己变。任务的三个频道每次起服务时由 [TaskService.ensureChannels] 重建,
 * 名字顺带换了;配对频道(用到才建)和背景准备频道(只在准备运行环境时才建)建好后没人再碰,繁中界面下系统设置 › 应用 › 通知里
 * 还写着建它们那一刻的语言(「Pairing」「Background setup」),和 App 里说的「配对」对不上(上游问题)。
 *
 * 这里只给系统里已经有的频道改名:取出那一个、只改名字、原样交回 createNotificationChannel。官方说明:频道已存在时,
 * 名字和说明会更新(名字本来就只该在语言变了时改);重要程度只会调低、而且只在用户没动过这个频道的设置时;其余字段一概忽略。
 * 交回的是取出来的那一个(重要程度没变),所以重要程度、声音、振动、角标和用户在系统设置里改过的都不受影响。
 * 不建不存在的频道:没用到的不必有;用户或 App 删掉的,按同一个 id 再建会连同删除前的设置一起恢复。
 *
 * 谁来调(都是幂等的:名字已经对了就一次写都不做):
 * - App 启动([com.wangzan101.mika.MikaApp.onCreate]):语言是在 App 不运行时换的(系统设置里),或这一版升级上来时旧名字还留着;
 * - 进程配置变了([com.wangzan101.mika.MikaApp.onConfigurationChanged]):跟随系统语言时,系统语言换了;
 * - App 内换语言([com.wangzan101.mika.i18n.AppLanguage.set]):安卓 12 及以前语言只记在本地,系统不会通知进程;
 *   安卓 13 起、进程里有无障碍服务时,系统也不再因 App 语言变了通知进程(AOSP 的 WindowProcessController.onServiceStarted,
 *   见 [com.wangzan101.mika.i18n.AppLanguage.applyDefaultLocale]),所以换语言的这一刻要自己调一次。
 */
object ChannelNames {
    private const val TAG = "MikaNotify"
    private val LOCK = Any()

    /** 要跟着语言改名的频道:id 到当前语言下该叫什么。名字和建这几个频道时用的是同一个来源。 */
    internal fun names(): Map<String, String> {
        val pairing = PhoneSetupCopy.CHANNEL_NAME
        return PairingChannel.IDS.associateWith { pairing } + (SandboxForeground.CHANNEL to SandboxForeground.CHANNEL_NAME)
    }

    /**
     * 该改哪些频道的名字(纯函数,便于测试):[existing] 是系统里已有的频道(id 到它现在的名字),[wanted] 是各 id 该叫什么。
     * 返回要改的 id 到新名字:只有已经存在、名字不一样的才在里面。系统里没有的不列(这里只改名,不建频道);
     * [wanted] 以外的频道不看;空名字不用(系统不收空名字,会抛错)。
     */
    internal fun renames(existing: Map<String, CharSequence>, wanted: Map<String, String>): Map<String, String> =
        wanted.filter { (id, name) ->
            val current = existing[id]?.toString()
            name.isNotBlank() && current != null && current != name
        }

    /** 把已有频道的名字对到当前的 App 语言。不抛错:改不了就记一句,下次再对。 */
    fun refresh(context: Context) {
        runCatching {
            val nm = context.getSystemService(NotificationManager::class.java)
            // 几处会同时调(启动在后台线程、换语言在主线程):排队做,每次都按此刻的语言取名,最后一次一定是最新的语言
            synchronized(LOCK) {
                val wanted = names()
                val existing = nm.notificationChannels.filter { it.id in wanted }.associateBy { it.id }
                renames(existing.mapValues { it.value.name }, wanted).forEach { (id, name) ->
                    val channel = existing.getValue(id)
                    Log.i(TAG, "notification channel $id renamed from \"${channel.name}\" to \"$name\"")
                    channel.name = name
                    nm.createNotificationChannel(channel)
                }
            }
        }.onFailure { Log.w(TAG, "could not refresh the notification channel names", it) }
    }
}
