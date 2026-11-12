// WOOWTECH Play branch: guards restricted alarm permissions of the branded manifest.
package com.wangzan101.mika.core.brand

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The Play edition has no background alarm capability or alarm permission.
 */
class WoowtechManifestTest {
    private val androidNs = "http://schemas.android.com/apk/res/android"
    private val app = File("../app/src")

    private fun manifest(path: String): Element {
        val file = File(app, path)
        assertTrue("$file not found from ${File(".").absolutePath}", file.isFile)
        return DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(file).documentElement
    }

    /** The manifest's uses-permission elements, each name once: permission name to its maxSdkVersion ("" when it has none). */
    private fun permissions(path: String): Map<String, String> {
        val nodes = manifest(path).getElementsByTagName("uses-permission")
        val all = (0 until nodes.length).map { nodes.item(it) as Element }
            .map { it.getAttributeNS(androidNs, "name") to it.getAttributeNS(androidNs, "maxSdkVersion") }
        assertEquals("$path declares a permission twice", all.map { it.first }.toSet().size, all.size)
        return all.toMap()
    }

    /** A new permission in the Play build is a product decision and needs policy review. */
    @Test
    fun woowtechFlavorManifestAddsNoOtherPermission() {
        assertEquals(setOf("android.permission.FOREGROUND_SERVICE_DATA_SYNC"), permissions("woowtech/AndroidManifest.xml").keys)
        val removed = manifest("woowtech/AndroidManifest.xml").getElementsByTagName("uses-permission").item(0) as Element
        assertEquals("remove", removed.getAttributeNS("http://schemas.android.com/tools", "node"))
        // The flavor manifest has a higher priority than src/main; the package comes from the module's namespace.
        assertFalse(manifest("woowtech/AndroidManifest.xml").hasAttribute("package"))
    }

    /** No alarm permission may be brought into the Play build. */
    @Test
    fun playManifestHasNoExactAlarmPermissions() {
        val main = permissions("main/AndroidManifest.xml")
        assertFalse("SCHEDULE_EXACT_ALARM must not be in the Play manifest", SCHEDULE_EXACT_ALARM in main)
        assertFalse("USE_EXACT_ALARM must not be in the shared manifest", USE_EXACT_ALARM in main)
        assertFalse("the upstream flavor must not get a manifest of its own", File(app, "upstream/AndroidManifest.xml").exists())
    }

    @Test
    fun playManifestHasNoCrossAppControlOrApkInstallEntry() {
        val main = manifest("main/AndroidManifest.xml")
        val requested = permissions("main/AndroidManifest.xml").keys
        listOf(
            "android.permission.REQUEST_INSTALL_PACKAGES",
            "android.permission.WRITE_SECURE_SETTINGS",
            "android.permission.READ_MEDIA_IMAGES",
            "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            "android.permission.RECEIVE_BOOT_COMPLETED",
        ).forEach { assertFalse("Play manifest requests $it", it in requested) }
        val components = listOf("service", "provider", "receiver", "activity")
            .flatMap { tag -> main.getElementsByTagName(tag).let { nodes ->
                (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(androidNs, "name") }
            } }
        listOf("MikaAccessibilityService", "HelperHandoffProvider", "BootRestoreReceiver", "SelfCheckTargetActivity")
            .forEach { forbidden -> assertFalse("Play manifest still exposes $forbidden", components.any { it.endsWith(forbidden) }) }
    }

    @Test
    fun browserEntryIsIsolatedAndUsesTheInstalledPackageScheme() {
        val root = manifest("woowtech/AndroidManifest.xml")
        val activities = root.getElementsByTagName("activity")
        assertEquals(1, activities.length)
        val entry = activities.item(0) as Element
        assertEquals(".woowtech.BrowserOpenActivity", entry.getAttributeNS(androidNs, "name"))
        assertEquals("true", entry.getAttributeNS(androidNs, "exported"))
        assertEquals("true", entry.getAttributeNS(androidNs, "noHistory"))
        assertEquals("", entry.getAttributeNS(androidNs, "taskAffinity"))
        val filter = entry.getElementsByTagName("intent-filter")
        assertEquals(1, filter.length)
        val data = entry.getElementsByTagName("data").item(0) as Element
        assertEquals("${'$'}{applicationId}", data.getAttributeNS(androidNs, "scheme"))
        assertEquals("open", data.getAttributeNS(androidNs, "host"))
        val actions = entry.getElementsByTagName("action")
        assertEquals(1, actions.length)
        assertEquals("android.intent.action.VIEW", (actions.item(0) as Element).getAttributeNS(androidNs, "name"))
        val categories = entry.getElementsByTagName("category")
        assertEquals(setOf("android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"),
            (0 until categories.length).map { (categories.item(it) as Element).getAttributeNS(androidNs, "name") }.toSet())
        val mainActivities = manifest("main/AndroidManifest.xml").getElementsByTagName("activity")
        for (i in 0 until mainActivities.length) {
            val activity = mainActivities.item(i) as Element
            assertFalse(activity.getAttributeNS(androidNs, "name").contains("BrowserOpenActivity"))
            val cats = activity.getElementsByTagName("category")
            for (j in 0 until cats.length) {
                assertFalse((cats.item(j) as Element).getAttributeNS(androidNs, "name") == "android.intent.category.BROWSABLE")
            }
        }
    }

    private companion object {
        const val USE_EXACT_ALARM = "android.permission.USE_EXACT_ALARM"
        const val SCHEDULE_EXACT_ALARM = "android.permission.SCHEDULE_EXACT_ALARM"
    }
}
