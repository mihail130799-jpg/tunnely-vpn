import 'package:flutter/material.dart';

import '../core/mihomo_config.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.connectOnLaunch = false,
    this.routing = RoutingMode.ruDirect,
    this.ipv6 = true,
  });

  final ThemeMode themeMode;

  /// Connect to the last server when the app opens (off by default).
  final bool connectOnLaunch;
  final RoutingMode routing;
  final bool ipv6;

  AppSettings copyWith({ThemeMode? themeMode, bool? connectOnLaunch, RoutingMode? routing, bool? ipv6}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        connectOnLaunch: connectOnLaunch ?? this.connectOnLaunch,
        routing: routing ?? this.routing,
        ipv6: ipv6 ?? this.ipv6,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'connectOnLaunch': connectOnLaunch,
        'routing': routing.name,
        'ipv6': ipv6,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.system),
        connectOnLaunch: j['connectOnLaunch'] as bool? ?? false,
        routing: RoutingMode.values.firstWhere((m) => m.name == j['routing'], orElse: () => RoutingMode.ruDirect),
        ipv6: j['ipv6'] as bool? ?? true,
      );
}
