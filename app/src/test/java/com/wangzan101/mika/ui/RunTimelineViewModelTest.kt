package com.wangzan101.mika.ui

import com.wangzan101.mika.i18n.ChineseTexts
import com.wangzan101.mika.core.guard.GuardVerdict
import com.wangzan101.mika.core.guard.Severity
import com.wangzan101.mika.core.record.Redactor
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.record.RunHandle
import com.wangzan101.mika.record.RunStore
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import com.wangzan101.mika.core.assembly.knownTools
import com.wangzan101.mika.core.tool.Verb

class RunTimelineViewModelTest {
    @get:Rule val texts = ChineseTexts()

    @get:Rule val tmp = TemporaryFolder()

    private var clock = 1_760_000_000_000L
    private val store by lazy { RunStore(tmp.root.resolve("files"), { null }, 30, { clock }) { it } }

    private fun run(goal: String, block: RunHandle.() -> Unit): String {
        val h = store.open(goal)
        h.block()
        h.close()
        return h.runId
    }

    private fun ready(runId: String) = RunTimelineViewModel(store, runId).load() as TimelineUi.Ready

    /** 任务还在跑、还没有结束事件时算「进行中」:页面据此每秒重读,跑完就停。 */
    @Test fun anUnfinishedRunOfALiveTaskReadsAsRunning() {
        val h = store.open("打开设置")
        store.append(h.runId, RunEvent.ModelReply(clock + 1_000, 1, "", null, null, 500, 10, 0, 900, repliedAtMs = clock + 1_000))
        val live = RunTimelineViewModel(store, h.runId, alive = { it == h.runId }).load() as TimelineUi.Ready
        assertTrue("没结束就算在跑", live.header.running)
        store.append(h.runId, RunEvent.TaskEnded(clock + 2_000, "succeeded", "好了"))
        val done = RunTimelineViewModel(store, h.runId, alive = { it == h.runId }).load() as TimelineUi.Ready
        assertFalse("结束之后不再重读", done.header.running)
    }

    /** 没有结束记录、任务也已经不在了(进程被杀、记录没写完):算已结束,不一直按秒重读。 */
    @Test fun anUnfinishedRunWhoseTaskIsGoneIsNotRunning() {
        val h = store.open("打开设置")
        store.append(h.runId, RunEvent.ModelReply(clock + 1_000, 1, "", null, null, 500, 10, 0, 900, repliedAtMs = clock + 1_000))
        val gone = RunTimelineViewModel(store, h.runId, alive = { false }).load() as TimelineUi.Ready
        assertFalse(gone.header.running)
        val other = RunTimelineViewModel(store, h.runId, alive = { it == "another-run" }).load() as TimelineUi.Ready
        assertFalse("别的任务在跑不算这一次", other.header.running)
    }

    @Test fun usedMemoryAppearsInProcessHeader() {
        val id = run("总结") { event(RunEvent.MemoryUsed(clock, listOf("m1", "m2"))) }
        val ui = RunTimelineViewModel(store, id, resolveMemory = { ids -> ids.map { "记忆 $it" } }).load() as TimelineUi.Ready
        assertEquals(listOf("记忆 m1", "记忆 m2"), ui.header.usedMemory)
    }

    @Test fun headerCarriesRunMetrics() {
        val id = run("查天气") {
            event(RunEvent.TaskStarted(clock, "查天气", "m1"))
            event(RunEvent.ModelReply(clock + 3_000, 1, "", null, null, 1_000, 100, 0, 2_500, repliedAtMs = clock + 3_000))
            event(RunEvent.TaskEnded(clock + 4_000, "succeeded", "晴"))
        }
        val m = ready(id).header.metrics!!
        assertEquals(id, m.runId)
        assertEquals(4_000L, m.totalMs)
        assertEquals(3_000L, m.firstFeedbackMs)
        assertEquals(1, m.modelCalls)
    }

