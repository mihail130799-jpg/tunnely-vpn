import 'dart:async';

import 'package:flutter/services.dart';

enum VpnStatus { disconnected, connecting, connected, reconnecting, disconnecting, error }

class VpnStateInfo {
  const VpnStateInfo(this.status, {this.connectedSince, this.serverName, this.error});

  final VpnStatus status;
  final DateTime? connectedSince;
  final String? serverName;
  final String? error;

  static const disconnected = VpnStateInfo(VpnStatus.disconnected);

  bool get isBusy =>
      status == VpnStatus.connecting || status == VpnStatus.reconnecting || status == VpnStatus.disconnecting;

  bool get isOn => status == VpnStatus.connected || status == VpnStatus.connecting || status == VpnStatus.reconnecting;

  factory VpnStateInfo.fromMap(Map<dynamic, dynamic> m) {
    final since = (m['connectedSince'] as num?)?.toInt() ?? 0;
    return VpnStateInfo(
      VpnStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => VpnStatus.disconnected),
      connectedSince: since > 0 ? DateTime.fromMillisecondsSinceEpoch(since) : null,
      serverName: m['serverName'] as String?,
      error: m['error'] as String?,
    );
  }
}

class TrafficInfo {
  const TrafficInfo({this.up = 0, this.down = 0, this.totalUp = 0, this.totalDown = 0});

  /// Bytes per second.
  final int up;
  final int down;
  final int totalUp;
  final int totalDown;

  static const zero = TrafficInfo();
}

/// Thin wrapper over the native `tunnely/vpn` channels (Android VpnService / iOS NetworkExtension).
class VpnPlatform {
  VpnPlatform({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel('tunnely/vpn'),
        _events = events ?? const EventChannel('tunnely/vpn/state');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<VpnStateInfo> get states =>
      _events.receiveBroadcastStream().map((e) => VpnStateInfo.fromMap(e as Map<dynamic, dynamic>));

  /// Shows the system VPN permission dialog when needed. True if granted.
  Future<bool> prepare() async => await _methods.invokeMethod<bool>('prepare') ?? false;

  Future<void> start({required String config, String? serverName}) =>
      _methods.invokeMethod('start', {'config': config, 'serverName': serverName});

  Future<void> stop() => _methods.invokeMethod('stop');

  Future<VpnStateInfo> state() async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('state');
    return m == null ? VpnStateInfo.disconnected : VpnStateInfo.fromMap(m);
  }

  Future<TrafficInfo> traffic() async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('traffic');
    if (m == null) return TrafficInfo.zero;
    int v(String k) => (m[k] as num?)?.toInt() ?? 0;
    return TrafficInfo(up: v('up'), down: v('down'), totalUp: v('totalUp'), totalDown: v('totalDown'));
  }

  /// Real latency through the running core, ms; -1 on failure.
  Future<int> delay(String proxyName, String url, {int timeoutMs = 5000}) async =>
      await _methods.invokeMethod<int>('delay', {'name': proxyName, 'url': url, 'timeoutMs': timeoutMs}) ?? -1;

  Future<bool> select(String group, String name) async =>
      await _methods.invokeMethod<bool>('select', {'group': group, 'name': name}) ?? false;

  /// Mihomo parse error for [config], or null if valid.
  Future<String?> validate(String config) => _methods.invokeMethod<String>('validate', {'config': config});

  Future<String> coreVersion() async => await _methods.invokeMethod<String>('coreVersion') ?? '?';
}
