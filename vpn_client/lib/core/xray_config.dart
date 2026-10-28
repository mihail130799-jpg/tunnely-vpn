import 'dart:convert';

import '../models/server_profile.dart';

/// How traffic is split between the tunnel and the direct connection.
enum RoutingMode {
  /// Everything through VPN except Russian domains/IPs and the local network.
  ruDirect,

  /// Everything through VPN except the local network.
  global,
}

/// Address plan shared with the Android VpnService.
class TunAddresses {
  static const ipv4 = '172.19.0.1/30';
  static const dnsV4 = '172.19.0.2';
  static const ipv6 = 'fdfe:dcba:9876::1/126';
  static const mtu = 9000;
}

const latencyTestUrl = 'https://www.gstatic.com/generate_204';

/// Tag of the tun inbound (must match TunInboundTag in vpn_core).
const tunInboundTag = 'tun-in';

/// Tag of the least-ping balancer used for "Auto".
const autoBalancerTag = 'auto';

/// Display name of the automatic choice.
const autoGroup = 'Авто';

/// Russian domain suffixes routed directly in [RoutingMode.ruDirect].
const ruDomainSuffixes = [
  'ru', 'su', 'xn--p1ai', 'xn--d1acj3b', 'moscow', 'xn--80adxhks', 'tatar', 'xn--80asehdb',
  // Russian services on non-.ru domains.
  'yandex.net', 'yandex.com', 'yastatic.net', 'yandexcloud.net', 'ya.ru',
  'vk.com', 'vk.me', 'vkuser.net', 'userapi.com', 'vk-cdn.net', 'mycdn.me', 'okcdn.ru',
  'mail.ru', 'imgsmail.ru', 'max.ru', 'oneme.ru',
  'avito.st', 'wbbasket.ru', 'wb.ru', 'ozone.ru', 'ozon.ru',
  'sberbank.com', 'sber.ru', 'tbank.ru', 'tinkoff.ru', 'vtb.com', 'alfabank.com',
  'gosuslugi.ru', 'mos.ru', 'nalog.gov.ru', 'kaspersky.com', '1c.com',
];

/// Private and special-purpose ranges that never go through the tunnel.
const privateCidrs = [
  '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12',
  '192.168.0.0/16', '224.0.0.0/4', '255.255.255.255/32',
  'fc00::/7', 'fe80::/10', 'ff00::/8', '::1/128',
];

/// A generated Xray config plus how servers were mapped into it.
class XrayConfig {
  XrayConfig(this.json, this.outboundTags, this.unsupported);

  final String json;

  /// [ServerProfile.id] -> outbound tag inside the config.
  final Map<String, String> outboundTags;

  /// Servers left out because Xray cannot speak their protocol/transport,
  /// id -> user-facing reason.
  final Map<String, String> unsupported;
}