    @Test fun headerCarriesTheStepLimit() {
        val limited = run("查天气") {
            event(RunEvent.TaskStarted(clock, "查天气", "m1", stepLimit = 60))
            event(RunEvent.TaskEnded(clock + 1_000, "succeeded", "晴"))
        }
        assertEquals(60, ready(limited).header.stepLimit)
        val unlimited = run("看电量") {
            event(RunEvent.TaskStarted(clock, "看电量", "m1"))
            event(RunEvent.TaskEnded(clock + 1_000, "succeeded", "85%"))
        }
        assertNull(ready(unlimited).header.stepLimit)
    }

    /** 步数用完后的收尾那一轮记作第上限加一步:显示用了几步时不算它,不会出现 4 / 3。 */
    @Test fun stepsUsedNeverExceedsTheLimit() {
        val id = run("查快递") {
            event(RunEvent.TaskStarted(clock, "查快递", "m1", stepLimit = 3))
            (1..4).forEach { step -> event(RunEvent.ModelReply(clock + step * 1_000L, step, "", null, null, 500, 10, 0, 900, repliedAtMs = clock + step * 1_000L)) }
            event(RunEvent.TaskEnded(clock + 5_000, "failed", "已达到 3 步上限"))
        }
        assertEquals(3, ready(id).header.stepsUsed)
        val early = run("看电量") {
            event(RunEvent.TaskStarted(clock, "看电量", "m1", stepLimit = 30))
            event(RunEvent.ModelReply(clock + 1_000, 1, "", null, null, 500, 10, 0, 900, repliedAtMs = clock + 1_000))
            event(RunEvent.ModelReply(clock + 2_000, 2, "85%", null, null, 500, 10, 0, 900, repliedAtMs = clock + 2_000))
            event(RunEvent.TaskEnded(clock + 3_000, "succeeded", "85%"))
        }
        assertEquals(2, ready(early).header.stepsUsed)
    }

    @Test fun groupsEventsIntoSteps() {
        val long = "先".repeat(100)
        val id = run("看电量") {
            event(RunEvent.TaskStarted(clock, "看电量", "m1"))
            event(RunEvent.Criteria(clock, listOf("看到电量百分比"), emptyList()))
            event(RunEvent.ModelReply(clock, 1, long, "phone_launch_app", """{"package":"com.android.settings"}""", 10, 1, null))
            event(RunEvent.ToolResult(clock, 1, "phone_launch_app", """{"ok":true}""", true, null))
            event(RunEvent.ModelReply(clock, 2, "看看", "phone_observe", "{}", 10, 1, null))
            event(RunEvent.ToolResult(clock, 2, "phone_observe", """{"ok":true,"elements":[]}""", null, 1))
            media(1, byteArrayOf(1, 2, 3))
            event(RunEvent.Media(clock, 1, 2, "com.android.settings"))
            event(RunEvent.ModelReply(clock, 3, "", "phone_tap", """{"ref":"@e3"}""", 10, 1, null))
            event(RunEvent.ToolResult(clock, 3, "phone_tap", """{"ok":true}""", false, null))
            event(RunEvent.ModelReply(clock, 4, "", "phone_tap", """{"ref":"@e9"}""", 10, 1, null))
            event(RunEvent.ToolResult(clock, 4, "phone_tap", """{"ok":false,"error":"ref_expired","message":"x"}""", null, null))
            clock += 65_000
            event(RunEvent.TaskEnded(clock, "succeeded", "85%"))
        }
        val ui = ready(id)
        assertEquals(listOf(1, 2, 3, 4), ui.steps.map { it.step })
        val (launch, look, tap, stale) = ui.steps
        assertEquals("先".repeat(80) + "…", launch.said)
        assertEquals("打开 App", launch.tool)
        assertEquals("com.android.settings", launch.detail)
        assertEquals("生效", launch.result)
        assertEquals("看屏幕", look.tool)
        assertEquals(1, look.screenshotId)
        assertTrue(store.screen(id, 1)!!.isFile)
        assertEquals("没变化", tap.result)
        assertEquals("出错:界面已经变了,要重新看屏幕", stale.result)
        assertNull(launch.screenshotId)

        val h = ui.header
        assertEquals("看电量", h.goal)
        assertEquals(listOf("看到电量百分比"), h.criteria)
        assertEquals("办成了", h.outcome)
        assertEquals("1 分 5 秒", h.duration)
        assertEquals(4, h.modelCalls)
        assertEquals("没有核查", h.verdict)
    }

