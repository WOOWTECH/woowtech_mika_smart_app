// WOOWTECH fork: the woowtech flavor's hand-written strings stay in step with upstream's. Not part of upstream Mika.
package com.wangzan101.mika.core.brand

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * app/src/woowtech/res 里人工写的字串盖过 src/main/res 的同名字串,app/brand.gradle.kts 产生品牌字串时也跳过它们,
 * 所以上游改了 key 或占位符,这些字串不会跟着变。同步上游后由这里报出来:覆盖的每个 key 上游都还有、占位符和上游一样;
 * 品牌版自己的字串(woow_ 开头)英文、繁中两份都有。上游改了原文的意思查不出来,同步时照 docs-woowtech/FORK.md 看一次。
 */
class BrandStringsTest {
    private val app = File("../app/src")

    /** [dir] 下文件名以 [prefix] 开头的 .xml 里的字串:名字 → 文字(复数、数组是各项连起来,只用来数占位符)。 */
    private fun strings(dir: File, prefix: String = ""): Map<String, String> =
        dir.listFiles { f -> f.name.startsWith(prefix) && f.name.endsWith(".xml") }.orEmpty().sortedBy { it.name }.flatMap { f ->
            val nodes = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(f).documentElement.childNodes
            (0 until nodes.length).mapNotNull { nodes.item(it) as? Element }
                .filter { it.tagName in RESOURCE_TAGS }
                .map { it.getAttribute("name") to it.textContent }
        }.toMap()

    private fun args(s: String): List<String> = ARG.findAll(s).map { it.value }.sorted().toList()

    @Test
    fun overridesStillMatchUpstream() {
        val upstreamDefault = strings(File(app, "main/res/values"), "strings")
        for (folder in listOf("values", "values-b+zh+Hant")) {
            val upstream = strings(File(app, "main/res/$folder"), "strings")
            val woowtech = strings(File(app, "woowtech/res/$folder"))
            assertTrue(folder, woowtech.isNotEmpty())
            for ((name, text) in woowtech) {
                if (name.startsWith(OWN)) continue
                // 不翻译的字(translatable="false")上游只写在默认文件里
                val original = upstream[name] ?: upstreamDefault[name]
                assertNotNull("$folder/$name overrides no upstream string", original)
                assertEquals("$folder/$name", args(original!!), args(text))
            }
        }
    }

    @Test
    fun ownStringsHaveBothLanguages() {
        fun own(folder: String) = strings(File(app, "woowtech/res/$folder")).keys.filter { it.startsWith(OWN) }.toSet()
        assertTrue(own("values").isNotEmpty())
        assertEquals(own("values"), own("values-b+zh+Hant"))
    }

    private companion object {
        val RESOURCE_TAGS = setOf("string", "plurals", "string-array")
        val ARG = Regex("%(\\d+\\$)?[sd]")
        /** 品牌版自己的字串的前缀(授权页的 woow_lic_*),上游没有。 */
        const val OWN = "woow_"
    }
}
