package com.wangzan101.mika.ui

import com.wangzan101.mika.core.assembly.knownTools
import com.wangzan101.mika.i18n.ChineseTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ToolLabelsTest {
    @get:Rule val texts = ChineseTexts()

    /** 每个声明了 label 的工具都有界面文字,中文和声明一字不差;英文另有一份。 */
    @Test
    fun everyDeclaredLabelIsLocalized() {
        val tools = knownTools()
        val labels = ToolLabels(tools)
        val declared = tools.names.mapNotNull { n -> tools[n]?.label?.let { n to it } }
        assertTrue(declared.size > 40)
        for ((name, label) in declared) {
            assertTrue("$name: $label", label in ToolLabels.TOOL_LABELS)
            assertEquals(name, label, labels.label(name))
        }
        UiText.source = ResFileTexts.english
        assertEquals("Tap", labels.label("tap"))
        assertEquals("Open web page", labels.label("browser_navigate"))
    }

    /** WOOWTECH fork: 上游没有说法的工具、一次连做几步(do_steps)也有界面上的说法,不露工具名。 */
    @Test
    fun everyToolAndDoStepsHasALabel() {
        val tools = knownTools()
        val labels = ToolLabels(tools)
        assertEquals(emptyList<String>(), tools.names.filter { tools[it]?.label == null })
        assertEquals("连续做几步", labels.label("do_steps"))
        UiText.source = ResFileTexts.english
        assertEquals("Several steps in a row", labels.label("do_steps"))
        assertEquals("Find by looking at the screen", labels.label("phone_find_visually"))
        assertEquals("Run page script", labels.label("web_script"))
        UiText.source = ResFileTexts.traditional
        assertEquals("連續做幾步", labels.label("do_steps"))
        assertEquals("看圖找控制項", labels.label("web_find_visually"))
    }

    /** WOOWTECH fork: 运行记录里写成「工具名「命令」」的地方,工具名换成界面上的说法;查询词、路径、包名不是这种地方。 */
    @Test
    fun commandPlacesUseTheToolLabel() {
        val labels = ToolLabels(knownTools())
        UiText.source = ResFileTexts.traditional
        assertEquals("處理檔案「python -c 'print(2 ** 20)'」", labels.place("run_command「python -c 'print(2 ** 20)'」"))
        UiText.source = ResFileTexts.english
        assertEquals("Work with files “ls -l”", labels.place("run_command「ls -l」"))
        assertEquals("Search files “*.csv”", labels.place("search_files「*.csv」"))
        assertEquals("Run built-in script office/xlsx.py", labels.place("run_bundled_script office/xlsx.py"))
        assertNull(labels.place("wait 5 seconds"))
        assertNull(labels.place("tap the button"))
        assertNull(labels.place("/workspace/a.txt"))
        assertNull(labels.place("com.android.chrome"))
    }
}
