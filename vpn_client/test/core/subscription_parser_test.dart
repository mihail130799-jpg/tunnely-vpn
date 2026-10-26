import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunnely/core/country.dart';
import 'package:tunnely/core/subscription_parser.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';
final _l1 = 'vless://$_uuid@a.example.com:443?security=reality&pbk=K&sid=1#🇩🇪 Germany';
const _l2 = 'trojan://pw@b.example.com:443#Нидерланды';

void main() {
  test('plain newline list', () {
    final r = parseBatch('$_l1\n\n$_l2\n');
    expect(r.proxies.length, 2);
    expect(r.errors, isEmpty);
  });

  test('base64 list (v2ray format)', () {
    final r = parseBatch(base64.encode(utf8.encode('$_l1\n$_l2')));
    expect(r.proxies.map((p) => p['type']), ['vless', 'trojan']);
  });

  test('url-safe base64 without padding', () {
    final b = base64Url.encode(utf8.encode('$_l1\n$_l2')).replaceAll('=', '');
    expect(parseBatch(b).proxies.length, 2);
  });

  test('bad lines are reported, good kept', () {
    final r = parseBatch('$_l1\nvless://broken\nnot a link\nfoo://x');
    expect(r.proxies.length, 1);
    expect(r.errors.length, 2);
  });

  test('clash yaml', () {
    const y = '''
mixed-port: 7890
proxies:
  - name: "DE 1"
    type: vless
    server: de.example.com
    port: "443"
    uuid: $_uuid
    tls: true
    reality-opts:
      public-key: K
  - {name: SS, type: ss, server: s.example.com, port: 8388, cipher: aes-128-gcm, password: pw}
  - name: broken
proxy-groups: []
''';
    final r = parseBatch(y);
    expect(r.proxies.length, 2);
    expect(r.proxies.first['port'], 443);
    expect((r.proxies.first['reality-opts'] as Map)['public-key'], 'K');
    expect(r.errors.length, 1);
  });

  test('empty', () {
    expect(parseBatch('  ').errors, isNotEmpty);
    expect(parseBatch('hello world').errors, isNotEmpty);
  });

  test('headers metadata', () {
    final m = SubscriptionMeta.fromHeaders({
      'profile-title': 'base64:${base64.encode(utf8.encode('Мой VPN'))}',
      'profile-update-interval': '12',
      'subscription-userinfo': 'upload=10; download=20; total=1000; expire=1893456000',
    });
    expect(m.title, 'Мой VPN');
    expect(m.updateIntervalHours, 12);
    expect(m.download, 20);
    expect(m.total, 1000);
    expect(m.expire!.toUtc().year, 2030);
  });

  group('country', () {
    test('flag emoji', () => expect(detectCountry('🇳🇱 Amsterdam 1'), 'NL'));
    test('russian name', () => expect(detectCountry('Финляндия Хельсинки'), 'FI'));
    test('english name', () => expect(detectCountry('Germany-01'), 'DE'));
    test('code token', () => expect(detectCountry('Fast US #2'), 'US'));
    test('UK alias', () => expect(detectCountry('UK London'), 'GB'));
    test('unknown', () => expect(detectCountry('Server 1'), isNull));
  });
}
