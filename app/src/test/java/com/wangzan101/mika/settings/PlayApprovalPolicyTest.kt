package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PlayApprovalPolicyTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun autonomousPaymentPolicyFollowsChannelForBothBrands() {
        val control = ApprovalControl(ApprovalStore(tmp.root.resolve("approval.json")),
            paymentsAlwaysAsk = PlayApprovalPolicy.paymentsAlwaysAsk)
        control.setAutonomous(true)
        val run = control.start()
        assertEquals(BuildConfig.PLAY_EDITION, run.paymentsAlwaysAsk())
        assertEquals(!BuildConfig.PLAY_EDITION, run.startedWithoutGate)
        if (BuildConfig.PLAY_EDITION) assertNotNull(run.gate())
        else assertNull(run.gate())
    }
}
