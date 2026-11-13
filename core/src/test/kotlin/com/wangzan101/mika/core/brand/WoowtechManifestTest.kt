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
 * Both Play flavors are guarded: woowtech and apporoplay (Apporo's Play edition, whose manifest mirrors woowtech's).
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
        assertOnlyRemovesDataSync("woowtech/AndroidManifest.xml")
    }

    /** Same for apporoplay: src/apporo's exact-alarm permissions must not come along. */
    @Test
    fun apporoplayFlavorManifestAddsNoOtherPermission() {
        assertOnlyRemovesDataSync("apporoplay/AndroidManifest.xml")
    }

    private fun assertOnlyRemovesDataSync(path: String) {
        assertEquals(setOf("android.permission.FOREGROUND_SERVICE_DATA_SYNC"), permissions(path).keys)
        val removed = manifest(path).getElementsByTagName("uses-permission").item(0) as Element
        assertEquals("remove", removed.getAttributeNS("http://schemas.android.com/tools", "node"))
        // The flavor manifest has a higher priority than src/main; the package comes from the module's namespace.
        assertFalse(manifest(path).hasAttribute("package"))
    }

    /** Both Play flavors take the same src/main components out (sandbox preparation, pairing-code receiver). */
    @Test
    fun playFlavorsRemoveTheSameComponents() {
        fun removed(path: String): Set<String> = listOf("service", "receiver", "provider", "activity").flatMap { tag ->
            val nodes = manifest(path).getElementsByTagName(tag)
            (0 until nodes.length).map { nodes.item(it) as Element }
        }.filter { it.getAttributeNS("http://schemas.android.com/tools", "node") == "remove" }
            .map { it.getAttributeNS(androidNs, "name") }.toSet()
        assertEquals(setOf(".sandbox.SandboxService", ".setup.PairingCodeReceiver"), removed("woowtech/AndroidManifest.xml"))
        assertEquals(removed("woowtech/AndroidManifest.xml"), removed("apporoplay/AndroidManifest.xml"))
    }

    /** PlayTransportPolicy's HTTPS rule holds at the platform too: no cleartext except to this phone (src/main allows it). */
    @Test
    fun playFlavorsAllowCleartextOnlyOnThePhone() {
        for (flavor in listOf("woowtech", "apporoplay")) {
            val config = manifest("$flavor/res/xml/network_security_config.xml") // any XML file; asserts it exists
            val base = config.getElementsByTagName("base-config").item(0) as Element
            assertEquals(flavor, "false", base.getAttribute("cleartextTrafficPermitted"))
            val domains = config.getElementsByTagName("domain")
            assertEquals(flavor, setOf("localhost", "127.0.0.1"), (0 until domains.length).map { domains.item(it).textContent.trim() }.toSet())
        }
    }

    /** Settings › Privacy policy (MainActivity) opens the flavor's play_privacy_policy_url; src/main leaves it empty. */
    @Test
    fun playFlavorsLinkTheirOwnPrivacyPolicy() {
        val expected = mapOf(
            "woowtech" to "https://assistant-relay.woowtech.io/privacy/play",
            "apporoplay" to "https://assistant-relay.apporo.ai/privacy/play",
        )
        for ((flavor, url) in expected) {
            val found = File(app, "$flavor/res/values").listFiles { f -> f.name.endsWith(".xml") }.orEmpty().flatMap { f ->
                val nodes = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(f).getElementsByTagName("string")
                (0 until nodes.length).map { nodes.item(it) as Element }
                    .filter { it.getAttribute("name") == "play_privacy_policy_url" }.map { it.textContent }
            }
            assertEquals(flavor, listOf(url), found)
        }
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
        assertIsolatedBrowserEntry("woowtech/AndroidManifest.xml", ".woowtech.BrowserOpenActivity")
    }

    /** apporoplay registers Apporo's entry class (its own copy in src/apporoplay/java). */
    @Test
    fun apporoplayBrowserEntryIsIsolatedAndUsesTheInstalledPackageScheme() {
        assertIsolatedBrowserEntry("apporoplay/AndroidManifest.xml", ".apporo.BrowserOpenActivity")
    }

    private fun assertIsolatedBrowserEntry(path: String, activityName: String) {
        val root = manifest(path)
        val activities = root.getElementsByTagName("activity")
        assertEquals(1, activities.length)
        val entry = activities.item(0) as Element
        assertEquals(activityName, entry.getAttributeNS(androidNs, "name"))
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
