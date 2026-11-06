// WOOWTECH fork: the upstream flavor's licenses list, exactly upstream's. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.woowtech

import androidx.compose.runtime.Composable
import com.wangzan101.mika.ui.Licenses

/** 上游 flavor:许可证页的第三方组件清单和上游一样(Mika 本身不列,运行环境的软件包接在后面)。woowtech flavor 有自己的一份。 */
object BrandLicenses {
    @Composable
    fun thirdParty(entries: List<Licenses.Entry>, runtime: List<Licenses.Entry>): List<Licenses.Entry> =
        entries.filter { it.name != "Mika" } + runtime
}
