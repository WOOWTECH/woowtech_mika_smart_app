package com.wangzan101.mika.mcp

import com.wangzan101.mika.settings.McpSettings
import com.wangzan101.mika.settings.McpUsbSettings
import com.wangzan101.mika.settings.RelaySettings

/**
 * 局域网和 USB 共用的本地监听:局域网开着就绑所有网卡,只有 USB 开着就只绑回环。
 * 远程网关用独立的出站通道,不改变本地监听范围;三个开关各管各的,通知「关闭」会一起关闭。
 * 不碰安卓接口,在电脑上测。
 */
object McpModes {
    /** 电脑经 adb 打开 USB 方式(`am start-foreground-service -a`)。 */
    const val ACTION_USB_ON = "com.wangzan101.mika.mcp.USB_ON"
    /** 电脑经 adb 关掉 USB 方式。 */
    const val ACTION_USB_OFF = "com.wangzan101.mika.mcp.USB_OFF"
    /** 通知上的「关闭」:本地监听和远程通道都关。 */
    const val ACTION_TURN_OFF = "com.wangzan101.mika.mcp.TURN_OFF"

    enum class Listen { Off, LoopbackOnly, PrivateNetworks }

    /**
     * [relayOnly](商店版,见 PlayTransportPolicy.allowsLocalComputerAccess):电脑连接只走出站的远程网关,
     * 本机不监听局域网和 USB,开关就算是开着的也一样。
     */
    fun listen(network: Boolean, usb: Boolean, relayOnly: Boolean = false): Listen = when {
        relayOnly -> Listen.Off
        network -> Listen.PrivateNetworks
        usb -> Listen.LoopbackOnly
        else -> Listen.Off
    }

    /** 服务收到的动作改哪个开关;别的动作(含没有动作)不改,只按开关现状来。[relayOnly] 时不打开 USB 方式。 */
    fun apply(action: String?, network: McpSettings, usb: McpUsbSettings, relay: RelaySettings? = null, relayOnly: Boolean = false) {
        when (action) {
            ACTION_USB_ON -> if (!relayOnly) usb.enable()
            ACTION_USB_OFF -> usb.disable()
            ACTION_TURN_OFF -> {
                try { network.setEnabled(false) }
                finally { try { usb.disable() } finally { relay?.setEnabled(false) } }
            }
        }
    }
}
