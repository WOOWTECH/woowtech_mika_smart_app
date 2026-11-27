package com.wangzan101.mika.settings

import com.wangzan101.mika.BuildConfig

/**
 * Approvals in the Play edition. Owner decision 2026-11-18: autonomous mode is offered as in the direct-download
 * edition, but a payment always asks first, even in autonomous mode (see [RunApproval]).
 */
internal object PlayApprovalPolicy {
    val paymentsAlwaysAsk: Boolean get() = BuildConfig.PLAY_EDITION
}
