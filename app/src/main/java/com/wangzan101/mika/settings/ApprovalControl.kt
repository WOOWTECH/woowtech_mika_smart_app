package com.wangzan101.mika.settings

import com.wangzan101.mika.core.action.ApprovalSettings
import com.wangzan101.mika.core.gate.ConfirmationGate

/**
 * 一个任务自己的审批设置:自主与否是开工时取全局的,之后跟着设置里的「自主模式」变([set])。
 * 询问时只有付款先问;自主时连付款也不问。[paymentsAsk] 为 true(商店版,见 [PlayApprovalPolicy])时付款永远先问,
 * 自主模式也一样:这时任务一直有确认关卡。
 */
class RunApproval(startAutonomous: Boolean, private val paymentsAsk: Boolean = false) : ApprovalSettings {
    /** 开工时就是自主。 */
    val startedAutonomous: Boolean = startAutonomous
    /** 开工时就没有确认关卡(自主,且付款不必先问):这个任务不给 request_confirmation;中途关掉自主留给下一个任务。 */
    val startedWithoutGate: Boolean get() = startedAutonomous && !paymentsAsk
    @Volatile private var auto = startAutonomous

    override fun autonomous(): Boolean = auto

    override fun paymentsAlwaysAsk(): Boolean = paymentsAsk

    fun set(autonomous: Boolean) {
        auto = autonomous
    }

    /** 这个任务(和它的子任务)用的付款确认关卡:开工时有关卡才有,每次一份新的。 */
    fun gate(): ConfirmationGate? = if (startedWithoutGate) null else ConfirmationGate()
}

/**
 * 询问 / 自主是一个全局开关,存在 [ApprovalStore.autonomous],默认询问。每个任务开工时拿一份自己的([start]);
 * 换开关([setAutonomous]):存下来管之后的任务,正在跑的任务也跟着换(从询问换成自主,下一步起付款也不再问——
 * [paymentsAlwaysAsk] 时付款照问)。
 */
class ApprovalControl(private val store: ApprovalStore, private val paymentsAlwaysAsk: Boolean = false) {
    private val runs = mutableSetOf<RunApproval>()

    /**
     * [remote] 为 true 是电脑经 MCP 交来的任务:不管开关,一律按询问开工、也不跟着开关变,
     * 付款这一步在这类任务里永远不做(审批判定对非手机发起的一律拒绝),远端没有办法让它放行。
     */
    @Synchronized fun start(remote: Boolean = false): RunApproval =
        if (remote) RunApproval(false, paymentsAlwaysAsk) else RunApproval(store.autonomous.value, paymentsAlwaysAsk).also { runs += it }

    @Synchronized fun end(run: RunApproval) {
        runs -= run
    }

    @Synchronized fun setAutonomous(on: Boolean) {
        store.setAutonomous(on)
        runs.forEach { it.set(on) }
    }
}
