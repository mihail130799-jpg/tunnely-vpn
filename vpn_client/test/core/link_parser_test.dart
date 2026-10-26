import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunnely/core/link_parser.dart';

// All keys below are synthetic test data, not real credentials.
const _uuid = '11111111-2222-3333-4444-555555555555';

void main() {
  group('vless', () {
    test('reality + vision', () {
      final p = parseLink(
        'vless://$_uuid@example.com:443?type=tcp&security=reality&pbk=AbCdEf_123-xyz&sid=6ba85179e30d4fc2'
        '&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision&encryption=none#%F0%9F%87%A9%F0%9F%87%AA%20Germany',
      );
      expect(p['type'], 'vless');
      expect(p['server'], 'example.com');
      expect(p['port'], 443);
      expect(p['uuid'], _uuid);
      expect(p['flow'], 'xtls-rprx-vision');
      expect(p['tls'], true);
      expect(p['servername'], 'www.microsoft.com');
      expect(p['client-fingerprint'], 'chrome');
      expect(p['reality-opts'], {'public-key': 'AbCdEf_123-xyz', 'short-id': '6ba85179e30d4fc2'});
      expect(p['name'], '🇩🇪 Germany');
      expect(p.containsKey('network'), false);
      expect(p.containsKey('encryption'), false);
    });

    test('reality defaults fingerprint to chrome', () {
      final p = parseLink('vless://$_uuid@1.2.3.4:8443?security=reality&pbk=KEY#x');
      expect(p['client-fingerprint'], 'chrome');
      expect((p['reality-opts'] as Map).containsKey('short-id'), false);
    });

    test('reality without pbk is rejected', () {
      expect(() => parseLink('vless://$_uuid@1.2.3.4:443?security=reality#x'), throwsA(isA<ImportException>()));
    });

    test('tls + ws', () {
      final p = parseLink('vless://$_uuid@cdn.example.org:443?type=ws&security=tls&path=%2Fws%3Fed%3D2048&host=a.example.org&sni=a.example.org&alpn=h2,http/1.1#WS');
      expect(p['network'], 'ws');
      expect(p['ws-opts'], {'path': '/ws?ed=2048', 'headers': {'Host': 'a.example.org'}});
      expect(p['servername'], 'a.example.org');
      expect(p['alpn'], ['h2', 'http/1.1']);
    });

    test('grpc', () {
      final p = parseLink('vless://$_uuid@g.example.org:443?type=grpc&serviceName=svc&security=tls#g');
      expect(p['network'], 'grpc');
      expect(p['grpc-opts'], {'grpc-service-name': 'svc'});
    });

    test('xhttp + reality', () {
      final p = parseLink('vless://$_uuid@x.example.org:443?type=xhttp&path=%2Fxh&mode=auto&security=reality&pbk=K&sid=ab#xh');
      expect(p['network'], 'xhttp');
      expect(p['xhttp-opts'], {'path': '/xh', 'mode': 'auto'});
      expect(p['reality-opts'], {'public-key': 'K', 'short-id': 'ab'});
    });

    test('plain tcp without security', () {
      final p = parseLink('vless://$_uuid@10.0.0.1:1234#plain');
      expect(p.containsKey('tls'), false);
    });

    test('missing port', () {
      expect(() => parseLink('vless://$_uuid@example.com?security=tls'), throwsA(isA<ImportException>()));
    });

    test('missing uuid', () {
      expect(() => parseLink('vless://example.com:443'), throwsA(isA<ImportException>()));
    });

    test('unknown transport', () {
      expect(() => parseLink('vless://$_uuid@e.com:443?type=quic'), throwsA(isA<ImportException>()));
    });

    test('name falls back to host:port', () {
      expect(parseLink('vless://$_uuid@e.com:443')['name'], 'e.com:443');
    });
  });

  group('trojan', () {
    test('default tls', () {
      final p = parseLink('trojan://p%40ss@t.example.com:443?sni=t.example.com#Trojan');
      expect(p['type'], 'trojan');
      expect(p['password'], 'p@ss');
      expect(p['sni'], 't.example.com');
      expect(p.containsKey('tls'), false);
    });

    test('ws', () {
      final p = parseLink('trojan://pw@t.example.com:443?type=ws&path=%2Ftr&host=h.example.com#t');
      expect(p['network'], 'ws');
      expect((p['ws-opts'] as Map)['path'], '/tr');
    });
  });

  group('shadowsocks', () {
    test('SIP002 base64 userinfo', () {
      final ui = base64Url.encode(utf8.encode('chacha20-ietf-poly1305:secret')).replaceAll('=', '');
      final p = parseLink('ss://$ui@s.example.com:8388#SS%20node');
      expect(p['type'], 'ss');
      expect(p['cipher'], 'chacha20-ietf-poly1305');
      expect(p['password'], 'secret');
      expect(p['port'], 8388);
      expect(p['name'], 'SS node');
    });

    test('SIP002 plain 2022 userinfo', () {
      final p = parseLink('ss://2022-blake3-aes-128-gcm:YWJjZGVmZ2hpamtsbW5vcA%3D%3D@s.example.com:443#n');
      expect(p['cipher'], '2022-blake3-aes-128-gcm');
      expect(p['password'], 'YWJjZGVmZ2hpamtsbW5vcA==');
    });

    test('legacy fully encoded', () {
      final body = base64.encode(utf8.encode('aes-256-gcm:pw@1.2.3.4:8388'));
      final p = parseLink('ss://$body#legacy');
      expect(p['server'], '1.2.3.4');
      expect(p['cipher'], 'aes-256-gcm');
    });

    test('obfs plugin', () {
      final ui = base64Url.encode(utf8.encode('aes-128-gcm:pw'));
      final p = parseLink('ss://$ui@s.example.com:8388/?plugin=obfs-local%3Bobfs%3Dtls%3Bobfs-host%3Dbing.com#o');
      expect(p['plugin'], 'obfs');
      expect(p['plugin-opts'], {'mode': 'tls', 'host': 'bing.com'});
    });
  });

  group('vmess', () {
    test('ws tls', () {
      final j = {
        'v': '2', 'ps': 'VM', 'add': 'v.example.com', 'port': '443', 'id': _uuid, 'aid': '0',
        'scy': 'auto', 'net': 'ws', 'host': 'h.example.com', 'path': '/vm', 'tls': 'tls', 'sni': 'h.example.com',
      };
      final p = parseLink('vmess://${base64.encode(utf8.encode(jsonEncode(j)))}');
      expect(p['type'], 'vmess');
      expect(p['name'], 'VM');
      expect(p['port'], 443);
      expect(p['alterId'], 0);
      expect(p['network'], 'ws');
      expect(p['tls'], true);
      expect(p['servername'], 'h.example.com');
    });

    test('garbage', () {
      expect(() => parseLink('vmess://not-base64!!'), throwsA(isA<ImportException>()));
    });
  });

  group('hysteria2 / tuic', () {
    test('hy2 alias', () {
      final p = parseLink('hy2://pw@h.example.com:8443?sni=h.example.com&obfs=salamander&obfs-password=x&insecure=1#H');
      expect(p['type'], 'hysteria2');
      expect(p['obfs'], 'salamander');
      expect(p['obfs-password'], 'x');
      expect(p['skip-cert-verify'], true);
    });

    test('hysteria2 default port', () {
      expect(parseLink('hysteria2://pw@h.example.com#H')['port'], 443);
    });

    test('tuic', () {
      final p = parseLink('tuic://$_uuid:pw@t.example.com:443?congestion_control=bbr&alpn=h3&sni=t.example.com#T');
      expect(p['type'], 'tuic');
      expect(p['uuid'], _uuid);
      expect(p['password'], 'pw');
      expect(p['congestion-controller'], 'bbr');
      expect(p['alpn'], ['h3']);
    });
  });

  test('unsupported scheme', () {
    expect(() => parseLink('wireguard://abc'), throwsA(isA<ImportException>()));
    expect(() => parseLink('hello'), throwsA(isA<ImportException>()));
  });

  test('looksLikeLink', () {
    expect(looksLikeLink('vless://x'), true);
    expect(looksLikeLink('https://x'), false);
  });
}
