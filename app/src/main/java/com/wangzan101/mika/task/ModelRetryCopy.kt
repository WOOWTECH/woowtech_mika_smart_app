package com.wangzan101.mika.task

import com.wangzan101.mika.R
import com.wangzan101.mika.core.agent.RetryNotice
import com.wangzan101.mika.i18n.tr

/**
 * 模型请求一时失败、正在重试时任务卡片上的一句:断线(连不上、超时、流断了)还是服务忙(限流、服务端出错),第几次。
 * 断线时一次请求要等到读超时才失败,重试几次可能要好几分钟;说一声,用户知道不是卡住了。
 */
internal object ModelRetryCopy {
    fun note(n: RetryNotice): String =
        if (n.network) tr(R.string.task_retry_network, n.attempt) else tr(R.string.task_retry_busy, n.attempt)
}
