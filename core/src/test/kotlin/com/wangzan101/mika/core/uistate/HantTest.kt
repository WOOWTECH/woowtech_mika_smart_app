package com.wangzan101.mika.core.uistate

import org.junit.Assert.assertEquals
import org.junit.Test

class HantTest {
    // 两串逐字配对:长度不等会悄悄截断、整张表错位;一个繁体字只能对一个简体字
    @Test fun tableLinesUp() {
        assertEquals(Hant.TRADITIONAL.length, Hant.SIMPLIFIED.length)
        assertEquals(Hant.TRADITIONAL.length, Hant.TRADITIONAL.toSet().size)
        assertEquals("", Hant.TRADITIONAL.filter { it in Hant.SIMPLIFIED })
    }

    @Test fun foldsWordsToSimplified() {
        assertEquals("注销账户", Hant.fold("註銷帳户"))
        assertEquals("回复", Hant.fold("回覆"))
        assertEquals("发布", Hant.fold("發佈"))
        assertEquals("联系对方", Hant.fold("聯繫對方"))
        assertEquals("已经简体", Hant.fold("已经简体"))
    }

    // 台湾付款界面的字:紀錄、匯款、簽帳卡、悠遊付
    @Test fun foldsTaiwanPaymentWords() {
        assertEquals("付款纪录", Hant.fold("付款紀錄"))
        assertEquals("ATM汇款", Hant.fold("ATM匯款"))
        assertEquals("签账卡", Hant.fold("簽帳卡"))
        assertEquals("悠游付", Hant.fold("悠遊付"))
        assertEquals("送出订单", Hant.fold("送出訂單"))
    }
}
