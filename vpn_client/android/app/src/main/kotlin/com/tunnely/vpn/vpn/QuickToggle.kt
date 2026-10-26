package com.tunnely.vpn.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.tunnely.vpn.MainActivity

/** One-tap connect/disconnect shared by the Quick Settings tile and the home-screen widget. */
object QuickToggle {
    /**
     * Toggles the tunnel. Returns false when the app must be opened instead
     * (no VPN permission yet or nothing imported); the caller decides how to open it.
     */
    fun toggle(context: Context): Boolean {
        return when (VpnState.current.status) {
            TunnelStatus.CONNECTED, TunnelStatus.CONNECTING, TunnelStatus.RECONNECTING -> {
                TunnelyVpnService.stop(context)
                true
            }
            TunnelStatus.DISCONNECTING -> true
            else -> {
                if (!canToggleWithoutApp(context)) {
                    false
                } else {
                    TunnelyVpnService.start(context)
                    true
                }
            }
        }
    }

    /** VPN permission granted and a config saved: the tunnel can start without the UI. */
    fun canToggleWithoutApp(context: Context): Boolean =
        VpnService.prepare(context) == null && ConfigStore(context).hasConfig()

    fun openAppIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
