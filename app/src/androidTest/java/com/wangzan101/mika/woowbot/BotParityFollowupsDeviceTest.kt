package com.wangzan101.mika.woowbot

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.CloseComposeActivity
import com.wangzan101.mika.ui.botUiImportAvatar
import com.wangzan101.mika.ui.components.MikaDialog
import com.wangzan101.mika.ui.theme.MikaTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.Base64

/** iOS parity follow-ups the owner accepted on 2026-11-28 that need a device: k9 (avatar background) and k4 (dialog buttons). */
@RunWith(AndroidJUnit4::class)
class BotParityFollowupsDeviceTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = CloseComposeActivity(compose)
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Before fun woowtechOnly() = assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)

    /** k9: a transparent picture becomes a white-backed 320 × 320 JPEG, as on iOS, not a black-backed one. */
    @Test fun transparentAvatarIsLaidOnWhite() {
        val picture = Bitmap.createBitmap(100, 60, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.TRANSPARENT)
            Canvas(this).drawRect(40f, 20f, 60f, 40f, Paint().apply { color = Color.RED })
        }
        val file = File(context.cacheDir, "avatar-transparent.png")
        file.outputStream().use { check(picture.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        try {
            val jpeg = Base64.getDecoder().decode(botUiImportAvatar(context, Uri.fromFile(file)))
            val saved = requireNotNull(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
            assertEquals(320, saved.width)
            assertEquals(320, saved.height)
            for ((x, y) in listOf(2 to 2, 317 to 2, 2 to 317, 317 to 317, 60 to 160)) {
                val p = saved.getPixel(x, y)
                assertTrue("($x, $y) is #%06X".format(p and 0xFFFFFF), Color.red(p) > 240 && Color.green(p) > 240 && Color.blue(p) > 240)
            }
            val centre = saved.getPixel(160, 160)
            assertTrue("centre is #%06X".format(centre and 0xFFFFFF), Color.red(centre) > 200 && Color.green(centre) < 60 && Color.blue(centre) < 60)
        } finally {
            file.delete()
        }
    }

    /** k4: each dialog button is its whole capsule, at least 44 dp high; a tap near its edge, away from the label, presses it. */
    @Test fun dialogButtonIsTheWholeCapsule() {
        var deleted = false
        var cancelled = false
        compose.setContent {
            MikaTheme {
                MikaDialog(
                    onDismissRequest = {},
                    title = { Text("刪除對話") },
                    text = { Text("確定要刪除這個對話？") },
                    confirmButton = { TextButton({ deleted = true }, Modifier.testTag("delete")) { Text("刪除") } },
                    dismissButton = { TextButton({ cancelled = true }, Modifier.testTag("cancel")) { Text("取消") } },
                )
            }
        }
        for (tag in listOf("delete", "cancel")) compose.onNodeWithTag(tag).assertHeightIsAtLeast(44.dp).assertWidthIsAtLeast(100.dp)
        // Near each end at mid-height, well away from the centred label. The rounded corners outside the capsule are not part
        // of it, as on iOS (a capsule content shape), so the taps are not in the very corners.
        compose.onNodeWithTag("delete").performTouchInput { click(Offset(width - 12f, height / 2f)) }
        compose.onNodeWithTag("cancel").performTouchInput { click(Offset(12f, height / 2f)) }
        compose.runOnIdle { assertTrue(deleted); assertTrue(cancelled) }
    }
}
