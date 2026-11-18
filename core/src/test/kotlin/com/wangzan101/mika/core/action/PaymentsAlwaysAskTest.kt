package com.wangzan101.mika.core.action

import com.wangzan101.mika.core.agent.AgentLoop
import com.wangzan101.mika.core.agent.FakeModel
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.gate.ConfirmationGate
import com.wangzan101.mika.core.model.ChatModel
import com.wangzan101.mika.core.model.Message
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.Role
import com.wangzan101.mika.core.model.StopReason
import com.wangzan101.mika.core.model.ToolSpec
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.record.RunSink
import com.wangzan101.mika.core.uistate.ActionResult
import com.wangzan101.mika.core.uistate.ScreenPort
import com.wangzan101.mika.core.uistate.ScreenSnapshot
import com.wangzan101.mika.core.uistate.UiElement
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import com.wangzan101.mika.core.assembly.toolDispatcher

private fun el(ref: String, role: String, name: String, b: List<Int>, editable: Boolean = false) =
    UiElement(ref, role, name, 0, 0, b, null, !editable, editable, false)

/** 聊天页:标题、输入框、「发送」。 */
private val chat = listOf(
    el("@e1", "text", "张三", listOf(0, 0, 999, 80)),
    el("@e2", "edit", "明天见", listOf(0, 900, 790, 999), editable = true),
    el("@e3", "button", "发送", listOf(800, 900, 990, 990)),
)

/** 结算页:店名、合计金额和「提交订单」「立即支付」。 */
private val checkout = listOf(
    el("@e1", "text", "耳机店", listOf(0, 0, 999, 80)),
    el("@e2", "text", "合计 ¥25", listOf(0, 800, 600, 860)),
    el("@e3", "button", "提交订单", listOf(600, 900, 990, 990)),
    el("@e4", "button", "立即支付", listOf(0, 900, 590, 990)),
)

private class ShopPage(var page: List<UiElement>) : ScreenPort {
    val taps = mutableListOf<String>()
    private var reads = 0
    private fun read(id: String) = ScreenSnapshot(id, "com.shop", page, 1080, 2400)
    override suspend fun snapshot(): ScreenSnapshot = read("s${++reads}")
    override suspend fun peek(): ScreenSnapshot = read("p$reads")
    override suspend fun screenshotPng(): ByteArray? = null
    override suspend fun tapRef(ref: String, snapshotId: String): ActionResult { taps += ref; return ActionResult.Ok(changed = true) }
    override suspend fun tapXY(x: Int, y: Int): ActionResult { taps += "$x,$y"; return ActionResult.Ok(changed = true) }
    override suspend fun typeText(ref: String?, snapshotId: String?, text: String) = ActionResult.Ok(changed = true)
    override suspend fun clearText(ref: String?, snapshotId: String?) = ActionResult.Ok()
    override suspend fun scroll(ref: String?, snapshotId: String?, down: Boolean) = ActionResult.Ok()
    override suspend fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long) = ActionResult.Ok()
    override suspend fun back() = ActionResult.Ok()
    override suspend fun pressKey(keyCode: Int) = ActionResult.Ok()
    override suspend fun openApp(packageName: String, cold: Boolean) = ActionResult.Ok()
    override suspend fun waitStable(timeoutMs: Long) = true
    override suspend fun listApps() = listOf("com.shop" to "Shop")
}

private class ApprovalEvents : RunSink {
    val all = mutableListOf<RunEvent>()
    override fun event(e: RunEvent) { all += e }
}

/** 商店版的审批设置:自主模式可开可关,付款永远先问。 */
private class PlayApprovals(var auto: Boolean) : ApprovalSettings {
    override fun autonomous() = auto
    override fun paymentsAlwaysAsk() = true
}

private var seq = 0
private fun call(name: String, args: String = "{}") = Part.ToolCall("p${++seq}", name, args)
private fun tools(vararg c: Part.ToolCall) = ModelReply(c.toList(), StopReason.ToolUse, null)
private val OBSERVE get() = tools(call("phone_observe"))
private val FINISH get() = com.wangzan101.mika.core.testing.answerReply("好了")
private val GIVE_UP get() = tools(call("end_not_done", """{"message":"没做"}"""))
private fun tap(ref: String) = tools(call("phone_tap", """{"ref":"$ref","snapshotId":"s1"}"""))
private val ASK_ORDER get() =
    tools(call("request_confirmation", """{"action":"order","target":"耳机店","content":"一副耳机","amount":"¥25","app":"com.shop"}"""))

