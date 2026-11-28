package com.wangzan101.mika.ui

import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.PathParser
import com.wangzan101.mika.chat.BotUiProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The bubble helmet (owner 11/28, bubble-helmet-avatar-spec.md): the face colour rule and the drawing's path data. */
class BotUiAvatarTest {
    private val white = 0xFFFFFFFF
    private val dark = 0xFF111111

    @Test fun matchingTheBodyDarkensTheFaceOnlyOnLightColours() {
        fun auto(color: Int) = botUiInk(BotUiProfile(color = color, palette = 2))
        // Orange is 0.34, under the 0.4 line, so it keeps white features (the earlier rule gave it dark ones).
        assertEquals(.340, botUiLuminance(0xFFE78531), .001)
        assertEquals(white, auto(3))
        // Yellow 0.424, silver 0.415 and pearl white 0.806 are over it; blue stays white.
        assertEquals(.424, botUiLuminance(0xFFD8A729), .001)
        assertEquals(.415, botUiLuminance(0xFFA8ADB4), .001)
        assertEquals(.806, botUiLuminance(0xFFE6E8EC), .001)
        assertEquals(dark, auto(7))
        assertEquals(dark, auto(10))
        assertEquals(dark, auto(11))
        assertEquals(white, auto(1))
        // Of the twelve, exactly those three.
        assertEquals(setOf(7, 10, 11), (0 until BotUiProfile.COLORS).filter { auto(it) == dark }.toSet())
        // A chosen colour wins over the body; a profile from the six-colour generation always matches its body.
        assertEquals(white, botUiInk(BotUiProfile(color = 11, face = 1, palette = 2)))
        assertEquals(dark, botUiInk(BotUiProfile(color = 1, face = 2, palette = 2)))
        assertEquals(dark, botUiInk(BotUiProfile(color = 5, face = 1)))
        assertEquals(white, botUiInk(BotUiProfile(color = 0, face = 2)))
    }

    @Test fun twelveColoursTenOutlinesTenExpressions() {
        assertEquals(BotUiProfile.COLORS, BotUiAvatarColors.size)
        assertEquals(0xFFE6E8EC, BotUiAvatarColors.last().argb)
        assertEquals(BotUiProfile.SHAPES, BotUiHelmetOutlines.size)
        assertEquals(BotUiProfile.EXPRESSIONS, BotUiHelmetExpressions.size)
        assertTrue(BotUiHelmetExpressions.all { it.marks.isNotEmpty() })
    }

    @Test fun everyPathParses() {
        val marks = BotUiHelmetExpressions.flatMap { it.marks }.mapNotNull {
            when (it) {
                is BotUiHelmetMark.Line -> it.path
                is BotUiHelmetMark.Fill -> it.path
                else -> null
            }
        }
        for (d in BotUiHelmetOutlines.map { it.path } + marks + HELMET_HIGHLIGHT) {
            assertWholeArguments(d)
            val nodes = PathParser().parsePathString(d).toNodes()
            assertTrue(d, nodes.first() is PathNode.MoveTo)
        }
        // Each outline is a single closed shape.
        for (outline in BotUiHelmetOutlines) {
            val nodes = PathParser().parsePathString(outline.path).toNodes()
            assertEquals(outline.path, 1, nodes.count { it is PathNode.MoveTo || it is PathNode.RelativeMoveTo })
            assertTrue(outline.path, nodes.last() is PathNode.Close)
        }
    }

    /** The parser drops a number left over from a command, so each command's numbers must come in whole groups (A takes 7). */
    private fun assertWholeArguments(d: String) {
        val arity = mapOf('M' to 2, 'L' to 2, 'T' to 2, 'H' to 1, 'V' to 1, 'C' to 6, 'S' to 4, 'Q' to 4, 'A' to 7, 'Z' to 0)
        val number = Regex("""-?(\d+\.?\d*|\.\d+)""")
        for (m in Regex("""([A-Za-z])([^A-Za-z]*)""").findAll(d)) {
            val n = arity.getValue(m.groupValues[1].single().uppercaseChar())
            val count = number.findAll(m.groupValues[2]).count()
            assertTrue("$d: ${m.value}", if (n == 0) count == 0 else count > 0 && count % n == 0)
        }
    }
}
