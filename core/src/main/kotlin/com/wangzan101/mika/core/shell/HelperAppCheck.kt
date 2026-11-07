// WOOWTECH fork: the helper notices that its app was uninstalled or replaced. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.core.shell

/**
 * 内置助手在 Mika 不在时(死亡通知之后、Mika 回来之前)看它的包还是不是启动时那个 App。
 * 卸载时系统先结束 Mika 的进程、随后才删包,死亡通知到时多半还查得到;只查那一次的话,
 * 助手会一直留到手机重启(2026-11-07 模拟器实测)。所以刚死时查得勤一些,之后隔 [MAX_DELAY_MS] 查一次。
 */
object HelperAppCheck {
    enum class State {
        /** 还是启动时那个 App:uid 和签名证书指纹都对上。 */
        Same,
        /** 这个用户下没装(卸载了)。 */
        Gone,
        /** 装着同名的包,但 uid 或签名证书不同:已经是另一个 App。 */
        Replaced,
        /** 查不清(反射、Binder 出错,读不到 uid 或证书)。 */
        Unknown,
    }

    /** 死亡通知当下查过一次之后,第一次复查等多久;之后每次加倍。 */
    const val FIRST_DELAY_MS = 1_000L

    /** Mika 一直没回来时的复查间隔:死了很久之后才被卸载,也在这么久之内发现。 */
    const val MAX_DELAY_MS = 10_000L

    /** 第 [n] 次(从 0 起)复查前等多久:1、2、4、8 秒,之后每 10 秒。 */
    fun delayMs(n: Int): Long = (FIRST_DELAY_MS shl n.coerceIn(0, 4)).coerceAtMost(MAX_DELAY_MS)

    /**
     * 查到的包([uid]、签名证书指纹 [certPin],见 [HelperHandoff.certPin])和启动时记下的([pinnedUid]、[pinnedCert])比。
     * uid 不同就是另一个 App:同一次开机里系统不会把卸载掉的 App 的 uid 再分给新装的(连同一份 APK 重装也拿新 uid),
     * 助手又活不过重启;uid 相同、证书不同也算另一个 App。
     */
    fun state(uid: Int?, certPin: String?, pinnedUid: Int, pinnedCert: String): State = when {
        uid == null -> State.Unknown
        uid != pinnedUid -> State.Replaced
        certPin == null -> State.Unknown
        certPin != pinnedCert -> State.Replaced
        else -> State.Same
    }

    /**
     * 只在确定不在、确定换了人时退出;查不清时接着等。
     * 误退出的代价大:经电脑 USB 起的助手要用户再插线跑一次命令才回得来。
     */
    fun exits(state: State): Boolean = state == State.Gone || state == State.Replaced
}
