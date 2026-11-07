// WOOWTECH fork: shared copy helper (not in upstream Mika); see docs-woowtech/FORK.md.
package com.wangzan101.mika.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.widget.Toast

/**
 * 把 [text] 放进剪贴板([label] 是剪贴板条目的名字),再用 Toast 说一句 [copied]。
 * 安卓 13 起系统复制后自己会在左下角弹出带预览的「已复制」浮层,App 再弹 Toast 就和它叠在一起、字被挡住,
 * 所以那以后不弹(见 [copiedToastNeeded])。[long] 是 Toast 显示得久一点(提示里还有别的话时)。
 * 剪贴板写不进(内容太大等)时照样抛出,由调用方说失败。
 */
internal fun copyToClipboard(context: Context, label: String, text: String, copied: String, long: Boolean = false) {
    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(label, text))
    if (copiedToastNeeded()) Toast.makeText(context, copied, if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()
}

/** 复制后 App 要不要自己说「已复制」:系统在安卓 13(API 33)起自己会说,12L 及以下要 App 说。 */
internal fun copiedToastNeeded(sdk: Int = Build.VERSION.SDK_INT): Boolean = sdk < Build.VERSION_CODES.TIRAMISU
