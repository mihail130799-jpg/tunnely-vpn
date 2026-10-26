import 'dart:convert';

import '../models/server_profile.dart';

/// How traffic is split between the tunnel and the direct connection.
enum RoutingMode {
  /// Everything through VPN except Russian domains/IPs and the local network.
  ruDirect,

  /// Everything through VPN except the local network.
  global,
}

/// Name of the selector group the UI switches between servers with.
const selectorGroup = 'PROXY';

/// Name of the automatic (lowest latency) group.
const autoGroup = 'Авто';

/// Address plan shared with the Android VpnService / iOS tunnel settings.
class TunAddresses {
  static const ipv4 = '172.19.0.1/30';
  static const ipv6 = 'fdfe:dcba:9876::1/126';
  static const mtu = 9000;
}

const latencyTestUrl = 'https://www.gstatic.com/generate_204';

/// Builds a Mihomo configuration. Mihomo reads YAML, and JSON is valid YAML,
/// so the result is emitted as JSON for exact, dependency-free encoding.
String buildMihomoConfig({
  required List<ServerProfile> servers,
  required String? selected,
  required int tunFd,
  RoutingMode routing = RoutingMode.ruDirect,
  bool ipv6 = true,
  String logLevel = 'warning',
}) {
  if (servers.isEmpty) throw ArgumentError('no servers');

  final names = <String>{};
  final proxies = <Map<String, dynamic>>[];
  final idToName = <String, String>{};
  for (final s in servers) {
    var name = s.name.trim().isEmpty ? s.server : s.name.trim();
    if (name == selectorGroup || name == autoGroup || name == 'DIRECT' || name == 'REJECT') name = '$name ';
    final base = name;
    var i = 2;
    while (!names.add(name)) {
      name = '$base ($i)';
      i++;
    }
    idToName[s.id] = name;
    proxies.add({...s.proxy, 'name': name});
  }
  final allNames = proxies.map((p) => p['name'] as String).toList();
  final selectedName = selected == null ? autoGroup : (idToName[selected] ?? autoGroup);

  final config = <String, dynamic>{
    'mode': 'rule',
    'log-level': logLevel,
    'ipv6': ipv6,
    'allow-lan': false,
    'unified-delay': true,
    'tcp-concurrent': true,
    'find-process-mode': 'off',
    'geo-auto-update': false,
    'keep-alive-interval': 30,
    'profile': {'store-selected': false, 'store-fake-ip': false},
    'tun': {
      'enable': true,
      'stack': 'gvisor',
      'file-descriptor': tunFd,
      'inet4-address': [TunAddresses.ipv4],
      if (ipv6) 'inet6-address': [TunAddresses.ipv6],
      'mtu': TunAddresses.mtu,
      'auto-route': false,
      'auto-detect-interface': false,
      'dns-hijack': ['any:53', 'tcp://any:53'],
    },
    'dns': {
      'enable': true,
      'ipv6': ipv6,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': ['*.lan', '*.local', '+.msftconnecttest.com', '+.msftncsi.com', 'time.*.com', '+.ntp.org'],
      // Plain IPs to bootstrap the DoH resolvers below.
      'default-nameserver': ['77.88.8.8', '1.1.1.1'],
      // Resolves proxy server hostnames directly, before the tunnel exists.
      'proxy-server-nameserver': ['https://77.88.8.8/dns-query', 'https://1.1.1.1/dns-query'],
      // Everything else goes through the tunnel.
      'nameserver': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
      if (routing == RoutingMode.ruDirect)
        'nameserver-policy': {
          'rule-set:ru-domains': ['https://77.88.8.8/dns-query', 'https://77.88.8.1/dns-query'],
        },
    },
    'proxies': proxies,
    'proxy-groups': [
      {
        'name': selectorGroup,
        'type': 'select',
        'proxies': [autoGroup, ...allNames],
      },
      {
        'name': autoGroup,
        'type': 'url-test',
        'proxies': allNames,
        'url': latencyTestUrl,
        'interval': 300,
        'tolerance': 50,
        'lazy': false,
      },
    ],
    if (routing == RoutingMode.ruDirect)
      'rule-providers': {
        'ru-domains': {'type': 'file', 'behavior': 'domain', 'format': 'mrs', 'path': './ruleset/ru-domains.mrs'},
        'ru-ips': {'type': 'file', 'behavior': 'ipcidr', 'format': 'mrs', 'path': './ruleset/ru-ips.mrs'},
      },
    'rules': [
      'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
      'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
      'IP-CIDR,169.254.0.0/16,DIRECT,no-resolve',
      'IP-CIDR6,fe80::/10,DIRECT,no-resolve',
      'IP-CIDR6,fc00::/7,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,local,DIRECT',
      if (routing == RoutingMode.ruDirect) ...[
        'DOMAIN-SUFFIX,ru,DIRECT',
        'DOMAIN-SUFFIX,xn--p1ai,DIRECT',
        'DOMAIN-SUFFIX,su,DIRECT',
        'RULE-SET,ru-domains,DIRECT',
        'RULE-SET,ru-ips,DIRECT,no-resolve',
      ],
      'MATCH,$selectorGroup',
    ],
  };

  // Mihomo restores the selector to its first member; put the choice first.
  final group = (config['proxy-groups'] as List).first as Map<String, dynamic>;
  final members = (group['proxies'] as List<String>)..remove(selectedName);
  group['proxies'] = [selectedName, ...members];

  return const JsonEncoder.withIndent('  ').convert(config);
}