private fun FakeModel.result(i: Int): JsonObject =
    Json.parseToJsonElement(requests[i].last { it.role == Role.Tool }.parts.filterIsInstance<Part.ToolResult>().first().content).jsonObject
private fun JsonObject.s(k: String) = this[k]!!.jsonPrimitive.content

/** Owner decision 2026-11-18:商店版开了自主模式,花钱的那一步也照样先问;别的(发送等)照自主直接做。 */
@OptIn(ExperimentalCoroutinesApi::class)
class PaymentsAlwaysAskTest {
    private fun loop(m: ChatModel, s: ShopPage, approvals: ApprovalSettings, sink: RunSink = RunSink.NONE, gate: ConfirmationGate? = ConfirmationGate()) =
        AgentLoop(m, toolDispatcher(s), "BASE", sink = sink, confirmations = gate, approvals = approvals)

    @Test fun autonomousStillAsksBeforePlacingAnOrder() = runTest {
        val s = ShopPage(checkout); val sink = ApprovalEvents()
        val m = FakeModel(OBSERVE, tap("@e3"), GIVE_UP)
        loop(m, s, PlayApprovals(auto = true), sink).run("t")
        assertTrue(s.taps.isEmpty())
        assertEquals("confirmation_required", m.result(2).s("error"))
        val audit = sink.all.filterIsInstance<RunEvent.Approval>().single()
        assertEquals(listOf("true", "required"), listOf(audit.payment.toString(), audit.decision))
    }

    @Test fun autonomousStillHandsThePaymentToTheUser() = runTest {
        val s = ShopPage(checkout)
        val m = FakeModel(OBSERVE, tap("@e4"), GIVE_UP)
        loop(m, s, PlayApprovals(auto = true)).run("t")
        assertTrue(s.taps.isEmpty())
        assertEquals("confirmation_required", m.result(2).s("error"))
        assertTrue(m.result(2).s("message"), "hand_to_user" in m.result(2).s("message"))
    }

    @Test fun autonomousSendsWithoutAsking() = runTest {
        val s = ShopPage(chat); val sink = ApprovalEvents()
        val m = FakeModel(OBSERVE, tap("@e3"), FINISH)
        loop(m, s, PlayApprovals(auto = true), sink).run("t")
        assertEquals(listOf("@e3"), s.taps)
        assertTrue(sink.all.none { it is RunEvent.Confirmation })
    }

    @Test fun anApprovedOrderRunsOnceInAutonomousMode() = runTest {
        val s = ShopPage(checkout)
        val m = FakeModel(OBSERVE, ASK_ORDER, tap("@e3"), tap("@e3"), GIVE_UP)
        val l = loop(m, s, PlayApprovals(auto = true))
        val run = async { l.run("t") }
        advanceUntilIdle()
        assertTrue(l.state.value is TaskState.WaitingConfirmation)
        l.answerConfirmation(ConfirmChoice.Once)
        run.await()
        assertEquals(listOf("@e3"), s.taps)
        assertEquals("confirmation_required", m.result(4).s("error"))
    }

    @Test fun switchingToAutonomousMidRunKeepsAskingForPayment() = runTest {
        val s = ShopPage(checkout)
        val approvals = PlayApprovals(auto = false)
        val m = FakeModel(OBSERVE, tap("@e3"), tap("@e3"), GIVE_UP)
        val flipping = object : ChatModel by m {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                if (m.requests.size == 2) approvals.auto = true
                return m.complete(system, messages, tools)
            }
        }
        loop(flipping, s, approvals).run("t")
        assertEquals("confirmation_required", m.result(2).s("error"))
        assertEquals("confirmation_required", m.result(3).s("error"))
        assertTrue(s.taps.isEmpty())
    }

    @Test fun withoutAConfirmationGateAPaymentIsRefusedNotRun() = runTest {
        val s = ShopPage(checkout)
        val m = FakeModel(OBSERVE, tap("@e3"), GIVE_UP)
        loop(m, s, PlayApprovals(auto = true), gate = null).run("t")
        assertTrue(s.taps.isEmpty())
        assertEquals("confirmation_required", m.result(2).s("error"))
    }

    @Test fun directDownloadAutonomousStillPaysWithoutAsking() = runTest {
        val s = ShopPage(checkout)
        val m = FakeModel(OBSERVE, tap("@e3"), FINISH)
        loop(m, s, ApprovalSettings { true }).run("t")
        assertEquals(listOf("@e3"), s.taps)
    }
}