/// Thrown by [toXrayOutbound] for protocols/transports Xray does not support.
class UnsupportedServer implements Exception {
  UnsupportedServer(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

String outboundTagFor(ServerProfile s) => 'p-${s.id}';

/// Builds the full tunnel config.
///
/// [selected] is a server id, or null for "Auto" (least-ping balancer, with
/// [preferredAuto] as the fallback until the first probe completes).
/// [ruIps] are the CIDRs routed directly in [RoutingMode.ruDirect].
XrayConfig buildXrayConfig({
  required List<ServerProfile> servers,
  required String? selected,
  RoutingMode routing = RoutingMode.ruDirect,
  bool ipv6 = true,
  List<String> ruIps = const [],
  String? preferredAuto,
  String logLevel = 'warning',
}) {
  final outbounds = <Map<String, dynamic>>[];
  final tags = <String, String>{};
  final unsupported = <String, String>{};
  for (final s in servers) {
    try {
      final ob = toXrayOutbound(s.proxy, outboundTagFor(s));
      outbounds.add(ob);
      tags[s.id] = ob['tag'] as String;
    } on UnsupportedServer catch (e) {
      unsupported[s.id] = e.reason;
    }
  }
  if (outbounds.isEmpty) {
    throw ArgumentError(unsupported.isEmpty ? 'no servers' : 'no supported servers');
  }

  final proxyTags = [for (final o in outbounds) o['tag'] as String];
  final selectedTag = selected == null ? null : tags[selected];
  final useAuto = selectedTag == null;
  final fallback = (preferredAuto != null ? tags[preferredAuto] : null) ?? proxyTags.first;

  Map<String, dynamic> toProxy(Map<String, dynamic> rule) =>
      {...rule, if (useAuto) 'balancerTag': autoBalancerTag else 'outboundTag': selectedTag};

  final config = <String, dynamic>{
    'log': {'loglevel': logLevel},
    'stats': <String, dynamic>{},
    'policy': {
      'levels': {
        '0': {'handshake': 6, 'connIdle': 300, 'uplinkOnly': 2, 'downlinkOnly': 5},
      },
      // Outbound counters drive the speed shown in the app (see TrafficNow).
      'system': {
        'statsInboundUplink': true,
        'statsInboundDownlink': true,
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      },
    },
    'dns': {
      'tag': 'dns-internal',
      'queryStrategy': ipv6 ? 'UseIP' : 'UseIPv4',
      'servers': [
        if (routing == RoutingMode.ruDirect)
          {
            'address': 'https+local://77.88.8.8/dns-query',
            'domains': [for (final d in ruDomainSuffixes) 'domain:$d'],
            'skipFallback': true,
          },
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ],
    },
    'inbounds': [
      {
        'tag': tunInboundTag,
        'protocol': 'tun',
        'settings': {'name': 'tun0', 'MTU': TunAddresses.mtu, 'userLevel': 0},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        },
      },
    ],
    'outbounds': [
      ...outbounds,
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
      {'tag': 'dns-out', 'protocol': 'dns'},
    ],
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        // Android "Private DNS" probes DoT on the TUN DNS address; fail fast so
        // it falls back to plain DNS, which is answered by Xray below.
        {'type': 'field', 'ip': [TunAddresses.dnsV4], 'port': '853', 'outboundTag': 'block'},
        {'type': 'field', 'inboundTag': [tunInboundTag], 'port': '53', 'outboundTag': 'dns-out'},
        toProxy({'type': 'field', 'inboundTag': ['dns-internal']}),
        {'type': 'field', 'ip': privateCidrs, 'outboundTag': 'direct'},
        {'type': 'field', 'domain': ['domain:local', 'domain:lan'], 'outboundTag': 'direct'},
        if (routing == RoutingMode.ruDirect) ...[
          {'type': 'field', 'domain': [for (final d in ruDomainSuffixes) 'domain:$d'], 'outboundTag': 'direct'},
          if (ruIps.isNotEmpty) {'type': 'field', 'ip': ruIps, 'outboundTag': 'direct'},
        ],
        toProxy({'type': 'field', 'network': 'tcp,udp'}),
      ],
      if (useAuto)
        'balancers': [
          {
            'tag': autoBalancerTag,
            'selector': proxyTags,
            'strategy': {'type': 'leastPing'},
            'fallbackTag': fallback,
          },
        ],
    },
    if (useAuto)
      'observatory': {
        'subjectSelector': proxyTags,
        'probeUrl': latencyTestUrl,
        'probeInterval': '1m',
        'enableConcurrency': true,
      },
  };
  return XrayConfig(const JsonEncoder.withIndent(' ').convert(config), tags, unsupported);
}

/// Outbounds-only config for measuring servers while the tunnel is down.
String buildProbeConfig(List<ServerProfile> servers) {
  final outbounds = <Map<String, dynamic>>[];
  for (final s in servers) {
    try {
      outbounds.add(toXrayOutbound(s.proxy, outboundTagFor(s)));
    } on UnsupportedServer {
      // Reported by buildXrayConfig; nothing to probe.
    }
  }
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'outbounds': [...outbounds, {'tag': 'direct', 'protocol': 'freedom'}],
  });
}

