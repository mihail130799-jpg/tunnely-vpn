import '../core/country.dart';

/// One proxy server, stored as a Mihomo proxy map so every protocol
/// option survives round-trips without a lossy intermediate model.
class ServerProfile {
  ServerProfile({
    required this.id,
    required this.proxy,
    this.subscriptionId,
  });

  /// Stable identifier derived from [dedupKey]; survives subscription refresh.
  final String id;

  /// Mihomo proxy definition (`name`, `type`, `server`, `port`, ...).
  final Map<String, dynamic> proxy;

  /// Owning subscription, or null for manually imported keys.
  final String? subscriptionId;

  String get name => proxy['name'] as String? ?? '$server:$port';
  String get type => proxy['type'] as String? ?? '';
  String get server => proxy['server'] as String? ?? '';
  int get port => (proxy['port'] as num?)?.toInt() ?? 0;

  /// ISO 3166 alpha-2 code guessed from the server name, or null.
  String? get countryCode => detectCountry(name);

  /// Human-friendly protocol label for UI ("VLESS Reality", "Trojan", ...).
  String get protocolLabel {
    final reality = proxy['reality-opts'] != null;
    final network = proxy['network'] as String?;
    final base = switch (type) {
      'vless' => 'VLESS',
      'vmess' => 'VMess',
      'trojan' => 'Trojan',
      'ss' => 'Shadowsocks',
      'hysteria2' => 'Hysteria2',
      'tuic' => 'TUIC',
      'anytls' => 'AnyTLS',
      'wireguard' => 'WireGuard',
      _ => type.toUpperCase(),
    };
    if (reality) return '$base Reality';
    if (network != null && network != 'tcp') return '$base ${network.toUpperCase()}';
    return base;
  }

  /// Identity used for duplicate detection: same endpoint + same credential.
  String get dedupKey => dedupKeyOf(proxy);

  static String dedupKeyOf(Map<String, dynamic> p) {
    final secret = p['uuid'] ?? p['password'] ?? p['private-key'] ?? '';
    return '${p['type']}|${p['server']}|${p['port']}|$secret';
  }

  ServerProfile copyWith({Map<String, dynamic>? proxy, String? subscriptionId}) => ServerProfile(
        id: id,
        proxy: proxy ?? this.proxy,
        subscriptionId: subscriptionId ?? this.subscriptionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'proxy': proxy,
        if (subscriptionId != null) 'subscriptionId': subscriptionId,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String,
        proxy: Map<String, dynamic>.from(json['proxy'] as Map),
        subscriptionId: json['subscriptionId'] as String?,
      );
}
