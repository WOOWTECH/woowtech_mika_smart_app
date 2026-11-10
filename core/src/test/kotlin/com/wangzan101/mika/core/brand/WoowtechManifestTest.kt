// WOOWTECH fork: guards the exact alarm permissions of the woowtech flavor manifest. Not part of upstream Mika.
package com.wangzan101.mika.core.brand

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Reminders and scheduled tasks arm an exact alarm (TriggerRuntime.arm) only when canScheduleExactAlarms() is true; an
 * inexact alarm can be delivered late by up to 3/4 of the wait, at most an hour. From Android 14 SCHEDULE_EXACT_ALARM is
 * denied for a fresh install, so the woowtech flavor declares USE_EXACT_ALARM in app/src/woowtech/AndroidManifest.xml. That
 * build is an APK-only release: Google Play limits the permission to alarm, timer and calendar apps. The upstream flavor has
 * no manifest of its own and keeps src/main's user-granted SCHEDULE_EXACT_ALARM. These tests keep the files from drifting
 * apart; brand-check.sh apk checks the same two lines in the built APK.
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

    /** USE_EXACT_ALARM is what makes canScheduleExactAlarms() true without the user: it has to be there for every API level. */
    @Test
    fun woowtechFlavorDeclaresUseExactAlarmForEveryApiLevel() {
        val flavor = permissions("woowtech/AndroidManifest.xml")
        assertTrue(flavor.toString(), USE_EXACT_ALARM in flavor)
        // The system ignores a permission on API levels above its maxSdkVersion: a limit would turn it off on newer Android.
        assertEquals("USE_EXACT_ALARM must not have a maxSdkVersion", "", flavor[USE_EXACT_ALARM])
    }

    /**
     * Only one of the two permissions should be requested on a device (AOSP documentation of USE_EXACT_ALARM). Android 12
     * and 12L have no USE_EXACT_ALARM and grant SCHEDULE_EXACT_ALARM at install, so it stays for API 32 and below only.
     * The element merges with the one in src/main, which declares it for every API level.
     */
    @Test
    fun woowtechFlavorRequestsOnlyOneExactAlarmPermissionPerDevice() {
        assertEquals("32", permissions("woowtech/AndroidManifest.xml")[SCHEDULE_EXACT_ALARM])
    }

    /** A new permission in the woowtech build is a product decision: it needs a FORK.md row and a look at the Play policy. */
    @Test
    fun woowtechFlavorManifestAddsNoOtherPermission() {
        assertEquals(setOf(USE_EXACT_ALARM, SCHEDULE_EXACT_ALARM), permissions("woowtech/AndroidManifest.xml").keys)
        // The flavor manifest has a higher priority than src/main; the package comes from the module's namespace.
        assertFalse(manifest("woowtech/AndroidManifest.xml").hasAttribute("package"))
    }

    /** The upstream flavor must stay as upstream ships it: the user-granted permission, no USE_EXACT_ALARM, no flavor manifest. */
    @Test
    fun upstreamFlavorKeepsTheUserGrantedPermissionOnly() {
        val main = permissions("main/AndroidManifest.xml")
        assertTrue(main.toString(), SCHEDULE_EXACT_ALARM in main)
        assertEquals("src/main must declare SCHEDULE_EXACT_ALARM for every API level", "", main[SCHEDULE_EXACT_ALARM])
        assertFalse("USE_EXACT_ALARM belongs in the woowtech flavor manifest only", USE_EXACT_ALARM in main)
        assertFalse("the upstream flavor must not get a manifest of its own", File(app, "upstream/AndroidManifest.xml").exists())
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
