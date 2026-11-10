package com.wangzan101.mika.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.IntSize
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * WOOWTECH fork: 要你处理时小窗从下方的角挪到同侧上方,让开卡片上的按钮(「允许这一次」「我来处理」…);
 * 回到干活时挪回原来的角。等你的时候用户自己拖过,就停在他拖到的角,不再替他挪。
 * 关了动画(reduceMotion)时弹簧直接到位,不用等动画。
 */
@RunWith(AndroidJUnit4::class)
class AgentPipCornerTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = com.wangzan101.mika.CloseComposeActivity(compose)

    @Test fun movesUpWhileItNeedsYouAndBackWhenRunning() {
        var pip by mutableStateOf(PipUi(visible = true))
        compose.setContent {
            AgentPip(pip, null, webContent = false, reduceMotion = true,
                topInset = 0f, bottomInset = 120f, onExpand = {}, onCollapse = {}, onAttention = {})
        }
        val start = window()
        assertTrue("starts in the bottom-end corner: $start in ${root()}", start.top > root().height / 2f && start.left > root().width / 2f)

        compose.runOnIdle { pip = pip.copy(mode = PipMode.NeedsYou) }
        val raised = window()
        assertTrue("moved to the top-end corner while it needs you: $raised in ${root()}",
            raised.bottom < root().height / 2f && raised.left > root().width / 2f)

        compose.runOnIdle { pip = pip.copy(mode = PipMode.Running) }
        assertEquals("back in the corner it came from", start, window())
    }

    @Test fun staysWhereTheUserDraggedItWhileItNeededYou() {
        var pip by mutableStateOf(PipUi(visible = true))
        compose.setContent {
            AgentPip(pip, null, webContent = false, reduceMotion = true,
                topInset = 0f, bottomInset = 120f, onExpand = {}, onCollapse = {}, onAttention = {})
        }
        compose.runOnIdle { pip = pip.copy(mode = PipMode.NeedsYou) }
        val raised = window()
        assertTrue("moved up while it needs you: $raised in ${root()}", raised.bottom < root().height / 2f)

        // 拖到左下角(挪上去之前在右下角):松手吸到左下角
        val target = Offset(root().width * 0.2f, root().height * 0.8f)
        compose.onNodeWithTag("pip-window").performTouchInput { swipe(center, target - raised.topLeft) }
        val dragged = window()
        assertTrue("snapped to the bottom-start corner: $dragged in ${root()}",
            dragged.left < root().width / 2f && dragged.top > root().height / 2f)

        // 拖过就不再替他挪回右下角
        compose.runOnIdle { pip = pip.copy(mode = PipMode.Running) }
        assertEquals("stays where the user put it", dragged, window())
    }

    private fun window(): Rect {
        compose.waitForIdle()
        return compose.onNodeWithTag("pip-window").fetchSemanticsNode().boundsInRoot
    }

    private fun root(): IntSize = compose.onRoot().fetchSemanticsNode().size
}
