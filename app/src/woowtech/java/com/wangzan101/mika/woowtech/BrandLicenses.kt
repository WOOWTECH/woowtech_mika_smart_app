// WOOWTECH fork: the woowtech flavor's licenses list. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.woowtech

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.wangzan101.mika.R
import com.wangzan101.mika.core.brand.Brand
import com.wangzan101.mika.ui.Licenses

/**
 * 品牌版的第三方元件清單,跟著 App 語言顯示英文或繁中(上游的說明寫死簡體中文)。
 * 上游 Mika 列在第一個(署名 wangzan101),補上上游清單漏掉的 ML Kit,運行環境的套件接在最後(版本那句也翻譯)。
 * 每個上游條目在 [TEXTS] 有一組譯文(woowtech/tools/brand-check.sh sources 會核對)。
 * 同步上游後新增、還沒翻譯的條目照上游原文顯示,只換產品名。
 */
object BrandLicenses {
    private class Text(val note: Int, val name: Int? = null, val license: Int? = null)

    private val TEXTS = mapOf(
        "Mika" to Text(R.string.woow_lic_mika),
        "PRoot" to Text(R.string.woow_lic_proot),
        "talloc" to Text(R.string.woow_lic_talloc),
        "Apache Commons Compress" to Text(R.string.woow_lic_commons_compress),
        "Apache Commons Codec" to Text(R.string.woow_lic_commons_codec),
        "Apache Commons IO" to Text(R.string.woow_lic_commons_io),
        "Apache Commons Lang" to Text(R.string.woow_lic_commons_lang),
        "Kotlin 标准库" to Text(R.string.woow_lic_kotlin, name = R.string.woow_lic_kotlin_name),
        "kotlinx.coroutines" to Text(R.string.woow_lic_coroutines),
        "kotlinx.serialization" to Text(R.string.woow_lic_serialization),
        "OpenTelemetry" to Text(R.string.woow_lic_opentelemetry),
        "Protocol Buffers" to Text(R.string.woow_lic_protobuf),
        "OkHttp" to Text(R.string.woow_lic_okhttp),
        "Okio" to Text(R.string.woow_lic_okio),
        "AndroidX(含 Jetpack Compose)" to Text(R.string.woow_lic_androidx, name = R.string.woow_lic_androidx_name),
        "Guava ListenableFuture(由 AndroidX 库引入)" to Text(R.string.woow_lic_guava, name = R.string.woow_lic_guava_name),
        "scrcpy" to Text(R.string.woow_lic_scrcpy),
        "Alpine Linux" to Text(R.string.woow_lic_alpine, license = R.string.woow_lic_alpine_license),
        "XZ for Java" to Text(R.string.woow_lic_xz),
        "commonmark-java" to Text(R.string.woow_lic_commonmark),
    )

    /** 運行環境套件的說明「版本 <x>。<網址>」(Licenses.runtimePackages)。 */
    private val RUNTIME_NOTE = Regex("^版本 (.*?)。(.*)$")

    @Composable
    fun thirdParty(entries: List<Licenses.Entry>, runtime: List<Licenses.Entry>): List<Licenses.Entry> {
        val upstream = entries.map { e ->
            val t = TEXTS[e.name]
            if (t == null) {
                e.copy(note = Brand.text(e.note))
            } else {
                Licenses.Entry(
                    name = if (t.name == null) e.name else stringResource(t.name),
                    license = if (t.license == null) e.license else stringResource(t.license),
                    note = stringResource(t.note),
                )
            }
        }
        val mlKit = Licenses.Entry(
            stringResource(R.string.woow_lic_mlkit_name), stringResource(R.string.woow_lic_mlkit_license), stringResource(R.string.woow_lic_mlkit),
        )
        val packages = runtime.map { e ->
            val m = RUNTIME_NOTE.matchEntire(e.note)
            if (m == null) e else e.copy(note = stringResource(R.string.woow_lic_runtime_package, m.groupValues[1], m.groupValues[2]).trim())
        }
        return upstream.filter { it.name == "Mika" } + upstream.filter { it.name != "Mika" } + mlKit + packages
    }
}
