// WOOWTECH fork: model errors in the UI language. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.ui

import com.wangzan101.mika.R
import com.wangzan101.mika.core.model.ListFailure
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelListResult
import com.wangzan101.mika.core.net.ProxyFailure
import com.wangzan101.mika.i18n.tr

/**
 * 模型、模型列表出错时给人看的一句短原因,按界面语言写:接在「试着让 … 调用一个工具没成功:」「连接失败:」这类话后面。
 * core 的 [ModelError.message]、[ListFailure.text] 是写死的简体中文,认不出的报错还带着整段报文;这里只引服务端的原话
 * ([ModelError.BadResponse.said]),说法和 core 的一样(简体那份逐字相同)。
 */
object ModelErrorCopy {
    fun reason(e: ModelError): String = when (e) {
        is ModelError.Auth -> tr(R.string.model_error_auth)
        is ModelError.QuotaExceeded -> tr(R.string.model_error_quota)
        is ModelError.RateLimited -> tr(R.string.model_error_rate_limited)
        is ModelError.ContextTooLong -> tr(R.string.model_error_context)
        is ModelError.ModelNotFound -> tr(R.string.model_reason_not_found)
        is ModelError.ModelNotAvailable ->
            if (e.detail.isEmpty()) tr(R.string.model_error_not_available) else tr(R.string.model_reason_not_available, e.detail)
        is ModelError.ToolsUnsupported -> tr(R.string.model_reason_no_tools)
        is ModelError.Network -> tr(R.string.model_error_network)
        is ModelError.Proxy -> proxy(e.failure)
        is ModelError.StreamCut -> tr(R.string.model_error_stream_cut)
        is ModelError.Server -> tr(R.string.model_reason_server, "HTTP ${e.status}")
        is ModelError.ContentRefused -> tr(R.string.model_error_refused)
        is ModelError.ChatGptLimitReached -> tr(R.string.model_error_chatgpt_limit)
        is ModelError.ChatGptNotEligible -> tr(R.string.model_error_chatgpt_not_eligible)
        is ModelError.SignInExpired -> tr(R.string.model_error_signed_out, e.account)
        is ModelError.AccountPlanNotAllowed -> tr(R.string.model_error_plan, e.account)
        is ModelError.BadResponse -> when {
            e.status != null && e.said.isNotEmpty() -> tr(R.string.model_error_server_said, "HTTP ${e.status}", e.said)
            e.status != null -> tr(R.string.model_reason_server, "HTTP ${e.status}")
            e.said.isNotEmpty() -> tr(R.string.model_error_said, e.said)
            else -> tr(R.string.model_error_unreadable)
        }
    }

    /** 列模型没成功的原因;[ModelListResult.Failed.detail] 是状态码(「HTTP 500」)时一并说。 */
    fun listFailure(r: ModelListResult.Failed): String = when (r.reason) {
        ListFailure.BadUrl -> tr(R.string.model_url_scheme)
        ListFailure.Auth -> tr(R.string.model_error_auth)
        ListFailure.Quota -> tr(R.string.model_error_quota)
        ListFailure.RateLimited -> tr(R.string.model_error_rate_limited)
        ListFailure.Network -> tr(R.string.list_error_network)
        ListFailure.ProxyUnreachable -> proxy(ProxyFailure.Unreachable)
        ListFailure.ProxyAuth -> proxy(ProxyFailure.AuthFailed)
        ListFailure.NotSupported -> tr(R.string.list_error_not_supported)
        ListFailure.Server -> if (r.detail.isEmpty()) tr(R.string.list_error_server) else tr(R.string.model_reason_server, r.detail)
        ListFailure.BadResponse -> if (r.detail.isEmpty()) tr(R.string.model_error_unreadable) else tr(R.string.model_reason_server, r.detail)
    }

    private fun proxy(f: ProxyFailure): String =
        tr(if (f == ProxyFailure.AuthFailed) R.string.net_proxy_auth_failed else R.string.net_proxy_unreachable)
}
