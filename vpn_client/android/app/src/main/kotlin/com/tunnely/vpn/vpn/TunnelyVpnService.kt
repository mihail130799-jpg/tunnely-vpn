package com.tunnely.vpn.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.tunnely.core.tunnelycore.Protector
import com.tunnely.core.tunnelycore.Tunnelycore
import com.tunnely.vpn.MainActivity
import com.tunnely.vpn.R
import java.io.File
import java.util.concurrent.Executors

/**
 * Android VPN entry point. Owns the TUN interface and runs the Mihomo core on it.
 * Start with [ACTION_START] (config comes from [ConfigStore]); stop with [ACTION_STOP].
 */
class TunnelyVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var currentNetwork: Network? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> worker.execute { stopTunnel(userRequested = true) }
            // null action = restarted by the system (START_STICKY) or always-on VPN.
            else -> {
                startForegroundCompat(buildNotification(getString(R.string.vpn_notification_connecting), null))
                worker.execute { startTunnel() }
            }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        // Another VPN took over or the user revoked permission in system settings.
        worker.execute { stopTunnel(userRequested = false) }
    }

    override fun onDestroy() {
        worker.execute { stopTunnel(userRequested = false) }
        worker.shutdown()
        super.onDestroy()
    }

    private fun startTunnel() {
        val store = ConfigStore(this)
        val config = store.load()
        val serverName = store.serverName()
        if (config == null) {
            fail(getString(R.string.vpn_error_no_config))
            return
        }
        VpnState.update(VpnStateSnapshot(TunnelStatus.CONNECTING, serverName = serverName))
        try {
            if (tun != null) closeTunnel()
            val home = prepareHomeDir()
            Tunnelycore.setHomeDir(home.absolutePath)
            Tunnelycore.setProtector(object : Protector {
                override fun protect(fd: Int): Boolean = this@TunnelyVpnService.protect(fd)
            })

            val pfd = buildInterface()
                ?: throw IllegalStateException(getString(R.string.vpn_error_permission))
            tun = pfd

            // Patch the fd as text: re-serializing with org.json would emit "\/",
            // which is valid JSON but rejected by Mihomo's YAML parser.
            check(FD_PATTERN.containsMatchIn(config)) { "config has no tun.file-descriptor" }
            Tunnelycore.start(FD_PATTERN.replace(config, "\"file-descriptor\": ${pfd.fd}"))

            registerNetworkCallback()
            VpnState.update(VpnStateSnapshot(TunnelStatus.CONNECTED, System.currentTimeMillis(), serverName))
            notify(buildNotification(getString(R.string.vpn_notification_connected), serverName))
        } catch (e: Exception) {
            Log.e(TAG, "start failed: ${e.javaClass.simpleName}")
            closeTunnel()
            fail(getString(R.string.vpn_error_start, e.message?.take(200) ?: e.javaClass.simpleName))
        }
    }

    private fun buildInterface(): ParcelFileDescriptor? {
        val b = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(MTU)
            .addAddress(TUN_V4, 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(TUN_DNS_V4)
        try {
            b.addAddress(TUN_V6, 126)
            b.addRoute("::", 0)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "IPv6 not available on this device")
        }
        // Our own traffic (subscription updates, the core's outbound sockets) bypasses the tunnel.
        b.addDisallowedApplication(packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) b.setMetered(false)
        b.setConfigureIntent(
            PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return b.establish()
    }

    private fun stopTunnel(userRequested: Boolean) {
        val wasError = VpnState.current.status == TunnelStatus.ERROR
        if (tun != null) VpnState.update(VpnState.current.copy(status = TunnelStatus.DISCONNECTING))
        unregisterNetworkCallback()
        try {
            Tunnelycore.stop()
        } catch (e: Exception) {
            Log.w(TAG, "core stop: ${e.javaClass.simpleName}")
        }
        Tunnelycore.setProtector(null)
        closeTunnel()
        // Keep a start error visible unless the user explicitly dismissed it by stopping.
        if (!wasError || userRequested) {
            VpnState.update(VpnStateSnapshot(TunnelStatus.DISCONNECTED))
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun closeTunnel() {
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun fail(message: String) {
        VpnState.update(VpnStateSnapshot(TunnelStatus.ERROR, error = message))
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Follows the default network so routing and reconnects track Wi-Fi/mobile switches. */
    private fun registerNetworkCallback() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = onNetworkChanged(network)
            override fun onLost(network: Network) {
                if (network == currentNetwork) onNetworkChanged(null)
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                cm.requestNetwork(request, cb)
            } else {
                cm.registerNetworkCallback(request, cb)
            }
            networkCallback = cb
        } catch (e: Exception) {
            Log.w(TAG, "network callback: ${e.javaClass.simpleName}")
        }
    }

    private fun onNetworkChanged(network: Network?) {
        val changed = currentNetwork != null && network != currentNetwork
        currentNetwork = network
        setUnderlyingNetworks(network?.let { arrayOf(it) })
        if (changed && network != null) {
            // Old sockets are bound to the previous network; drop them so apps reconnect quickly.
            if (!worker.isShutdown) worker.execute { Tunnelycore.closeAllConnections() }
        }
    }

    private fun unregisterNetworkCallback() {
        val cb = networkCallback ?: return
        try {
            getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {
        }
        networkCallback = null
        currentNetwork = null
    }

    /** Mihomo home: rule sets bundled as Flutter assets are copied here once per app version. */
    private fun prepareHomeDir(): File {
        val home = File(filesDir, "mihomo")
        val rules = File(home, "ruleset").apply { mkdirs() }
        val stamp = File(home, ".assets_version")
        val version = packageManager.getPackageInfo(packageName, 0).lastUpdateTime.toString()
        if (!stamp.exists() || stamp.readText() != version) {
            for (name in listOf("ru-domains.mrs", "ru-ips.mrs")) {
                assets.open("flutter_assets/assets/ruleset/$name").use { input ->
                    File(rules, name).outputStream().use { input.copyTo(it) }
                }
            }
            stamp.writeText(version)
        }
        return home
    }

    private fun startForegroundCompat(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun notify(n: Notification) {
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, n)
    }

    private fun buildNotification(title: String, serverName: String?): Notification {
        ensureChannel(this)
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, TunnelyVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tunnel)
            .setContentTitle(title)
            .setContentText(serverName)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, getString(R.string.vpn_action_disconnect), stop)
            .build()
    }

    companion object {
        private const val TAG = "TunnelyVpn"
        const val ACTION_START = "com.tunnely.vpn.START"
        const val ACTION_STOP = "com.tunnely.vpn.STOP"
        private const val CHANNEL_ID = "vpn_status"
        private const val NOTIFICATION_ID = 1

        // Must match TunAddresses in lib/core/mihomo_config.dart.
        private const val TUN_V4 = "172.19.0.1"
        private const val TUN_DNS_V4 = "172.19.0.2"
        private const val TUN_V6 = "fdfe:dcba:9876::1"
        private const val MTU = 9000
        private val FD_PATTERN = Regex("\"file-descriptor\"\\s*:\\s*-?\\d+")

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        context.getString(R.string.vpn_channel_name),
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply { setShowBadge(false) },
                )
            }
        }

        fun start(context: Context) {
            val i = Intent(context, TunnelyVpnService::class.java).setAction(ACTION_START)
            context.startForegroundService(i)
        }

        fun stop(context: Context) {
            val i = Intent(context, TunnelyVpnService::class.java).setAction(ACTION_STOP)
            context.startService(i)
        }
    }
}
