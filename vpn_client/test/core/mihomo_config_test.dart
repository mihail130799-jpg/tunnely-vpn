import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunnely/core/link_parser.dart';
import 'package:tunnely/core/mihomo_config.dart';
import 'package:tunnely/models/server_profile.dart';

ServerProfile _s(String id, String name) => ServerProfile(
      id: id,
      proxy: {'name': name, 'type': 'trojan', 'server': '$id.example.com', 'port': 443, 'password': 'pw'},
    );

void main() {
  final servers = [_s('a', 'Germany'), _s('b', 'Germany'), _s('c', 'PROXY')];

  Map<String, dynamic> build({String? selected, RoutingMode routing = RoutingMode.ruDirect}) =>
      jsonDecode(buildMihomoConfig(servers: servers, selected: selected, tunFd: 42, routing: routing).json)
          as Map<String, dynamic>;

  test('tun uses the provided fd and fixed addresses', () {
    final tun = build()['tun'] as Map;
    expect(tun['file-descriptor'], 42);
    expect(tun['inet4-address'], [TunAddresses.ipv4]);
    expect(tun['auto-route'], false);
  });

  test('duplicate and reserved names are made unique', () {
    final names = (build()['proxies'] as List).map((p) => p['name']).toList();
    expect(names, ['Germany', 'Germany (2)', 'PROXY ']);
  });

  test('selected server becomes first in selector', () {
    final g = (build(selected: 'b')['proxy-groups'] as List).first as Map;
    expect(g['name'], selectorGroup);
    expect((g['proxies'] as List).first, 'Germany (2)');
    expect((g['proxies'] as List).toSet().length, (g['proxies'] as List).length);
  });

  test('proxyNames maps ids to unique names', () {
    final c = buildMihomoConfig(servers: servers, selected: null, tunFd: 1);
    expect(c.proxyNames, {'a': 'Germany', 'b': 'Germany (2)', 'c': 'PROXY '});
  });

  test('no selection means auto group', () {
    final g = (build()['proxy-groups'] as List).first as Map;
    expect((g['proxies'] as List).first, autoGroup);
  });

  test('unknown selection falls back to auto', () {
    final g = (build(selected: 'zzz')['proxy-groups'] as List).first as Map;
    expect((g['proxies'] as List).first, autoGroup);
  });

  test('ru-direct routing has russian rules before MATCH', () {
    final rules = (build()['rules'] as List).cast<String>();
    expect(rules, contains('RULE-SET,ru-domains,DIRECT'));
    expect(rules.last, 'MATCH,$selectorGroup');
    expect(build()['rule-providers'], isNotNull);
  });

  test('global routing has no russian rules', () {
    final c = build(routing: RoutingMode.global);
    expect((c['rules'] as List).any((r) => '$r'.contains('ru-')), false);
    expect(c.containsKey('rule-providers'), false);
    expect((c['dns'] as Map).containsKey('nameserver-policy'), false);
  });

  // Golden file consumed by vpn_core's Go test, which validates it with the
  // real Mihomo parser (vpn_core/tunnelycore/core_test.go).
  test('writes golden config for Go validation', () {
    const uuid = '11111111-2222-3333-4444-555555555555';
    final links = [
      'vless://$uuid@a.example.com:443?type=tcp&security=reality&pbk=SGVsbG9Xb3JsZEhlbGxvV29ybGRIZWxsb1dvcmxkMTI&sid=6ba8&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision#DE',
      'vless://$uuid@b.example.com:443?type=xhttp&path=%2Fx&security=tls&sni=b.example.com#XH',
      'vless://$uuid@c.example.com:443?type=ws&path=%2Fws&host=c.example.com&security=tls#WS',
      'trojan://pw@d.example.com:443?sni=d.example.com#TR',
      'ss://YWVzLTI1Ni1nY206cHc@e.example.com:8388#SS',
      'hy2://pw@f.example.com:443?sni=f.example.com#HY2',
      'tuic://$uuid:pw@g.example.com:443?congestion_control=bbr&alpn=h3#TUIC',
    ];
    final servers = [
      for (var i = 0; i < links.length; i++) ServerProfile(id: '$i', proxy: parseLink(links[i])),
    ];
    for (final routing in RoutingMode.values) {
      final out = File('../vpn_core/tunnelycore/testdata/generated_${routing.name}.json');
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(buildMihomoConfig(servers: servers, selected: '0', tunFd: 0, routing: routing).json);
    }
  });

  test('empty server list throws', () {
    expect(() => buildMihomoConfig(servers: [], selected: null, tunFd: 1), throwsArgumentError);
  });
}

