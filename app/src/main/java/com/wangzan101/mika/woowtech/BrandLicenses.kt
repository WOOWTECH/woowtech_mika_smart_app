// WOOWTECH fork: brand layer additions to the licenses page. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.woowtech

import com.wangzan101.mika.core.brand.Brand
import com.wangzan101.mika.ui.Licenses

/**
 * 品牌版的许可证页:上游 Mika 本身改成列在第三方组件里(Apache-2.0,署名 wangzan101),
 * 其他条目说明里的产品名换成品牌名,再补上上游清单漏掉的 ML Kit。没有品牌设定时原样返回上游清单。
 */
object BrandLicenses {
    fun thirdParty(entries: List<Licenses.Entry>): List<Licenses.Entry> {
        if (!Brand.branded) return entries.filter { it.name != "Mika" }
        val upstream = Licenses.Entry(
            "Mika", "Apache-2.0",
            "本 App 以開源專案 Mika（Copyright 2026 wangzan101，https://github.com/wangzan101/Mika）為基礎，" +
                "由 WOOW TECH CO., LTD. 修改與發行；修改內容見原始碼倉庫的 docs-woowtech/FORK.md。上游的 NOTICE 隨原始碼保留。",
        )
        val mlKit = Licenses.Entry(
            "Google ML Kit 文字辨識", "Google APIs 服務條款與 ML Kit 服務條款",
            "辨識畫面上的文字（含中文）的模型隨安裝包提供，不經過 Google Play 服務下載。https://developers.google.com/ml-kit/terms",
        )
        return listOf(upstream) + entries.filter { it.name != "Mika" }.map { it.copy(note = Brand.text(it.note)) } + mlKit
    }
}
