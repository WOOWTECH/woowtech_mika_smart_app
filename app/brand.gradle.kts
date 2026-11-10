// WOOWTECH fork: brand layer (渥屋助理 / woowtech agent). Not part of upstream Mika; see docs-woowtech/FORK.md.
// Applied at the end of app/build.gradle.kts, which then wires the flavors with what this script leaves in `extra`
// (a script plugin cannot see the Android Gradle plugin's classes, so nothing here uses its types).
//
// - Flavor dimension "brand": `upstream` is upstream Mika unchanged (the baseline for upstream's unit and golden
//   tests); `woowtech` builds io.woowtech.agent. Unit and instrumented tests run on `upstream` only.
// - woowtech UI strings: while Gradle configures the project, every string in src/main/res (values,
//   values-b+zh+Hant) that names Mika or links the upstream repo is copied with the brand name and repo into
//   app/.gradle/woowtech-brand-res (git-ignored, survives `clean`), which is added to the woowtech source set.
//   Keys hand-written in src/woowtech/res/<same folder> are skipped there. Links to upstream docs/<file>.md
//   point to docs-woowtech/<file>.md instead when that file exists (WOOWTECH's own guide, right package name).
// - Release signing: WOOWTECH_SIGNING_PROPERTIES may point to a properties file outside the repo (storeFile,
//   storePassword, keyAlias, keyPassword). Without it the woowtech release APK is unsigned (CI) and is signed
//   afterwards with apksigner on the release machine.

import java.io.File
import java.util.Properties

/** Brand releases made on the current upstream version: versionName gets `-woow.<N>`, versionCode `×100 + N`. */
val woowtechRevision = 6
require(woowtechRevision in 1..99) { "woowtechRevision must be 1..99 to preserve versionCode ordering" }

val brandProps = Properties().apply {
    file("src/woowtech/resources/brand.properties").reader(Charsets.UTF_8).use { load(it) }
}

// ---- woowtech UI strings ----------------------------------------------------------------------------------

val woowtechBrandRes: File = file(".gradle/woowtech-brand-res")

/** One string resource element: (1) opening tag, (2) tag, (3) name, (4) body, (5) closing tag. Self-closing tags never match. */
val brandElement = Regex(
    """(<(string|plurals|string-array)\b[^>]*\bname="([^"]+)"[^>]*(?<!/)>)(.*?)(</\2>)""",
    RegexOption.DOT_MATCHES_ALL,
)
val brandNameDefinition = Regex("""<(?:string|plurals|string-array)\b[^>]*\bname="([^"]+)"""")

/** Same rule as core's Brand.text: a standalone "Mika", not inside identifiers, paths or URLs. */
val brandMika = Regex("""( ?)(?<![A-Za-z0-9_/.@\-])Mika(?![A-Za-z0-9_/\-])( ?)""")

fun brandCjk(c: Char?): Boolean = c != null &&
    (Character.UnicodeScript.of(c.code) == Character.UnicodeScript.HAN || c in '　'..'〿' || c in '＀'..'￯')

fun brandText(s: String, name: String, chinese: Boolean): String = brandMika.replace(s) { m ->
    if (!chinese) return@replace m.groupValues[1] + name + m.groupValues[2]
    val before = s.getOrNull(m.range.first - 1)
    val after = s.getOrNull(m.range.last + 1)
    // 中文:和汉字、全形标点、标签之间不留空格;挨着英文字母或数字时保留原本的空格
    val lead = if (before == null || before == '>' || brandCjk(before)) "" else m.groupValues[1]
    val trail = if (after == null || after == '<' || brandCjk(after)) "" else m.groupValues[2]
    lead + name + trail
}

/** An upstream docs link: (1) up to `blob/main/`, (2) the file name under docs/. */
val brandDocLink = Regex("""(github\.com/wangzan101/Mika/blob/main/)docs/([A-Za-z0-9._-]+\.md)""")

/** Upstream docs links whose WOOWTECH version exists (docs-woowtech/, same file name) point to it. */
fun brandDocs(s: String): String = brandDocLink.replace(s) { m ->
    if (rootProject.file("docs-woowtech/${m.groupValues[2]}").isFile) m.groupValues[1] + "docs-woowtech/" + m.groupValues[2] else m.value
}

fun generateBrandStrings(brand: String, brandProps: Properties, output: File) {
    val upstreamRepo = "github.com/wangzan101/Mika"
    val repoLabel = brandProps.getProperty("repo.label")
    val names = mapOf("values" to brandProps.getProperty("name"), "values-b+zh+Hant" to brandProps.getProperty("name.zh"))
    output.deleteRecursively()
    for ((folder, name) in names) {
        val chinese = folder != "values"
        val manual = file("src/$brand/res/$folder").listFiles { f -> f.name.endsWith(".xml") }.orEmpty()
            .flatMap { f -> brandNameDefinition.findAll(f.readText()).map { it.groupValues[1] }.toList() }
            .toSet() + "app_name"
        val out = StringBuilder()
        file("src/main/res/$folder").listFiles { f -> f.name.startsWith("strings") && f.name.endsWith(".xml") }.orEmpty()
            .sortedBy { it.name }
            .forEach { f ->
                brandElement.findAll(f.readText()).forEach { m ->
                    val body = m.groupValues[4]
                    if (m.groupValues[3] !in manual) {
                        val docs = if (brand == "woowtech") brandDocs(body) else body
                        val branded = brandText(docs.replace(upstreamRepo, repoLabel), name, chinese)
                        if (branded != body) out.append("    ").append(m.groupValues[1]).append(branded).append(m.groupValues[5]).append('\n')
                    }
                }
            }
        if (out.isEmpty()) continue
        File(output, folder).apply { mkdirs() }.resolve("strings_woowtech_generated.xml").writeText(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                "<!-- Generated by app/brand.gradle.kts from src/main/res/$folder; do not edit. -->\n" +
                "<resources xmlns:tools=\"http://schemas.android.com/tools\" xmlns:xliff=\"urn:oasis:names:tc:xliff:document:1.2\">\n" +
                out + "</resources>\n",
        )
    }
}

generateBrandStrings("woowtech", brandProps, woowtechBrandRes)
val apporoBrandRes = file(".gradle/apporo-brand-res")
val apporoProps = Properties().apply { file("src/apporo/resources/brand.properties").reader(Charsets.UTF_8).use { load(it) } }
generateBrandStrings("apporo", apporoProps, apporoBrandRes)
extra["apporoBrandRes"] = apporoBrandRes

// ---- handed to app/build.gradle.kts ------------------------------------------------------------------------

extra["woowtechRevision"] = woowtechRevision
extra["woowtechBrandRes"] = woowtechBrandRes
extra["woowtechSigning"] = System.getenv("WOOWTECH_SIGNING_PROPERTIES")?.let { file(it) }?.takeIf { it.isFile }
    ?.let { f -> Properties().apply { f.reader(Charsets.UTF_8).use { load(it) } } }
