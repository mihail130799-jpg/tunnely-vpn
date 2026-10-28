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
 *  - `stop`, `state` -> Map, `traffic` -> Map, `delay` {tag, url, timeoutMs, config} -> "ms|error",
 *    `logs` -> {core, events}, `clearLogs`, `validate` {config} -> String?, `coreVersion` -> String,
 *    `appInfo` -> {version, abi}, `installApk` {path} -> "started" | "permission".
 * Events on `tunnely/vpn/state`: state maps (see [VpnStateSnapshot.toMap]).
 */
class VpnBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private val methods = MethodChannel(messenger, "tunnely/vpn")
    private val events = EventChannel(messenger, "tunnely/vpn/state")
    private val io = Executors.newSingleThreadExecutor()
    private val probes = Executors.newFixedThreadPool(6)
    private var pendingPrepare: MethodChannel.Result? = null
    private var stateListener: ((VpnStateSnapshot) -> Unit)? = null

    init {
        // Same directory the service uses, so logs are readable before the first connect.
        Tunnelycore.setHomeDir(java.io.File(activity.filesDir, "xray").apply { mkdirs() }.absolutePath)
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
        probes.shutdown()
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
                val bypassApps = call.argument<List<String>>("bypassApps") ?: emptyList()
                io.execute {
                    try {
                        ConfigStore(activity).save(config, serverName, bypassApps)
                        activity.runOnUiThread {
                            TunnelyVpnService.start(activity)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("store_failed", e.javaClass.simpleName, null) }
                    }
                }
            }
            "installedPackages" -> io.execute {
                val pkgs = InstalledApps.packages(activity)
                activity.runOnUiThread { result.success(pkgs) }
            }
            "installedApps" -> io.execute {
                val apps = InstalledApps.withIcons(activity)
                activity.runOnUiThread { result.success(apps) }
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
                val tag = call.argument<String>("tag") ?: ""
                val url = call.argument<String>("url") ?: ""
                val timeout = call.argument<Int>("timeoutMs") ?: 5000
                val probeConfig = call.argument<String>("config") ?: ""
                probes.execute {
                    // "<ms>|<error>"; the core uses the running tunnel, or probeConfig when stopped.
                    val r = Tunnelycore.delayError(tag, url, timeout, probeConfig)
                    activity.runOnUiThread { result.success(r) }
                }
            }
            "logs" -> result.success(
                mapOf("core" to Tunnelycore.recentLogs(), "events" to Tunnelycore.recentEvents()),
            )
            "clearLogs" -> {
                Tunnelycore.clearLogs()
                result.success(null)
            }
            "validate" -> {
                val config = call.argument<String>("config") ?: ""
                io.execute {
                    val msg = Tunnelycore.validate(config)
                    activity.runOnUiThread { result.success(msg.ifEmpty { null }) }
                }
            }
            "coreVersion" -> result.success(Tunnelycore.version())
            "appInfo" -> result.success(Updater.appInfo(activity))
            "installApk" -> {
                try {
                    result.success(Updater.install(activity, call.argument<String>("path") ?: ""))
                } catch (e: Exception) {
                    result.error("install_failed", e.message ?: e.javaClass.simpleName, null)
                }
            }
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
