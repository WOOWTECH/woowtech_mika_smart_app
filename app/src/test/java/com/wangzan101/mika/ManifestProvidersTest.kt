package com.wangzan101.mika

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/** 清单里会让进程一启动就崩的配置,在电脑上先拦住(真机才会暴露的那一类)。 */
class ManifestProvidersTest {

    private val androidNs = "http://schemas.android.com/apk/res/android"

    @Test
    fun fileProvidersGrantUriPermissionsAndStayPrivate() {
        val manifest = File("src/main/AndroidManifest.xml")
        assertTrue("manifest not found from ${File(".").absolutePath}", manifest.exists())
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(manifest)
        val providers = doc.getElementsByTagName("provider")
        var fileProviders = 0
        for (i in 0 until providers.length) {
            val p = providers.item(i) as Element
            val metas = p.getElementsByTagName("meta-data")
            val isFileProvider = (0 until metas.length).any {
                (metas.item(it) as Element).getAttributeNS(androidNs, "name") == "android.support.FILE_PROVIDER_PATHS"
            }
            if (!isFileProvider) continue
            fileProviders++
            val name = p.getAttributeNS(androidNs, "name")
            // FileProvider.attachInfo 在 grantUriPermissions 不为 true 时抛 SecurityException,进程起不来
            assertEquals("$name grantUriPermissions", "true", p.getAttributeNS(androidNs, "grantUriPermissions"))
            assertEquals("$name exported", "false", p.getAttributeNS(androidNs, "exported"))
        }
        assertTrue("expected at least one FileProvider", fileProviders > 0)
    }

    /**
     * WOOWTECH Play branch: the Play manifest has none of the components that only the built-in shell helper, a computer
     * over adb or the compatibility self check could reach (phone control is out of this edition), and nothing asks for
     * shell-level permission. The computer connection is the outbound relay only (owner decision 2026-11-18): its
     * service is declared but not exported, so adb cannot start it to turn on the USB mode.
     */
    @Test
    fun playManifestHasNoShellOnlyComponents() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val components = listOf("activity", "service", "receiver", "provider").flatMap { tag ->
            val nodes = doc.getElementsByTagName(tag)
            (0 until nodes.length).map { nodes.item(it) as Element }
        }
        val names = components.map { it.getAttributeNS(androidNs, "name") }
        for (gone in listOf(".shell.HelperHandoffProvider", ".selfcheck.SelfCheckTargetActivity")) {
            assertTrue("$gone must not be in the Play manifest", gone !in names)
        }
        val relay = components.single { it.getAttributeNS(androidNs, "name") == ".mcp.McpService" }
        assertEquals("false", relay.getAttributeNS(androidNs, "exported"))
        for (c in components) {
            assertTrue(c.getAttributeNS(androidNs, "name"), c.getAttributeNS(androidNs, "permission") != "android.permission.INTERACT_ACROSS_USERS_FULL")
        }
    }

    /** 清单里登记的组件都按全名找得到类(搬了代码的入口留着同名的薄壳)。 */
    @Test
    fun everyComponentClassExists() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val names = listOf("application", "activity", "service", "receiver", "provider").flatMap { tag ->
            val nodes = doc.getElementsByTagName(tag)
            (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(androidNs, "name") }
        }
        assertTrue(names.size > 5)
        for (n in names) {
            val full = if (n.startsWith(".")) "com.wangzan101.mika$n" else n
            assertTrue("$full is not a class", runCatching { Class.forName(full, false, javaClass.classLoader) }.isSuccess)
        }
    }

    /**
     * 测试 APK 清单里的页面、服务运行在测试包自己的进程里,那里没有 Kotlin 标准库(和 App 重复的依赖不打进测试 APK):
     * 每个都要有同名的 Java 源文件。类名对不上、或写成 Kotlin,真机上一打开就崩,读屏只读到一块空屏。
     */
    @Test
    fun testApkComponentsAreJavaClassesWithMatchingNames() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/androidTest/AndroidManifest.xml"))
        val names = listOf("activity", "service", "receiver", "provider").flatMap { tag ->
            val nodes = doc.getElementsByTagName(tag)
            (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(androidNs, "name") }
        }
        assertTrue(names.isNotEmpty())
        for (n in names) {
            val path = "src/androidTest/java/${n.replace('.', '/')}"
            assertTrue("$n has no Java source at $path.java", File("$path.java").isFile)
        }
    }

    /**
     * 拍照附件走系统相机:声明用到相机、但不是必需(没有相机的设备照常安装)。这条声明不能删:
     * 有的系统按 APK 特征给应用分类,没有它时 Mika 可能被当成游戏、限制刷新率。
     */
    @Test
    fun cameraIsDeclaredAsOptionalFeature() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val features = doc.getElementsByTagName("uses-feature")
        val camera = (0 until features.length).map { features.item(it) as Element }
            .singleOrNull { it.getAttributeNS(androidNs, "name") == "android.hardware.camera" }
        assertTrue("uses-feature android.hardware.camera is missing", camera != null)
        assertEquals("false", camera!!.getAttributeNS(androidNs, "required"))
    }

    /** 内置助手进程按这个全名启动。 */
    @Test
    fun helperEntryClassExists() {
        val c = Class.forName(com.wangzan101.mika.core.shell.HelperHandoff.HELPER_CLASS, false, javaClass.classLoader)
        assertTrue(c.methods.any { it.name == "main" && java.lang.reflect.Modifier.isStatic(it.modifiers) })
    }
}
