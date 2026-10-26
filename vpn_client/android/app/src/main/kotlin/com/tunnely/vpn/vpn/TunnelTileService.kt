package com.tunnely.vpn.vpn

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.tunnely.vpn.MainActivity

/** Quick Settings tile: one tap connects/disconnects with the last used server. */
class TunnelTileService : TileService() {
    private val listener: (VpnStateSnapshot) -> Unit = { render(it) }

    override fun onStartListening() {
        VpnState.addListener(listener)
    }

    override fun onStopListening() {
        VpnState.removeListener(listener)
    }

    override fun onClick() {
        when (VpnState.current.status) {
            TunnelStatus.CONNECTED, TunnelStatus.CONNECTING, TunnelStatus.RECONNECTING ->
                TunnelyVpnService.stop(this)
            else -> {
                // Permission missing or nothing imported yet: open the app instead.
                if (VpnService.prepare(this) != null || ConfigStore(this).load() == null) {
                    openApp()
                } else {
                    TunnelyVpnService.start(this)
                }
            }
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun render(s: VpnStateSnapshot) {
        val tile = qsTile ?: return
        tile.state = when (s.status) {
            TunnelStatus.CONNECTED -> Tile.STATE_ACTIVE
            TunnelStatus.DISCONNECTED, TunnelStatus.ERROR -> Tile.STATE_INACTIVE
            else -> Tile.STATE_ACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = s.serverName
        tile.updateTile()
    }
}