    @Test fun rejectedLightReplyCountsAsCallButNotStep() {
        val id = run("看电量") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_observe", "{}", 10, 1, null, model = "light", role = "light_rejected"))
            event(RunEvent.ModelReply(clock, 1, "", "phone_tap", """{"ref":"@e3"}""", 10, 1, null, model = "main", role = "main"))
            event(RunEvent.ToolResult(clock, 1, "phone_tap", """{"ok":true}""", true, null))
            event(RunEvent.TaskEnded(clock, "succeeded", "85%"))
        }
        val ui = ready(id)
        assertEquals(2, ui.header.modelCalls)
        // 改派掉的 observe 不进步骤:这一步显示的是主模型的 tap
        assertEquals(ToolLabels(knownTools()).label("phone_tap"), ui.steps.single().tool)
    }

    @Test fun stepTimingIncludesModelRetryAndToolWithoutCountingBatchChildrenTwice() {
        val id = run("连续操作") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_observe", "{}", null, null, null,
                latencyMs = 1_200, role = "light_rejected"))
            event(RunEvent.ModelReply(clock, 1, "", "do_steps", "{}", null, null, null,
                latencyMs = 2_300, retryWaitMs = 500))
            event(RunEvent.ToolResult(clock, 1, "phone_tap", """{"ok":true}""", true, null,
                durationMs = 700, source = "batch"))
            event(RunEvent.ToolResult(clock, 1, "phone_type_text", """{"ok":true}""", true, null,
                durationMs = 900, source = "batch"))
            event(RunEvent.ToolResult(clock, 1, "do_steps", """{"ok":true}""", true, null,
                durationMs = 2_000, source = "model"))
        }
        val timing = ready(id).steps.single().timing
        assertEquals(4_000L, timing.modelMs)
        assertEquals(2_000L, timing.toolMs)
        assertEquals(500L, timing.retryMs)
        assertEquals(6_000L, timing.totalMs)
        assertEquals("约 6.0 秒 · 模型 4.0 秒 · 操作 2.0 秒 · 含重试 500 毫秒",
            RunTimelineViewModel.timingLabel(timing))
    }

    @Test fun replayTimingAndLegacyMissingTimingAreLabeledHonestly() {
        val replay = run("回放") {
            event(RunEvent.ToolResult(clock, 1, "phone_tap", """{"ok":true}""", true, null,
                durationMs = 850, source = "replay"))
        }
        assertEquals("操作 850 毫秒", RunTimelineViewModel.timingLabel(ready(replay).steps.single().timing))

        val legacy = run("旧记录") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_tap", "{}", null, null, null))
            event(RunEvent.ToolResult(clock, 1, "phone_tap", """{"ok":true}""", true, null))
        }
        assertEquals("耗时未记录", RunTimelineViewModel.timingLabel(ready(legacy).steps.single().timing))
        assertNull(ready(legacy).steps.single().timing.totalMs)
    }

    @Test fun activitiesMergeReadsAndKeepActionsSeparate() {
        val id = run("查页面并操作") {
            event(RunEvent.ModelReply(clock, 1, "", "do_steps", "{}", 10, 1, null))
            repeat(3) { i ->
                event(RunEvent.Activity(clock, 1, "observe", "web_read_page", "example.com", "completed", listOf(i + 1), callId = "r$i"))
            }
            event(RunEvent.Activity(clock, 1, "act", "web_tap", "example.com", "done", callId = "a1"))
            event(RunEvent.Activity(clock, 1, "act", "web_tap", "example.com", "no_effect", callId = "a2"))
        }
        val rows = ready(id).steps.single().activities
        assertEquals(3, rows.size)
        assertEquals(3, rows[0].count)
        assertEquals(listOf(1, 2, 3), rows[0].obsIds)
        assertEquals(listOf("act", "act"), rows.drop(1).map { it.kind })
    }

    /**
     * WOOWTECH fork: 对象和对话里的步骤一样给人看的说法:网页那一步(运行记录里写成「网站 域名」)只显示域名,
     * 连着读同一站照样合成一行;命令只留命令。
     */
    @Test fun activityTargetsReadLikeTheChatSteps() {
        val id = run("看网页") {
            event(RunEvent.Activity(clock, 1, "observe", "web_read_page", "网站 127.0.0.1", "completed", listOf(1), callId = "r1"))
            event(RunEvent.Activity(clock, 1, "observe", "web_read_page", "网站 127.0.0.1", "completed", listOf(2), callId = "r2"))
            event(RunEvent.Activity(clock, 1, "act", "web_tap", "网站 127.0.0.1", "changed", callId = "a1"))
        }
        val rows = ready(id).steps.single().activities
        assertEquals(listOf("127.0.0.1", "127.0.0.1"), rows.map { it.target })
        assertEquals(2, rows.first().count)
        // 命令的对象只留命令,旁边写的是工具的说法,不露 run_command
        val cmd = run("算一下") { event(RunEvent.Activity(clock, 1, "act", "run_command", "run_command「ls -l」", "completed", callId = "c1")) }
        val act = ready(cmd).steps.single().activities.single()
        assertEquals("处理文件" to "ls -l", act.label to act.target)
    }

    @Test fun showsVerifierAndGuardTags() {
        // 和 AgentLoop 一样用守卫自己的序列化拼结果
        fun withGuard(vararg v: GuardVerdict) =
            JsonObject(mapOf("ok" to JsonPrimitive(true), "guard" to JsonArray(v.map { it.toJson() }))).toString()
        val warn = withGuard(GuardVerdict("no_progress", Severity.Warn, buildJsonObject { put("same", 3) }))
        val stop = withGuard(GuardVerdict("repeating_action", Severity.Stop, buildJsonObject { put("code", "x"); put("n", 3) }))
        // 键的顺序换了也认得
        val reordered = """{"ok":true,"guard":[{"evidence":{"a":1},"severity":"warn","code":"too_many_failures"},{"severity":"warn","code":"brand_new"}]}"""
        val id = run("发消息") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_scroll", "{}", null, null, null))
            event(RunEvent.ToolResult(clock, 1, "phone_scroll", warn, false, null))
            event(RunEvent.ModelReply(clock, 2, "", "phone_scroll", "{}", null, null, null))
            // 截短的结果不再是合法 JSON,标签照样认得出
            event(RunEvent.ToolResult(clock, 2, "phone_scroll", RunEvent.clip(stop + " ".repeat(RunEvent.MAX_FIELD)), false, null))
            event(RunEvent.ModelReply(clock, 4, "", "phone_tap", "{}", null, null, null))
            event(RunEvent.ToolResult(clock, 4, "phone_tap", reordered, null, null))
            event(RunEvent.ModelReply(clock, 5, "", "phone_tap", "{}", null, null, null))
            event(RunEvent.ToolResult(clock, 5, "phone_tap", """{"ok":false,"error":"some_new_code"}""", null, null))
            event(RunEvent.ModelReply(clock, 3, "好了", "finish", """{"answer":"x"}""", null, null, null))
            event(RunEvent.Verifier(clock, "fail", "{}"))
            event(RunEvent.ToolResult(clock, 3, "finish", """{"ok":false,"error":"verification_failed"}""", null, null))
            event(RunEvent.TaskEnded(clock, "failed", "已安全停止"))
        }
        val ui = ready(id)
        assertEquals(listOf(Tag("守卫提醒:画面一直没变化", TagTone.Warn)), ui.steps[0].tags)
        assertEquals(listOf(Tag("守卫停止:同一个操作反复做", TagTone.Bad)), ui.steps[1].tags)
        assertEquals(listOf(Tag("核查没通过", TagTone.Bad)), ui.steps.single { it.step == 3 }.tags)
        val four = ui.steps.single { it.step == 4 }
        assertEquals(listOf(Tag("守卫提醒:操作连续失败", TagTone.Warn), Tag("守卫提醒", TagTone.Warn)), four.tags)
        assertEquals("出错了", ui.steps.single { it.step == 5 }.result)
        assertFalse(ui.toString().contains("brand_new") || ui.toString().contains("some_new_code"))
        assertEquals("核查没通过", ui.header.verdict)
        assertEquals("没有完成", ui.header.outcome)
    }

    // WOOWTECH fork: 电脑交来的任务里申报同意被直接拒绝(没有人被问过):标签和结果照实说,不写「要你同意」「你没有同意」;
    // 标签挂在申报的那一步上,前一步(真的点成了)只标它自己的结果
    @Test fun remoteRefusalIsNotShownAsTheUsersDecision() {
        val id = run("买耳机") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_tap", """{"ref":"@e3"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 1, "phone_tap", """{"ok":true}""", true, null))
            // 申报在执行那一步时记下,那一步的回复执行完才记:事件带着它的步号
            event(RunEvent.Confirmation(clock, "order", "耳机店", "一副耳机", "¥25", "declined_remote", step = 2))
            event(RunEvent.ModelReply(clock, 2, "请你同意", "request_confirmation", """{"action":"order"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 2, "request_confirmation", """{"ok":false,"error":"confirmation_remote","message":"x"}""", null, null))
            event(RunEvent.TaskEnded(clock, "failed", "不能下单"))
        }
        val (tap, ask) = ready(id).steps
        assertEquals("生效" to emptyList<Tag>(), tap.result to tap.tags)
        assertEquals(listOf(Tag("从电脑交办的任务不能付款或下单", TagTone.Bad)), ask.tags)
        assertEquals("出错:不能从电脑付款", ask.result)
    }

    /**
     * WOOWTECH fork: 申报同意的那一步,问完你才记它的回复和结果,确认事件在它们前面。〔要你同意〕〔你没同意〕挂在申报的那一步上;
     * 前一步填好了优惠码,真的生效了,只标生效,不带着「你没同意」让人以为被拒绝的下单做成了(11/07 模拟器 P8 第 9、10 步)。
     */
    @Test fun aDeclinedRequestIsTaggedOnTheStepThatAsked() {
        val id = run("填优惠码后送出") {
            event(RunEvent.ModelReply(clock, 9, "", "web_type_text", """{"ref":"@e7","text":"WOOW50"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 9, "web_type_text", """{"ok":true,"typed":6,"pressedEnter":false}""", true, null))
            event(RunEvent.Activity(clock, 9, "act", "web_type_text", "网站 127.0.0.1", "small_change", callId = "t9"))
            event(RunEvent.Confirmation(clock, "order", "测试商店", "优惠码 WOOW50,按 Enter 送出订单", "NT$790", null, step = 10))
            event(RunEvent.Confirmation(clock, "order", "测试商店", "优惠码 WOOW50,按 Enter 送出订单", "NT$790", "declined", step = 10))
            event(RunEvent.ModelReply(clock, 10, "", "request_confirmation", """{"action":"order"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 10, "request_confirmation", """{"ok":false,"error":"confirmation_declined","message":"x"}""", null, null))
            event(RunEvent.TaskEnded(clock, "failed", "你没同意,没有送出"))
        }
        val (typed, ask) = ready(id).steps
        assertEquals(9 to 10, typed.step to ask.step)
        assertEquals("生效" to emptyList<Tag>(), typed.result to typed.tags)
        assertEquals(listOf(Tag("要你同意", TagTone.Warn), Tag("你没同意", TagTone.Bad)), ask.tags)
        assertEquals("出错:你没有同意", ask.result)
    }

    /** WOOWTECH fork: 被确认关卡拦下的那一步自己带〔要你同意〕;一批里第一步就被拦下时,那一步先由这条开出来。 */
    @Test fun aBlockedStepCarriesItsOwnNeedsOkTag() {
        val id = run("选 ATM 转账") {
            event(RunEvent.ModelReply(clock, 7, "", "web_tap", """{"ref":"@e3"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 7, "web_tap", """{"ok":true}""", true, null))
            event(RunEvent.Confirmation(clock, "pay", "ATM转账", null, null, "required", step = 8))
            event(RunEvent.ModelReply(clock, 8, "", "do_steps", "{}", null, null, null))
            event(RunEvent.ToolResult(clock, 8, "do_steps", """{"ok":false,"error":"confirmation_required","message":"x"}""", null, null))
        }
        val (tap, batch) = ready(id).steps
        assertEquals("生效" to emptyList<Tag>(), tap.result to tap.tags)
        assertEquals("出错:要先征得你同意" to listOf(Tag("要你同意", TagTone.Warn)), batch.result to batch.tags)
    }

    /** WOOWTECH fork: 还在等你回答时,申报那一步的回复和结果都还没记:先开出这一行挂〔要你同意〕,不挂到前一步。 */
    @Test fun aRequestWaitingForYouShowsOnItsOwnStep() {
        val h = store.open("买耳机")
        store.append(h.runId, RunEvent.ModelReply(clock, 1, "", "web_tap", """{"ref":"@e3"}""", null, null, null))
        store.append(h.runId, RunEvent.ToolResult(clock, 1, "web_tap", """{"ok":true}""", true, null))
        store.append(h.runId, RunEvent.Confirmation(clock, "order", "测试商店", "一副耳机", "NT$590", null, step = 2))
        val ui = RunTimelineViewModel(store, h.runId, alive = { it == h.runId }).load() as TimelineUi.Ready
        assertTrue(ui.header.running)
        val (tap, ask) = ui.steps
        assertTrue(tap.tags.isEmpty())
        assertEquals(2, ask.step)
        assertEquals(listOf(Tag("要你同意", TagTone.Warn)), ask.tags)
        assertNull(ask.result)
    }

    /** 旧记录里的确认事件没有步号:照旧挂在它之前最近的一步上。 */
    @Test fun oldConfirmationsWithoutAStepStayOnTheStepBefore() {
        val id = run("发消息") {
            event(RunEvent.ModelReply(clock, 1, "", "phone_type_text", """{"text":"明天见"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 1, "phone_type_text", """{"ok":true}""", true, null))
            event(RunEvent.Confirmation(clock, "send", "张三", "明天见", null, "approved"))
            event(RunEvent.ModelReply(clock, 2, "", "request_confirmation", """{"action":"send"}""", null, null, null))
            event(RunEvent.ToolResult(clock, 2, "request_confirmation", """{"ok":true,"approved":true}""", null, null))
        }
        val (typed, ask) = ready(id).steps
        assertEquals(listOf(Tag("你同意了", TagTone.Ok)), typed.tags)
        assertTrue(ask.tags.isEmpty())
    }

    @Test fun missingRunShowsExpired() {
        assertEquals(TimelineUi.Expired, RunTimelineViewModel(store, "20250101-000000-abcdef").load())
        assertEquals(TimelineUi.Expired, RunTimelineViewModel(store, "../../etc").load())
        val id = run("x") { event(RunEvent.TaskEnded(clock, "cancelled", "")) }
        tmp.root.resolve("files/runs/$id").deleteRecursively()
        assertEquals(TimelineUi.Expired, RunTimelineViewModel(store, id).load())
    }

    @Test fun maskedFieldsStayMasked() {
        val key = "sk-" + "a".repeat(30)
        val id = run("登录 $key") {
            val args = Redactor.args(Verb.TypeText, """{"ref":"@e2","text":"hunter2"}""", secretField = true)
            event(RunEvent.ModelReply(clock, 1, Redactor.text("我输入密码 $key"), "phone_type_text", args, null, null, null))
            event(RunEvent.ToolResult(clock, 1, "phone_type_text", """{"ok":true,"secret":true}""", true, null))
        }
        val ui = ready(id)
        val all = ui.toString()
        assertFalse(all.contains("hunter2"))
        assertFalse(all.contains(key))
        assertEquals(Redactor.MASK, ui.steps.single().detail)
        assertTrue(ui.steps.single().said.contains(Redactor.MASK))
        assertTrue(ui.header.goal.contains(Redactor.MASK))
        assertEquals("没有结束", ui.header.outcome)
    }
}
