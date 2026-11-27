// apporoplay (Apporo's Google Play edition): the licenses list. Not part of upstream Mika; see docs-woowtech/FORK.md.
// Modelled on the woowtech Play edition's app/src/woowtech/java/com/wangzan101/mika/woowtech/BrandLicenses.kt.
package com.wangzan101.mika.woowtech

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.wangzan101.mika.R
import com.wangzan101.mika.core.brand.Brand
import com.wangzan101.mika.ui.Licenses

/**
 * Apporo 商店版的第三方元件清單,跟著 App 語言顯示英文或繁中(上游的說明寫死簡體中文)。
 * 和渥屋商店版一樣:上游 Mika 列在第一個(署名 wangzan101);不包含跨 App OCR(ML Kit)與沙箱(運行環境的套件)。
 * 譯文是 src/apporoplay/res 的 woow_lic_* 字串(和 Apporo 直裝版同名,內容寫商店版)。
 * 同步上游後新增、還沒翻譯的條目照上游原文顯示,只換產品名。
 */
object BrandLicenses {
    private class Text(val note: Int, val name: Int? = null, val license: Int? = null)

    /** The Play edition omits cross-app OCR and the executable sandbox, including its GPL runtime. */
    private val OMITTED = setOf("PRoot", "talloc", "scrcpy", "Alpine Linux")

    private val TEXTS = mapOf(
        "Mika" to Text(R.string.woow_lic_mika),
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
        "XZ for Java" to Text(R.string.woow_lic_xz),
        "commonmark-java" to Text(R.string.woow_lic_commonmark),
    )

    @Composable
    fun thirdParty(entries: List<Licenses.Entry>, @Suppress("UNUSED_PARAMETER") runtime: List<Licenses.Entry>): List<Licenses.Entry> =
        entries.filter { it.name !in OMITTED }.map { e ->
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
}
