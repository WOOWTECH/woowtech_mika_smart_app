// WOOWTECH fork: brand layer tests. Not part of upstream Mika.
package com.wangzan101.mika.core.brand

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        // core 的单测不带 brand.properties,所以全局的 Brand 也是上游原值
        assertFalse(Brand.branded)
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

    /** woowtech flavor 的品牌设定能读、必填的值都在,而且不再指向上游的发布页。 */
    @Test
    fun woowtechBrandFileIsComplete() {
        val f = File("../app/src/woowtech/resources/brand.properties")
        val props = Properties().apply { f.reader(Charsets.UTF_8).use(::load) }
        val b = BrandValues(props)
        listOf("name", "name.zh", "token", "persona", "repo", "repo.label", "releases.api", "search.url", "download.folder", "ui.languages")
            .forEach { assertTrue("brand.properties misses $it", !props.getProperty(it).isNullOrBlank()) }
        assertFalse(b.token.contains(' '))
        assertTrue(b.latestReleaseApi, b.latestReleaseApi.startsWith("https://api.github.com/repos/") && "wangzan101" !in b.latestReleaseApi)
        assertTrue(b.repo, b.repo.startsWith("https://github.com/") && "wangzan101" !in b.repo)
        assertTrue(props.getProperty("prompt.append.${BrandValues.IDENTITY}").orEmpty().isNotBlank())
    }
}
