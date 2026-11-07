// WOOWTECH fork: notification channel names follow the app language. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.task

import com.wangzan101.mika.cap.phone.setup.PairingChannel
import com.wangzan101.mika.cap.sandbox.SandboxForeground
import com.wangzan101.mika.i18n.EnglishTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import com.wangzan101.mika.ui.PhoneSetupCopy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

class ChannelNamesTest {
    @get:Rule val texts = EnglishTexts()

    private val sources: List<File> by lazy { File("src/main/java").walk().filter { it.extension == "kt" }.toList() }

    /** 注释不算,只看代码行。 */
    private fun code(f: File) = f.readLines()
        .filterNot { l -> l.trim().let { it.startsWith("*") || it.startsWith("/*") || it.startsWith("//") } }
        .joinToString("\n")

    /**
     * 跟着语言改名的是这六个 id:配对的两个(同名)、背景准备一个、任务的三个;名字和建它们时用的是同一个来源。
     * 任务的三个也在里面:[TaskService.ensureChannels] 只在起服务、有结果要发时才跑,App 启动和换语言时不跑,
     * 换了语言之后没再跑过任务的,它们的名字要靠这里换。
     */
    @Test fun namesFollowTheAppLanguageAndAreTheOnesTheChannelsAreCreatedWith() {
        // 英文界面(规则已装上)
        assertEquals(
            mapOf(
                "pairing_code" to "Pairing", "pairing_alert" to "Pairing", "runtime_prepare" to "Background setup",
                "task_progress" to "Task progress", "task_result_v2" to "Task results", "task_attention" to "Needs you",
            ),
            ChannelNames.names(),
        )
        assertEquals(PhoneSetupCopy.CHANNEL_NAME, ChannelNames.names().getValue(PairingChannel.IDS.last()))
        assertEquals(SandboxForeground.CHANNEL_NAME, ChannelNames.names().getValue(SandboxForeground.CHANNEL))
        // 任务的三个:正好是建频道时的那三个 id,名字是 ensureChannels 建它们用的那一份
        assertEquals(TaskService.CHANNEL_IMPORTANCE.keys, TaskService.channelNames().keys)
        assertEquals(TaskService.channelNames(), ChannelNames.names().filterKeys { it in TaskService.CHANNEL_IMPORTANCE })
        UiText.source = ResFileTexts.traditional
        assertEquals(
            mapOf(
                "pairing_code" to "配對", "pairing_alert" to "配對", "runtime_prepare" to "背景準備",
                "task_progress" to "任務進度", "task_result_v2" to "任務結果", "task_attention" to "需要你處理",
            ),
            ChannelNames.names(),
        )
        UiText.source = ResFileTexts.chinese
        assertEquals(
            mapOf(
                "pairing_code" to "配对", "pairing_alert" to "配对", "runtime_prepare" to "后台准备",
                "task_progress" to "任务进度", "task_result_v2" to "任务结果", "task_attention" to "需要你处理",
            ),
            ChannelNames.names(),
        )
    }

