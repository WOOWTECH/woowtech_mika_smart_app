// WOOWTECH fork: brand layer. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.core.brand

import java.util.Properties

/**
 * 随品牌变的值(产品名、对外地址、配色)都从这里取。
 *
 * 值来自 classpath 上可选的 `/brand.properties`:只有 woowtech flavor 带它(app/src/woowtech/resources)。
 * 没有这个文件时每个值都是上游原值、[text] 和 [prompt] 原样返回,所以上游构建和 core 的单测行为不变。
 */
object Brand : BrandValues(load())

private fun load(): Properties = Properties().also { p ->
    Brand::class.java.getResourceAsStream("/brand.properties")?.reader(Charsets.UTF_8)?.use(p::load)
}

/** [Brand] 的实现;单测用自己的 [Properties] 构造。 */
open class BrandValues(private val props: Properties) {
    private fun value(key: String, upstream: String): String =
        props.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() } ?: upstream

    /** 带了品牌设定(woowtech flavor)。 */
    val branded: Boolean = !props.isEmpty

    /** 英文产品名:英文界面,以及第三方看得到的名字(OAuth 同意页、MCP、外部工具)。 */
    val name: String = value("name", "Mika")

    /** 中文产品名:中文文字里提到产品时用。 */
    val nameZh: String = value("name.zh", "Mika")

    /** 不带空格的产品标记:User-Agent、ADB 钥匙名。 */
    val token: String = value("token", "Mika")

    /** 导出文件放在「下载」下的这个文件夹。 */
    val downloadFolder: String = value("download.folder", "Mika")

    val repo: String = value("repo", "https://github.com/wangzan101/Mika")
    val repoLabel: String = value("repo.label", "github.com/wangzan101/Mika")
    val latestReleaseApi: String = value("releases.api", "https://api.github.com/repos/wangzan101/Mika/releases/latest")

    /** 内建浏览器地址栏输入的不是网址时,拿去搜索的地址(后面接查询词)。 */
    val searchUrl: String = value("search.url", "https://www.bing.com/search?q=")

    /** 设置页语言列表只列这些语言(BCP 47,如 en、zh-Hant);空表示不限。 */
    val uiLanguages: List<String> =
        props.getProperty("ui.languages")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()

    /** 配色(ARGB 十六进制,如 FF4069FB);没设时用 [upstream]。 */
    fun argb(key: String, upstream: Long): Long =
        props.getProperty(key)?.trim()?.removePrefix("#")?.toLongOrNull(16) ?: upstream

    /**
     * 把文字里的产品名 Mika 换成品牌名。挨着中文(汉字或全形标点)时用 [nameZh],并去掉与中文之间的空格;
     * 其他时候用 [name]。网址、路径、标识符里的 mika(`mika_run_task`、`/Mika`、`mika phone`)不动。
     * 只用在 App 自己写的文字上:用户的话、屏幕上的字里的 Mika 可能是人名,不能换。
     */
    fun text(s: String): String {
        if (!branded || "Mika" !in s) return s
        return NAME.replace(s) { m ->
            val lead = m.groupValues[1]
            val trail = m.groupValues[2]
            val before = s.getOrNull(m.range.first - 1)
            val after = s.getOrNull(m.range.last + 1)
            if (cjk(before) || cjk(after)) {
                (if (before == null || cjk(before)) "" else lead) + nameZh + (if (after == null || cjk(after)) "" else trail)
            } else {
                lead + name + trail
            }
        }
    }

    /**
     * 提示词读出来后经这里([com.wangzan101.mika.core.prompt.Prompts.read])。
     * 身份那段(system/identity.md)开头的「You are Mika,」换成 `persona`;`prompt.append.<路径>` 设了就接在该段后面。
     * 其余提示词原样:工具结果、系统说明里仍叫 Mika,由身份段说明那就是它自己。
     */
    fun prompt(path: String, text: String): String {
        if (!branded) return text
        val persona = value("persona", name)
        val replaced = if (path == IDENTITY) text.replaceFirst(IDENTITY_OPENING, "You are $persona,") else text
        val extra = props.getProperty("prompt.append.$path")?.trim().orEmpty()
        return if (extra.isEmpty()) replaced else "$replaced\n\n$extra"
    }

    private fun cjk(c: Char?): Boolean = c != null &&
        (Character.UnicodeScript.of(c.code) == Character.UnicodeScript.HAN || c in '　'..'〿' || c in '＀'..'￯')

    companion object {
        const val IDENTITY = "system/identity.md"

        /** 上游身份段的开头;同步上游后由 BrandValuesTest 确认它还在。 */
        const val IDENTITY_OPENING = "You are Mika,"

        /** 独立的 Mika:前面不是字母、数字、_、/、.、@、-,后面不是字母、数字、_、/、-;两边各带最多一个空格。 */
        private val NAME = Regex("""( ?)(?<![A-Za-z0-9_/.@\-])Mika(?![A-Za-z0-9_/\-])( ?)""")
    }
}
