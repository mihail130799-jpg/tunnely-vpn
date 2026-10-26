package com.tunnely.vpn

import com.tunnely.vpn.vpn.VpnBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(VpnPlugin())
    }

    /** Registers [VpnBridge] with access to activity results (VPN permission dialog). */
    private class VpnPlugin : FlutterPlugin, ActivityAware {
        private var messenger: io.flutter.plugin.common.BinaryMessenger? = null
        private var bridge: VpnBridge? = null

        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            messenger = binding.binaryMessenger
        }

        override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            messenger = null
        }

        override fun onAttachedToActivity(binding: ActivityPluginBinding) {
            val m = messenger ?: return
            bridge = VpnBridge(binding.activity, m).also { it.attach(binding) }
        }

        override fun onDetachedFromActivity() {
            bridge?.dispose()
            bridge = null
        }

        override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
            onAttachedToActivity(binding)

        override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    }
}
