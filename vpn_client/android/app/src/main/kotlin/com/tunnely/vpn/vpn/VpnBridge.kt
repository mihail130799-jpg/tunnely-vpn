package com.tunnely.vpn.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import com.tunnely.core.tunnelycore.Tunnelycore
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

/**
 * Flutter <-> native VPN bridge.
 *
 * Methods on `tunnely/vpn`:
 *  - `prepare` -> Boolean: asks for VPN permission if needed; true when granted.
 *  - `start` {config, serverName}: stores the config encrypted and starts the service.
 *  - `stop`, `state` -> Map, `traffic` -> Map, `delay` {name, url, timeoutMs} -> Int,
 *    `select` {group, name} -> Boolean, `validate` {config} -> String?, `coreVersion` -> String.
 * Events on `tunnely/vpn/state`: state maps (see [VpnStateSnapshot.toMap]).
 */
class VpnBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private val methods = MethodChannel(messenger, "tunnely/vpn")
    private val events = EventChannel(messenger, "tunnely/vpn/state")
    private val io = Executors.newSingleThreadExecutor()
    private var pendingPrepare: MethodChannel.Result? = null
    private var stateListener: ((VpnStateSnapshot) -> Unit)? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                val l: (VpnStateSnapshot) -> Unit = { sink.success(it.toMap()) }
                stateListener = l
                VpnState.addListener(l)
            }

            override fun onCancel(arguments: Any?) {
                stateListener?.let { VpnState.removeListener(it) }
                stateListener = null
            }
        })
    }

    fun attach(binding: ActivityPluginBinding) = binding.addActivityResultListener(this)

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        stateListener?.let { VpnState.removeListener(it) }
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepare(result)
            "start" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrEmpty()) {
                    result.error("bad_args", "config is required", null)
                    return
                }
                val serverName = call.argument<String>("serverName")
                io.execute {
                    try {
                        ConfigStore(activity).save(config, serverName)
                        activity.runOnUiThread {
                            TunnelyVpnService.start(activity)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("store_failed", e.javaClass.simpleName, null) }
                    }
                }
            }
            "stop" -> {
                TunnelyVpnService.stop(activity)
                result.success(null)
            }
            "state" -> result.success(VpnState.current.toMap())
            "traffic" -> {
                val t = Tunnelycore.trafficNow()
                result.success(
                    mapOf("up" to t.up, "down" to t.down, "totalUp" to t.totalUp, "totalDown" to t.totalDown),
                )
            }
            "delay" -> {
                val name = call.argument<String>("name") ?: ""
                val url = call.argument<String>("url") ?: ""
                val timeout = call.argument<Int>("timeoutMs") ?: 5000
                io.execute {
                    val d = Tunnelycore.delay(name, url, timeout)
                    activity.runOnUiThread { result.success(d.toInt()) }
                }
            }
            "select" -> {
                val ok = Tunnelycore.selectProxy(call.argument<String>("group") ?: "", call.argument<String>("name") ?: "")
                result.success(ok)
            }
            "validate" -> {
                val config = call.argument<String>("config") ?: ""
                io.execute {
                    val msg = Tunnelycore.validate(config)
                    activity.runOnUiThread { result.success(msg.ifEmpty { null }) }
                }
            }
            "coreVersion" -> result.success(Tunnelycore.version())
            else -> result.notImplemented()
        }
    }

    private fun prepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingPrepare != null) {
            result.error("busy", "permission request already in progress", null)
            return
        }
        pendingPrepare = result
        activity.startActivityForResult(intent, REQUEST_VPN)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_VPN) return false
        pendingPrepare?.success(resultCode == Activity.RESULT_OK)
        pendingPrepare = null
        return true
    }

    private companion object {
        const val REQUEST_VPN = 0x7E1
    }
}
