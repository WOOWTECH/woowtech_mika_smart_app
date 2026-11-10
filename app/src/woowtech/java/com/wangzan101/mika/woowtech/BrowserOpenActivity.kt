// WOOWTECH fork: browser entry only for this flavor. See docs-woowtech/browser-open.md.
package com.wangzan101.mika.woowtech

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.wangzan101.mika.ui.MainActivity

/** Opens the existing app task without delegating browser-controlled data or permissions. */
class BrowserOpenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val uri = intent.data
            // Explicit component launches bypass intent filters, so validate here as well.
            if (intent.action == Intent.ACTION_VIEW && uri != null &&
                uri.scheme == packageName && uri.encodedAuthority == "open" &&
                (uri.encodedPath.isNullOrEmpty() || uri.encodedPath == "/")) {
                // Never copy extras, selector, ClipData, flags, query or fragment from the caller.
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
