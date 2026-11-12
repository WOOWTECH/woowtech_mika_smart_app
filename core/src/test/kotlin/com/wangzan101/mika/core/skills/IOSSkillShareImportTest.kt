package com.wangzan101.mika.core.skills

import com.wangzan101.mika.core.knowledge.FrontMatter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Inputs are written by the actual Swift exporter, never handwritten Android fixtures. */
class IOSSkillShareImportTest {
    private fun fixture(name: String): String {
        val path = System.getenv("WOOW_SKILL_SHARE_FIXTURES")
        assumeTrue("Swift-generated cross-platform fixtures were not requested", path != null)
        val file = File(path!!, name)
        check(file.isFile) { "Missing freshly generated fixture: $name" }
        return file.readText(Charsets.UTF_8)
    }

    private fun prepare(text: String): SkillImport.Result = SkillImport.prepare(
        raw = text, store = InMemoryPersonalSkills(), builtinNames = emptySet(),
        toolNames = emptySet(), scriptTool = null, id = "cross-share", now = 42L,
    )

    private fun verify(label: String, expectedProblem: String? = null): String {
        val installed = fixture("$label.installed.md")
        val shared = fixture("$label.shared.md")
        // Android's parser does not recognize an indented closing delimiter. Normalize
        // copies only for comparison; prepare below receives the untouched Swift output.
        fun comparable(value: String) = value.replace("\n  ---  \n", "\n---\n")
        val (originalMeta, originalBody) = FrontMatter.parse(comparable(installed))
        val (shareMeta, shareBody) = FrontMatter.parse(comparable(shared))
        assertEquals("All original public fields survive", originalMeta - "source", shareMeta)
        assertEquals("Sharing preserves every byte of the body, headings and anchors", originalBody, shareBody)
        assertEquals("cross-share-${if (label == "invalid-fence") "invalid" else label}", shareMeta["name"])
        assertEquals("Synthetic share", shareMeta["display"])
        assertEquals("Organize a synthetic note", shareMeta["description"])
        assertEquals(listOf("note, summary", "guide"), shareMeta["aliases"])
        assertEquals("CC0-1.0", shareMeta["license"])
        assertNull(shareMeta["source"])
        assertNull(shareMeta["learned_from"])
        assertNull(shareMeta["updates"])
        assertFalse(shared.contains("synthetic-run"))
        assertFalse(shared.contains("previous-synthetic"))
        val result = prepare(shared)
        val category = when (result) {
            is SkillImport.Result.Ready -> "Ready"
            is SkillImport.Result.Rejected -> "Rejected(${result.problem})"
        }
        if (expectedProblem != null) {
            assertEquals("Android actual result for $label: $category", SkillImport.Result.Rejected(expectedProblem), result)
        } else {
            assertTrue("Android actual result for $label: $category", result is SkillImport.Result.Ready)
            val skill = (result as SkillImport.Result.Ready).skill
            assertEquals(SkillStatus.pending, skill.status)
            assertEquals(PersonalSkill.SOURCE_IMPORTED, skill.source)
            assertNull(skill.learnedFrom)
            assertNull(skill.replacesDraftOf)
            assertTrue(skill.outcomes.isEmpty())
            val (meta, body) = FrontMatter.parse(skill.markdown)
            assertEquals(PersonalSkill.SOURCE_IMPORTED, meta["source"])
            assertEquals("Android prepare preserves the shared body", shareBody, body)
        }
        println("PASS real Swift export -> Android SkillImport.prepare: $label: $category")
        return shared
    }

    @Test fun simplified() {
        val shared = verify("simplified")
        assertTrue(shared.contains("## Steps\nLINK_TARGET_KEEP\n[Jump](#steps)\n## Stepsister\nSTEPSISTER_KEEP"))
    }
    @Test fun traditionalOnly() { verify("hant", "missing_section") }
    @Test fun englishOnly() {
        val shared = verify("english", "missing_section")
        assertTrue(shared.contains("## Steps\nSTEPS_BODY_KEEP"))
        assertTrue(shared.contains("[Jump](#steps)\n## Stepsister\nSTEPSISTER_KEEP"))
    }
    @Test fun indentedDelimiter() {
        val shared = verify("indented", "invalid_name")
        assertTrue(shared.contains("\n  ---  \n"))
    }
    @Test fun htmlPre() {
        val shared = verify("html")
        assertTrue(shared.contains("<pre>\n## Steps\nHTML_BODY_KEEP\n</pre>"))
    }
    @Test fun fencedHeadingsCountedByAndroid() {
        val shared = verify("fenced")
        assertTrue(shared.contains("~~~text\n## 入口\nCANONICAL_BODY_KEEP"))
    }
    @Test fun invalidFenceInfoAcceptedByAndroid() {
        val shared = verify("invalid-fence")
        assertTrue(shared.contains("``` invalid` info\n## Steps\n```"))
    }
}