/// Converts a parsed server (Clash/Mihomo-style map produced by the link and
/// subscription parsers) into an Xray outbound.
Map<String, dynamic> toXrayOutbound(Map<String, dynamic> p, String tag) {
  final type = '${p['type']}';
  final server = '${p['server']}';
  final port = (p['port'] as num?)?.toInt() ?? int.tryParse('${p['port']}') ?? 0;
  final Map<String, dynamic> settings;
  final String protocol;
  switch (type) {
    case 'vless':
      protocol = 'vless';
      final enc = '${p['encryption'] ?? ''}';
      settings = {
        'vnext': [
          {
            'address': server,
            'port': port,
            'users': [
              {
                'id': '${p['uuid']}',
                'encryption': enc.isEmpty ? 'none' : enc,
                if ('${p['flow'] ?? ''}'.isNotEmpty) 'flow': '${p['flow']}',
              },
            ],
          },
        ],
      };
    case 'vmess':
      protocol = 'vmess';
      settings = {
        'vnext': [
          {
            'address': server,
            'port': port,
            'users': [
              {'id': '${p['uuid']}', 'security': '${p['cipher'] ?? 'auto'}'},
            ],
          },
        ],
      };
    case 'trojan':
      protocol = 'trojan';
      settings = {
        'servers': [
          {'address': server, 'port': port, 'password': '${p['password']}'},
        ],
      };
    case 'ss':
      if (p['plugin'] != null) throw UnsupportedServer('Shadowsocks с плагином не поддерживается');
      protocol = 'shadowsocks';
      settings = {
        'servers': [
          {'address': server, 'port': port, 'method': '${p['cipher']}', 'password': '${p['password']}'},
        ],
      };
    default:
      throw UnsupportedServer('Протокол ${type.toUpperCase()} пока не поддерживается');
  }
  return {
    'tag': tag,
    'protocol': protocol,
    'settings': settings,
    'streamSettings': _stream(p, trojanDefaultTls: type == 'trojan'),
  };
}

Map<String, dynamic> _stream(Map<String, dynamic> p, {required bool trojanDefaultTls}) {
  final network = '${p['network'] ?? 'tcp'}';
  final s = <String, dynamic>{};
  switch (network) {
    case 'tcp':
      s['network'] = 'raw';
    case 'http':
      final h = (p['http-opts'] as Map?) ?? const {};
      s['network'] = 'raw';
      s['rawSettings'] = {
        'header': {
          'type': 'http',
          'request': {
            if (h['path'] != null) 'path': h['path'],
            if ((h['headers'] as Map?)?['Host'] != null) 'headers': {'Host': (h['headers'] as Map)['Host']},
          },
        },
      };
    case 'ws':
      final w = (p['ws-opts'] as Map?) ?? const {};
      final host = (w['headers'] as Map?)?['Host'];
      if (w['v2ray-http-upgrade'] == true) {
        s['network'] = 'httpupgrade';
        s['httpupgradeSettings'] = {'path': w['path'] ?? '/', 'host': ?host};
      } else {
        s['network'] = 'ws';
        s['wsSettings'] = {'path': w['path'] ?? '/', 'host': ?host};
      }
    case 'grpc':
      final g = (p['grpc-opts'] as Map?) ?? const {};
      s['network'] = 'grpc';
      s['grpcSettings'] = {'serviceName': g['grpc-service-name'] ?? ''};
    case 'xhttp':
      final x = (p['xhttp-opts'] as Map?) ?? const {};
      s['network'] = 'xhttp';
      s['xhttpSettings'] = {
        'path': x['path'] ?? '/',
        if (x['host'] != null) 'host': x['host'],
        if (x['mode'] != null) 'mode': x['mode'],
      };
    default:
      throw UnsupportedServer('Транспорт «$network» не поддерживается');
  }

  final sni = p['servername'] ?? p['sni'];
  final fp = p['client-fingerprint'];
  final alpn = p['alpn'];
  final reality = p['reality-opts'];
  if (reality is Map) {
    s['security'] = 'reality';
    s['realitySettings'] = {
      'serverName': ?sni,
      'fingerprint': fp ?? 'chrome',
      'publicKey': reality['public-key'],
      if (reality['short-id'] != null) 'shortId': '${reality['short-id']}',
      'spiderX': '',
    };
  } else if (p['tls'] == true || trojanDefaultTls) {
    s['security'] = 'tls';
    s['tlsSettings'] = {
      'serverName': ?sni,
      'fingerprint': ?fp,
      if (alpn is List) 'alpn': alpn,
      if (p['skip-cert-verify'] == true) 'allowInsecure': true,
    };
  } else {
    s['security'] = 'none';
  }
  return s;
}
