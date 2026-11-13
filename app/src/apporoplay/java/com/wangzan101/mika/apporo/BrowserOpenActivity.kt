// apporoplay copy of app/src/apporo/java/com/wangzan101/mika/apporo/BrowserOpenActivity.kt (keep the two in step).
// Apporo alignment of WOOWTECH 3d419172. See docs-apporo/browser-open.md.
package com.wangzan101.mika.apporo

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.wangzan101.mika.ui.MainActivity

/** Open the existing app task without delegating browser-controlled data or permissions. */
class BrowserOpenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val uri = intent.data
            // Explicit component launches bypass intent filters: validate here too.
            if (intent.action == Intent.ACTION_VIEW && uri != null &&
                uri.scheme == packageName && uri.encodedAuthority == "open" &&
                (uri.encodedPath.isNullOrEmpty() || uri.encodedPath == "/")) {
                // Do not copy extras, selector, ClipData, flags, query or fragment.
                startActivity(Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                })
            }
        } finally {
            finish()
        }
    }
}
