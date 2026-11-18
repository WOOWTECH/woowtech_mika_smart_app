// WOOWTECH Play branch: guards restricted permissions and components of the branded manifest.
package com.wangzan101.mika.core.brand

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The Play edition schedules tasks with the user-granted exact alarm (SCHEDULE_EXACT_ALARM), never USE_EXACT_ALARM, and
 * has no phone-control component.
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

    /**
     * Owner decision 2026-11-18: scheduled tasks are back. Play limits USE_EXACT_ALARM to alarm, timer and calendar apps,
     * so the Play build asks the user for SCHEDULE_EXACT_ALARM (on every API level) and never declares USE_EXACT_ALARM.
     */
    @Test
    fun playManifestUsesOnlyTheUserGrantedExactAlarm() {
        val main = permissions("main/AndroidManifest.xml")
        assertTrue("scheduled tasks need SCHEDULE_EXACT_ALARM", SCHEDULE_EXACT_ALARM in main)
        assertEquals("SCHEDULE_EXACT_ALARM must apply to every API level", "", main.getValue(SCHEDULE_EXACT_ALARM))
        assertFalse("USE_EXACT_ALARM must not be in the shared manifest", USE_EXACT_ALARM in main)
        assertFalse("USE_EXACT_ALARM must not be in the Play manifest", USE_EXACT_ALARM in permissions("woowtech/AndroidManifest.xml"))
        assertFalse("the upstream flavor must not get a manifest of its own", File(app, "upstream/AndroidManifest.xml").exists())
        val receivers = manifest("main/AndroidManifest.xml").getElementsByTagName("receiver")
        val names = (0 until receivers.length).map { (receivers.item(it) as Element).getAttributeNS(androidNs, "name") }
        assertTrue(names.toString(), ".task.TriggerAlarmReceiver" in names)
    }

    /** After a reboot the alarms are gone; the boot receiver only re-arms them and never starts phone recovery. */
    @Test
    fun bootReceiverOnlyRearmsScheduledTasks() {
        val receivers = manifest("main/AndroidManifest.xml").getElementsByTagName("receiver")
        val restore = (0 until receivers.length).map { receivers.item(it) as Element }
            .single { it.getAttributeNS(androidNs, "name") == ".task.ScheduleRestoreReceiver" }
        val actions = restore.getElementsByTagName("action")
        assertEquals(setOf("android.intent.action.BOOT_COMPLETED", "android.intent.action.MY_PACKAGE_REPLACED",
            "android.intent.action.TIME_SET", "android.intent.action.TIMEZONE_CHANGED",
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"),
            (0 until actions.length).map { (actions.item(it) as Element).getAttributeNS(androidNs, "name") }.toSet())
        // 只看代码行(注释里可以提到它们)
        val code = File(app, "main/java/com/wangzan101/mika/task/ScheduleRestoreReceiver.kt").readLines()
            .filterNot { val t = it.trimStart(); t.startsWith("*") || t.startsWith("/*") || t.startsWith("//") }.joinToString("\n")
        listOf("BootRestoreHandler", "PhoneServices", "cap.phone", "deviceAccess").forEach {
            assertFalse("ScheduleRestoreReceiver must not use $it", it in code)
        }
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
            "com.android.alarm.permission.SET_ALARM",
        ).forEach { assertFalse("Play manifest requests $it", it in requested) }
        val components = listOf("service", "provider", "receiver", "activity")
            .flatMap { tag -> main.getElementsByTagName(tag).let { nodes ->
                (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(androidNs, "name") }
            } }
        listOf("MikaAccessibilityService", "HelperHandoffProvider", "BootRestoreReceiver", "SelfCheckTargetActivity")
            .forEach { forbidden -> assertFalse("Play manifest still exposes $forbidden", components.any { it.endsWith(forbidden) }) }
    }

    /**
     * Owner decision 2026-11-18: the Play edition keeps the one web page the user asked to keep open after a task, like the
     * direct-download edition. The foreground-service declaration (also entered in Play Console) has to say so, and the
     * browser must not drop its page keeper for this flavor again.
     */
    @Test
    fun taskServiceDeclaresTheKeptPage() {
        val services = manifest("main/AndroidManifest.xml").getElementsByTagName("service")
        val task = (0 until services.length).map { services.item(it) as Element }
            .single { it.getAttributeNS(androidNs, "name") == ".task.TaskService" }
        val properties = task.getElementsByTagName("property")
        val subtype = (0 until properties.length).map { properties.item(it) as Element }
            .single { it.getAttributeNS(androidNs, "name") == "android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" }
            .getAttributeNS(androidNs, "value")
        assertTrue(subtype, "keeps the one web page the user asked to keep open" in subtype)
        assertTrue(subtype, "at most two hours" in subtype)
        assertFalse(subtype, "phone task" in subtype || "virtual display" in subtype)
        val webStack = File(app, "main/java/com/wangzan101/mika/cap/web/WebStack.kt").readText()
        assertFalse("WebStack drops the page keeper for the Play flavor", "FLAVOR == \"woowtech\"" in webStack)
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
