// WOOWTECH fork: brand layer tests. Not part of upstream Mika.
package com.wangzan101.mika.core.brand

import com.wangzan101.mika.core.skills.SkillDrafter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Properties

class BrandValuesTest {
    private val woowtech = BrandValues(Properties().apply {
        setProperty("name", "woowtech agent")
        setProperty("name.zh", "渥屋助理")
        setProperty("persona", "渥屋助理 (woowtech agent)")
        setProperty("prompt.append.system/identity.md", "Never call yourself Mika.")
    })
    private val upstream = BrandValues(Properties())

    @Test
    fun withoutBrandFileEverythingIsUpstream() {
        assertFalse(upstream.branded)
        assertEquals("Mika", upstream.name)
        assertEquals("https://api.github.com/repos/wangzan101/Mika/releases/latest", upstream.latestReleaseApi)
        assertEquals("Open Mika once", upstream.text("Open Mika once"))
        assertEquals("You are Mika, the user's assistant", upstream.prompt(BrandValues.IDENTITY, "You are Mika, the user's assistant"))
        // 没设的文字为 null:调用处用上游原值
        assertNull(upstream.diagnosticsHeader)
        assertNull(upstream.issueTitlePrefix)
        // core 的单测不带 brand.properties,所以全局的 Brand 也是上游原值
        assertFalse(Brand.branded)
    }

    @Test fun capsuleDefaultIsBoundedAndInvalidValuesFallBack() {
        fun fraction(value: String) = BrandValues(Properties().apply {
            setProperty("capsule.default.fraction", value)
        }).capsuleDefaultFraction
        assertEquals(0f, upstream.capsuleDefaultFraction)
        assertEquals(0.5f, fraction("0.5"))
        assertEquals(1f, fraction("2"))
        assertEquals(0f, fraction("-1"))
        assertEquals(0f, fraction("NaN"))
        assertEquals(0f, fraction("Infinity"))
    }

    @Test
    fun englishTextUsesTheEnglishName() {
        assertEquals("Open woowtech agent once, then run this again.", woowtech.text("Open Mika once, then run this again."))
        assertEquals("woowtech agent's test page", woowtech.text("Mika's test page"))
        assertEquals("woowtech agent self-check", woowtech.text("Mika self-check"))
    }

    @Test
    fun chineseTextUsesTheChineseNameWithoutSpaces() {
        assertEquals("讓渥屋助理幫你", woowtech.text("讓 Mika 幫你"))
        assertEquals("渥屋助理正在操作", woowtech.text("Mika 正在操作"))
        assertEquals("交給渥屋助理。", woowtech.text("交給 Mika。"))
        assertEquals("不支持调用工具,渥屋助理干活要靠工具。", woowtech.text("不支持调用工具,Mika 干活要靠工具。"))
        assertEquals("打开渥屋助理 App", woowtech.text("打开 Mika App"))
    }

    @Test
    fun identifiersUrlsAndPathsStay() {
        listOf(
            "mika_run_task", "github.com/wangzan101/Mika", "Download/Mika/", "MikaLinks", "mika phone tap",
            "com.wangzan101.mika", "Mika-v0.1.37.apk", "@Mika",
        ).forEach { assertEquals(it, woowtech.text(it)) }
    }

    @Test
    fun identityPromptGetsTheBrandPersona() {
        val identity = "You are Mika, the user's personal assistant on their phone."
        val out = woowtech.prompt(BrandValues.IDENTITY, identity)
        assertTrue(out, out.startsWith("You are 渥屋助理 (woowtech agent), the user's personal assistant"))
        assertTrue(out, out.endsWith("Never call yourself Mika."))
        assertEquals("Mika's browser", woowtech.prompt("capabilities/web.md", "Mika's browser"))
    }

    /** 同步上游后的守门:身份段的开头还是品牌层要换的那句,否则模型会照旧自称 Mika。 */
    @Test
    fun upstreamIdentityStillOpensWithTheReplacedPhrase() {
        val identity = File("src/main/resources/prompts/system/identity.md").readText()
        assertTrue(identity.take(80), identity.startsWith(BrandValues.IDENTITY_OPENING))
    }

    private fun brandFile(): Properties =
        Properties().apply { File("../app/src/woowtech/resources/brand.properties").reader(Charsets.UTF_8).use(::load) }

    /** woowtech flavor 的品牌设定能读、必填的值都在,而且不再指向上游的发布页。 */
    @Test
    fun woowtechBrandFileIsComplete() {
        val props = brandFile()
        val b = BrandValues(props)
        listOf("name", "name.zh", "token", "persona", "repo", "repo.label", "releases.api", "search.url", "download.folder", "ui.languages")
            .forEach { assertTrue("brand.properties misses $it", !props.getProperty(it).isNullOrBlank()) }
        assertFalse(b.token.contains(' '))
        assertTrue(b.latestReleaseApi, b.latestReleaseApi.startsWith("https://api.github.com/repos/") && "wangzan101" !in b.latestReleaseApi)
        assertTrue(b.repo, b.repo.startsWith("https://github.com/") && "wangzan101" !in b.repo)
        assertTrue(props.getProperty("prompt.append.${BrandValues.IDENTITY}").orEmpty().isNotBlank())
    }

    /**
     * 用户读得到的那几种角色输出(技能草稿、记忆、停下后的总结、App 知识)要用繁体中文:补充都在,
     * 而且每个 prompt.append.<路径> 都还是现有的提示词;同步上游后提示词改名或搬走,补充就会悄悄失效。
     */
    @Test
    fun promptAppendsNameExistingPrompts() {
        val paths = brandFile().stringPropertyNames().filter { it.startsWith("prompt.append.") }.map { it.removePrefix("prompt.append.") }
        val readByUser = listOf("roles/skill_draft.md", "roles/memory_extract.md", "roles/stop_summary.md", "roles/app_knowledge.md")
        assertTrue(paths.toString(), paths.containsAll(readByUser + BrandValues.IDENTITY))
        paths.forEach { assertTrue("prompts/$it", File("src/main/resources/prompts/$it").isFile) }
    }

    /** 技能草稿的补充要模型照抄五个小节的标题,得和 SkillDrafter 核对的一样;对不上,草稿会因为缺小节被丢掉。 */
    @Test
    fun skillDraftAppendKeepsTheCheckedHeadings() {
        val extra = brandFile().getProperty("prompt.append.roles/skill_draft.md").orEmpty()
        SkillDrafter.SECTIONS.forEach { assertTrue(it, "## $it" in extra) }
    }

    /** 用户会贴到 GitHub 的文字(诊断信息抬头、自检回报的标题前缀)写繁中;前缀和 issue 范本的 title 一致。 */
    @Test
    fun woowtechIssueTextIsTraditionalChinese() {
        val props = Properties().apply { File("../app/src/woowtech/resources/brand.properties").reader(Charsets.UTF_8).use(::load) }
        val b = BrandValues(props)
        assertEquals("渥屋助理診斷資訊 / woowtech agent diagnostics", b.diagnosticsHeader)
        assertEquals("[相容性]", b.issueTitlePrefix)
        val template = File("../.github/ISSUE_TEMPLATE/device-report.yml").readLines()
        assertTrue(template.joinToString("\n"), "title: \"${b.issueTitlePrefix} \"" in template)
    }
}