    /**
     * 英文界面下建好的频道,换成繁中:只有已经存在的被改名(配对、背景准备、任务的进度和需要你);不存在的(旧的 pairing_code、
     * 还没建出来的结果频道)不会被建出来;改完再对一次,没有要改的(不重复写系统)。
     */
    @Test fun switchingTheLanguageRenamesTheExistingChannelsOnly() {
        val created = mapOf(
            PairingChannel.IDS.last() to "Pairing",
            SandboxForeground.CHANNEL to "Background setup",
            TaskService.CHANNEL_PROGRESS to "Task progress",
            TaskService.CHANNEL_ATTENTION to "Needs you",
        )
        UiText.source = ResFileTexts.traditional
        val renamed = ChannelNames.renames(created, ChannelNames.names())
        assertEquals(
            mapOf(
                PairingChannel.IDS.last() to "配對", SandboxForeground.CHANNEL to "背景準備",
                TaskService.CHANNEL_PROGRESS to "任務進度", TaskService.CHANNEL_ATTENTION to "需要你處理",
            ),
            renamed,
        )
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(created + renamed, ChannelNames.names()))
    }

    /** 旧的结果频道 task_result 是 ensureChannels 要删的:改名交回会把它救活,所以不在名单里;它碰巧还在系统里也不改它。 */
    @Test fun theOldResultChannelIsNeverRenamed() {
        assertFalse(ChannelNames.names().containsKey(TaskService.OLD_CHANNEL_RESULT))
        UiText.source = ResFileTexts.traditional
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(mapOf(TaskService.OLD_CHANNEL_RESULT to "Task results"), ChannelNames.names()))
    }

    /** 任务三个频道建的时候取的名字和改名用的是同一份(channelNames):ensureChannels 在 JVM 里跑不了,看源码里它没有自己另做一份。 */
    @Test fun theTaskChannelsAreCreatedWithTheNamesTheRenamingUses() {
        val service = code(sources.single { it.name == "TaskService.kt" })
        assertTrue("TaskService.ensureChannels takes the names from channelNames()", Regex("""\bval names = channelNames\(\)""").containsMatchIn(service))
    }

    /** 名字已经对了、或系统里还没有这个频道(没用到、被删了):什么都不做,尤其不建。 */
    @Test fun nothingIsRenamedWhenTheNameIsRightOrTheChannelIsMissing() {
        val names = ChannelNames.names()
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(names, names))
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(emptyMap(), names))
        // 只有一个存在时只改那一个
        assertEquals(mapOf("pairing_alert" to "Pairing"), ChannelNames.renames(mapOf("pairing_alert" to "配對"), names))
        // 名字一样、不是同一个对象:按文字比
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(mapOf("runtime_prepare" to StringBuilder("Background setup")), names))
    }

    /** 空名字系统不收(createNotificationChannel 会抛错),不用。 */
    @Test fun aBlankNameIsNeverApplied() {
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(mapOf("a" to "Old"), mapOf("a" to "  ")))
        assertEquals(mapOf("a" to "New"), ChannelNames.renames(mapOf("a" to "Old"), mapOf("a" to "New")))
    }

    /**
     * 改名只改名字:建频道(`NotificationChannel(`)的只有原来的三处,各自的重要程度见 TaskChannelsTest 和 PairingNoticeTest;
     * 改名的文件里没有建频道,也不碰重要程度、声音、振动、角标、分组这类设置。
     */
    @Test fun renamingNeverCreatesChannelsOrTouchesTheirSettings() {
        val constructs = Regex("""\bNotificationChannel\(""")
        assertEquals(
            setOf("PairingNotifier.kt", "SandboxForeground.kt", "TaskService.kt"),
            sources.filter { constructs.containsMatchIn(code(it)) }.map { it.name }.toSet(),
        )
        val own = code(sources.single { it.name == "ChannelNames.kt" })
        assertFalse(own, Regex("""(?i)importance|vibration|setSound|setShowBadge|enableLights|setBypassDnd|setGroup|setLockscreen""").containsMatchIn(own))
    }

    /**
     * 启动、进程配置变了、App 内换语言(安卓 13 起和 12 及以前两个分支各一次)都调改名;同步上游时这几行容易被改掉。
     * 安卓 13 起进程里有无障碍服务时,系统不会为 App 语言换了通知进程,所以 [com.wangzan101.mika.i18n.AppLanguage.set] 里那两次不能省。
     */
    @Test fun namesAreRefreshedAtStartAndWhenTheLanguageChanges() {
        val call = Regex("""\bChannelNames\.refresh\(""")
        fun calls(file: String) = call.findAll(code(sources.single { it.name == file })).count()
        assertEquals(2, calls("MikaApp.kt"))
        assertEquals(2, calls("AppLanguage.kt"))
    }
}
