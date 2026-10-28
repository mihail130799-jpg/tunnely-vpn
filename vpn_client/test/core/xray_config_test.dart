import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunnely/core/link_parser.dart';
import 'package:tunnely/core/xray_config.dart';
import 'package:tunnely/models/server_profile.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';

ServerProfile _p(String id, String link) => ServerProfile(id: id, proxy: parseLink(link));

Map<String, dynamic> _outbound(String link) => toXrayOutbound(parseLink(link), 'p');

void main() {
  group('outbound conversion', () {
    test('vless reality vision + VLESS encryption keeps the key fingerprint', () {
      final o = _outbound(
        'vless://$_uuid@a.example.com:443?type=tcp&security=reality&pbk=PUB&sid=ab12&sni=www.microsoft.com'
        '&fp=firefox&flow=xtls-rprx-vision&encryption=mlkem768x25519plus.native.0rtt.KEY#DE',
      );
      expect(o['protocol'], 'vless');
      final user = ((o['settings']['vnext'] as List).single['users'] as List).single as Map;
      expect(user, {'id': _uuid, 'encryption': 'mlkem768x25519plus.native.0rtt.KEY', 'flow': 'xtls-rprx-vision'});
      final st = o['streamSettings'] as Map;
      expect(st['network'], 'raw');
      expect(st['security'], 'reality');
      expect(st['realitySettings'], {
        'serverName': 'www.microsoft.com',
        'fingerprint': 'firefox',
        'publicKey': 'PUB',
        'shortId': 'ab12',
        'spiderX': '',
      });
    });

    test('vless without encryption param uses none', () {
      final o = _outbound('vless://$_uuid@a.example.com:443?security=tls&sni=a.example.com#x');
      final user = ((o['settings']['vnext'] as List).single['users'] as List).single as Map;
      expect(user['encryption'], 'none');
      expect(user.containsKey('flow'), false);
      expect((o['streamSettings'] as Map)['security'], 'tls');
    });

    test('ws / grpc / xhttp / httpupgrade transports', () {
      expect((_outbound('vless://$_uuid@h:443?type=ws&path=%2Fw&host=h.example.com&security=tls#x')['streamSettings']
          as Map)['wsSettings'], {'path': '/w', 'host': 'h.example.com'});
      expect((_outbound('vless://$_uuid@h:443?type=grpc&serviceName=svc&security=tls#x')['streamSettings']
          as Map)['grpcSettings'], {'serviceName': 'svc'});
      expect((_outbound('vless://$_uuid@h:443?type=xhttp&path=%2Fx&mode=auto&security=tls#x')['streamSettings']
          as Map)['xhttpSettings'], {'path': '/x', 'mode': 'auto'});
      final hu = _outbound('vless://$_uuid@h:443?type=httpupgrade&path=%2Fu&host=u.example.com#x')['streamSettings'] as Map;
      expect(hu['network'], 'httpupgrade');
      expect(hu['httpupgradeSettings'], {'path': '/u', 'host': 'u.example.com'});
    });

    test('trojan defaults to tls', () {
      final o = _outbound('trojan://pw@t.example.com:443?sni=t.example.com#t');
      expect(o['protocol'], 'trojan');
      expect((o['settings']['servers'] as List).single, {'address': 't.example.com', 'port': 443, 'password': 'pw'});
      expect((o['streamSettings'] as Map)['security'], 'tls');
    });

    test('shadowsocks and vmess', () {
      final ss = _outbound('ss://YWVzLTI1Ni1nY206cHc@s.example.com:8388#s');
      expect((ss['settings']['servers'] as List).single['method'], 'aes-256-gcm');
      final vm = toXrayOutbound({
        'type': 'vmess', 'server': 'v.example.com', 'port': 443, 'uuid': _uuid, 'cipher': 'auto', 'tls': true,
      }, 'v');
      expect(vm['protocol'], 'vmess');
    });

    test('unsupported protocols are reported', () {
      expect(() => _outbound('hy2://pw@h.example.com:443#h'), throwsA(isA<UnsupportedServer>()));
      expect(() => _outbound('tuic://$_uuid:pw@t.example.com:443#t'), throwsA(isA<UnsupportedServer>()));
    });
  });

  group('tunnel config', () {
    final servers = [
      _p('a', 'vless://$_uuid@a.example.com:443?security=reality&pbk=K&sid=1&fp=firefox#A'),
      _p('b', 'trojan://pw@b.example.com:443#B'),
      _p('h', 'hy2://pw@h.example.com:443#H'),
    ];

    Map<String, dynamic> build({String? selected, RoutingMode routing = RoutingMode.ruDirect, String? preferred}) =>
        jsonDecode(buildXrayConfig(
          servers: servers,
          selected: selected,
          routing: routing,
          ruIps: const ['2.56.24.0/22'],
          preferredAuto: preferred,
        ).json) as Map<String, dynamic>;

    List<Map> rules(Map<String, dynamic> c) => ((c['routing'] as Map)['rules'] as List).cast<Map>();

    test('tun inbound and stats', () {
      final c = build();
      final tun = (c['inbounds'] as List).single as Map;
      expect(tun['tag'], tunInboundTag);
      expect(tun['protocol'], 'tun');
      expect((c['policy'] as Map)['system'], {
        'statsInboundUplink': true,
        'statsInboundDownlink': true,
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      });
    });

    test('unsupported servers are left out and reported', () {
      final cfg = buildXrayConfig(servers: servers, selected: null);
      expect(cfg.outboundTags.keys, ['a', 'b']);
      expect(cfg.unsupported.keys, ['h']);
    });

    test('auto uses a least-ping balancer with the preferred server as fallback', () {
      final c = build(preferred: 'b');
      final b = ((c['routing'] as Map)['balancers'] as List).single as Map;
      expect(b['selector'], ['p-a', 'p-b']);
      expect(b['fallbackTag'], 'p-b');
      expect(rules(c).last['balancerTag'], autoBalancerTag);
      expect(c['observatory'], isNotNull);
    });

    test('selected server routes everything to its outbound', () {
      final c = build(selected: 'b');
      expect(rules(c).last['outboundTag'], 'p-b');
      expect((c['routing'] as Map).containsKey('balancers'), false);
      expect(c.containsKey('observatory'), false);
    });

    test('dns port 53 is answered by xray before private ranges go direct', () {
      final r = rules(build());
      final dns = r.indexWhere((x) => x['outboundTag'] == 'dns-out');
      final private = r.indexWhere((x) => (x['ip'] as List?)?.contains('172.16.0.0/12') ?? false);
      expect(dns, greaterThanOrEqualTo(0));
      expect(dns, lessThan(private));
    });

    test('ru-direct adds russian domains and IPs, global does not', () {
      expect(rules(build()).any((x) => (x['ip'] as List?)?.contains('2.56.24.0/22') ?? false), true);
      final g = build(routing: RoutingMode.global);
      expect(rules(g).any((x) => (x['domain'] as List?)?.contains('domain:ru') ?? false), false);
    });

    test('no supported servers throws', () {
      expect(() => buildXrayConfig(servers: [servers.last], selected: null), throwsArgumentError);
    });

    test('probe config has outbounds only', () {
      final c = jsonDecode(buildProbeConfig(servers)) as Map;
      expect(c.containsKey('inbounds'), false);
      expect((c['outbounds'] as List).map((o) => o['tag']), ['p-a', 'p-b', 'direct']);
    });

    // Golden files consumed by vpn_core's Go test, which validates them with
    // the real Xray config loader (vpn_core/tunnelycore/core_test.go).
    test('writes golden configs for Go validation', () {
      final golden = [
        _p('0', 'vless://$_uuid@a.example.com:443?type=tcp&security=reality&pbk=SGVsbG9Xb3JsZEhlbGxvV29ybGRIZWxsb1dvcmxkMTI'
            '&sid=6ba8&sni=www.microsoft.com&fp=firefox&flow=xtls-rprx-vision#DE'),
        _p('1', 'vless://$_uuid@b.example.com:443?type=xhttp&path=%2Fx&security=tls&sni=b.example.com#XH'),
        _p('2', 'vless://$_uuid@c.example.com:443?type=ws&path=%2Fws&host=c.example.com&security=tls#WS'),
        _p('3', 'trojan://pw@d.example.com:443?sni=d.example.com#TR'),
        _p('4', 'ss://YWVzLTI1Ni1nY206cHc@e.example.com:8388#SS'),
      ];
      final dir = Directory('../vpn_core/tunnelycore/testdata')..createSync(recursive: true);
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        f.deleteSync();
      }
      File('${dir.path}/xray_auto_ru.json').writeAsStringSync(
          buildXrayConfig(servers: golden, selected: null, ruIps: const ['2.56.24.0/22', '5.8.0.0/16']).json);
      File('${dir.path}/xray_selected_global.json').writeAsStringSync(
          buildXrayConfig(servers: golden, selected: '0', routing: RoutingMode.global, ipv6: false).json);
      File('${dir.path}/xray_probe.json').writeAsStringSync(buildProbeConfig(golden));
    });
  });
}
