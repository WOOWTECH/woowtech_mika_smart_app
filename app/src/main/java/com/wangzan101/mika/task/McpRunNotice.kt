package com.wangzan101.mika.task

import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr

/**
 * 这次任务里没连上的外部 MCP server(连接失败、超过总时限):任务卡片上提示一句,不打断任务,详情在设置页的健康状态里。
 * [failures] 是 (server 编号, 原因);名字取设置里的([names]),认不出的用编号。没有失败为 null。
 */
internal object McpRunNotice {
    fun text(failures: List<Pair<String, String>>, names: Map<String, String>): String? =
        failures.takeIf { it.isNotEmpty() }?.let { list -> tr(R.string.mcp_servers_run_failed, list.joinToString(", ") { names[it.first] ?: it.first }) }
}
