package com.tunnely.vpn.vpn

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArraySet

/** Lifecycle of the tunnel as reported to Flutter and the Quick Settings tile. */
enum class TunnelStatus { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, DISCONNECTING, ERROR }

data class VpnStateSnapshot(
    val status: TunnelStatus,
    /** Epoch millis when CONNECTED was reached, or 0. */
    val connectedSince: Long = 0,
    /** Display name of the active server, if known. */
    val serverName: String? = null,
    /** User-facing error text (Russian), only for ERROR. */
    val error: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "status" to status.name.lowercase(),
        "connectedSince" to connectedSince,
        "serverName" to serverName,
        "error" to error,
    )
}

/** Process-wide single source of truth for tunnel state. Listeners run on the main thread. */
object VpnState {
    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<(VpnStateSnapshot) -> Unit>()

    @Volatile
    var current = VpnStateSnapshot(TunnelStatus.DISCONNECTED)
        private set

    fun update(next: VpnStateSnapshot) {
        current = next
        main.post { listeners.forEach { it(next) } }
    }

    fun addListener(l: (VpnStateSnapshot) -> Unit) {
        listeners.add(l)
        main.post { l(current) }
    }

    fun removeListener(l: (VpnStateSnapshot) -> Unit) {
        listeners.remove(l)
    }
}
