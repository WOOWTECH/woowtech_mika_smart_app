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

    /** 跟着语言改名的是这三个频道;名字和建它们时用的是同一个来源:配对的两个 id 同名,背景准备另一个。 */
    @Test fun namesFollowTheAppLanguageAndAreTheOnesTheChannelsAreCreatedWith() {
        // 英文界面(规则已装上)
        assertEquals(mapOf("pairing_code" to "Pairing", "pairing_alert" to "Pairing", "runtime_prepare" to "Background setup"), ChannelNames.names())
        assertEquals(PhoneSetupCopy.CHANNEL_NAME, ChannelNames.names().getValue(PairingChannel.IDS.last()))
        assertEquals(SandboxForeground.CHANNEL_NAME, ChannelNames.names().getValue(SandboxForeground.CHANNEL))
        UiText.source = ResFileTexts.traditional
        assertEquals(mapOf("pairing_code" to "配對", "pairing_alert" to "配對", "runtime_prepare" to "背景準備"), ChannelNames.names())
        UiText.source = ResFileTexts.chinese
        assertEquals(mapOf("pairing_code" to "配对", "pairing_alert" to "配对", "runtime_prepare" to "后台准备"), ChannelNames.names())
    }

    /**
     * 英文界面下建好的频道,换成繁中:只有已经存在的「配对」「背景准备」被改名;不存在的(旧的 pairing_code)不会被建出来,
     * 任务的频道不在里面;改完再对一次,没有要改的(不重复写系统)。
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
        assertEquals(mapOf(PairingChannel.IDS.last() to "配對", SandboxForeground.CHANNEL to "背景準備"), renamed)
        assertEquals(emptyMap<String, String>(), ChannelNames.renames(created + renamed, ChannelNames.names()))
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
}
