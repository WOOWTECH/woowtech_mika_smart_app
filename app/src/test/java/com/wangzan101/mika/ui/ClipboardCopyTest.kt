// WOOWTECH fork: test for the shared copy helper (not in upstream Mika).
package com.wangzan101.mika.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 复制后的「已复制」:安卓 12L 及以下由 App 的 Toast 说;13 起系统自己弹浮层,App 不再弹,免得两个叠在一起。 */
class ClipboardCopyTest {
    @Test fun appSaysCopiedOnlyBeforeAndroid13() {
        assertTrue("安卓 11(最低支持)", copiedToastNeeded(30))
        assertTrue("安卓 12L", copiedToastNeeded(32))
        assertFalse("安卓 13 起系统自己提示", copiedToastNeeded(33))
        assertFalse(copiedToastNeeded(36))
    }
}
