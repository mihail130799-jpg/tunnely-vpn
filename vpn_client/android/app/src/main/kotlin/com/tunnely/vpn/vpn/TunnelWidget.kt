package com.tunnely.vpn.vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.tunnely.vpn.R

/**
 * Home-screen widget: status + server name; tapping toggles the tunnel
 * (or opens the app when permission/config is missing).
 */
class TunnelWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, manager, ids, VpnState.current)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Background activity starts are blocked, so a "needs the app" state is
        // routed to an activity PendingIntent at render time instead (see render).
        if (intent.action == ACTION_TOGGLE) QuickToggle.toggle(context)
    }

    companion object {
        private const val ACTION_TOGGLE = "com.tunnely.vpn.WIDGET_TOGGLE"

        /** Redraws every placed widget; cheap no-op when none are placed. */
        fun refresh(context: Context, state: VpnStateSnapshot) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TunnelWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids, state)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray, s: VpnStateSnapshot) {
            val on = s.status == TunnelStatus.CONNECTED
            val (status, dot) = when (s.status) {
                TunnelStatus.CONNECTED -> R.string.widget_connected to R.drawable.widget_dot_on
                TunnelStatus.CONNECTING, TunnelStatus.RECONNECTING -> R.string.widget_connecting to R.drawable.widget_dot_busy
                TunnelStatus.DISCONNECTING -> R.string.widget_disconnecting to R.drawable.widget_dot_busy
                TunnelStatus.ERROR -> R.string.widget_error to R.drawable.widget_dot_error
                TunnelStatus.DISCONNECTED -> R.string.widget_disconnected to R.drawable.widget_dot_off
            }
            val server = s.serverName ?: ConfigStore(context).serverName()
            val click = if (QuickToggle.canToggleWithoutApp(context)) {
                PendingIntent.getBroadcast(
                    context, 0,
                    Intent(context, TunnelWidget::class.java).setAction(ACTION_TOGGLE),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            } else {
                PendingIntent.getActivity(
                    context, 0, QuickToggle.openAppIntent(context),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }
            val views = RemoteViews(context.packageName, R.layout.widget_tunnel).apply {
                setInt(R.id.widget_root, "setBackgroundResource",
                    if (on) R.drawable.widget_bg_on else R.drawable.widget_bg_off)
                setImageViewResource(R.id.widget_dot, dot)
                setTextViewText(R.id.widget_status, context.getString(status))
                setTextViewText(R.id.widget_server, server ?: context.getString(R.string.widget_no_server))
                setTextViewText(R.id.widget_button,
                    context.getString(if (on || s.status == TunnelStatus.CONNECTING) R.string.widget_action_off else R.string.widget_action_on))
                setOnClickPendingIntent(R.id.widget_root, click)
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
