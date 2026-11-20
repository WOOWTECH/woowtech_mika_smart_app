package com.wangzan101.mika.core.document

/** Exact local commands only. Questions, extra instructions, quoted messages and attachments remain chat. */
object DocumentCommand {
    private val english = Regex("(?:export|save) (?:the )?(?:previous|last) (?:answer|response|report|table) (?:as|to) (pdf|html|csv)[.!?。！？]?", RegexOption.IGNORE_CASE)
    private val chinese = Regex("(?:請)?把(?:剛才|上面|上一則|上一则|上個)的?(?:回答|回覆|分析|報告|报告|表格)(?:整理成|做成|匯出成|导出为|輸出成|轉成) ?(pdf|html|csv)(?: ?(?:檔案|檔))?[.!?。！？]?", RegexOption.IGNORE_CASE)

    fun parse(text: String, hasAttachments: Boolean = false, hasQuote: Boolean = false, busy: Boolean = false): DocumentFormat? {
        if (hasAttachments || hasQuote || busy || text.length > 256 || text.toByteArray(Charsets.UTF_8).size > 256 ||
            text.any { it.code < 32 || it in "\u0085\u2028\u2029" }) return null
        val match = english.matchEntire(text.trim(' ')) ?: chinese.matchEntire(text.trim(' ')) ?: return null
        return DocumentFormat.entries.first { it.name.equals(match.groupValues[1], ignoreCase = true) }
    }
}
