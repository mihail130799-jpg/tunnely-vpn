import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunnely/providers/app_controller.dart';
import 'package:tunnely/providers/update_controller.dart';
import 'package:tunnely/services/update_service.dart';

import '../providers/app_controller_test.dart' show FakeVpn;

final _apk = utf8.encode('fake apk bytes');
final _apkHash = sha256.convert(_apk).toString();

Map<String, dynamic> _release({String tag = 'v0.4.0', bool prerelease = false, bool withSums = true}) => {
      'tag_name': tag,
      'draft': false,
      'prerelease': prerelease,
      'body': '## Что нового\n- **Быстрее**',
      'html_url': 'https://github.com/$releasesRepo/releases/tag/$tag',
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          {
            'name': 'Tunnely-0.4.0-$abi.apk',
            'size': _apk.length,
            'browser_download_url': 'https://dl.example/Tunnely-0.4.0-$abi.apk',
          },
        if (withSums) {'name': 'SHA256SUMS.txt', 'browser_download_url': 'https://dl.example/SHA256SUMS.txt'},
      ],
    };

MockClient _client(Map<String, dynamic> release, {List<int>? apk, int status = 200}) => MockClient((req) async {
      final url = req.url.toString();
      if (url.endsWith('/releases/latest')) return http.Response.bytes(utf8.encode(jsonEncode(release)), status);
      if (url.endsWith('SHA256SUMS.txt')) {
        return http.Response('$_apkHash  Tunnely-0.4.0-arm64-v8a.apk\n${'0' * 64} *Tunnely-0.4.0-x86_64.apk\n', 200);
      }
      if (url.endsWith('.apk')) return http.Response.bytes(apk ?? _apk, 200);
      return http.Response('', 404);
    });

void main() {
  test('compareVersions', () {
    expect(compareVersions('0.10.0', '0.9.9'), 1);
    expect(compareVersions('v0.3.0', '0.3.0+4'), 0);
    expect(compareVersions('0.3', '0.3.1'), -1);
    expect(compareVersions('1.0.0-beta', '0.9.0'), 1);
  });

  test('parseSha256Sums handles text and binary markers', () {
    final m = parseSha256Sums('${'A' * 64}  a.apk\r\n${'b' * 64} *b.apk\ngarbage\n');
    expect(m, {'a.apk': 'a' * 64, 'b.apk': 'b' * 64});
  });

  group('UpdateService.check', () {
    test('newer release returns the APK for this ABI with its hash', () async {
      final info = await UpdateService(client: _client(_release())).check(current: '0.3.0', abi: 'arm64-v8a');
      expect(info!.version, '0.4.0');
      expect(info.apkName, 'Tunnely-0.4.0-arm64-v8a.apk');
      expect(info.sha256, _apkHash);
    });

    test('same or older version is up to date', () async {
      expect(await UpdateService(client: _client(_release(tag: 'v0.3.0'))).check(current: '0.3.0', abi: 'x86_64'),
          isNull);
    });

    test('prereleases are ignored', () async {
      expect(
          await UpdateService(client: _client(_release(prerelease: true))).check(current: '0.3.0', abi: 'arm64-v8a'),
          isNull);
    });

    test('unknown ABI falls back to arm64', () async {
      final info = await UpdateService(client: _client(_release())).check(current: '0.3.0', abi: 'mips');
      expect(info!.apkName, endsWith('arm64-v8a.apk'));
    });

    test('release without checksums is rejected', () async {
      expect(
        UpdateService(client: _client(_release(withSums: false))).check(current: '0.3.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('server error is reported', () async {
      expect(
        UpdateService(client: _client(_release(), status: 500)).check(current: '0.3.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('download', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('tunnely_upd'));
    tearDown(() async => tmp.delete(recursive: true));

    test('verifies the hash', () async {
      final svc = UpdateService(client: _client(_release()));
      final info = (await svc.check(current: '0.3.0', abi: 'arm64-v8a'))!;
      final progress = <double>[];
      final f = await svc.download(info, tmp, onProgress: progress.add);
      expect(await f.readAsBytes(), _apk);
      expect(progress.last, 1.0);
    });

    test('tampered file is deleted and rejected', () async {
      final svc = UpdateService(client: _client(_release(), apk: utf8.encode('evil')));
      final info = (await svc.check(current: '0.3.0', abi: 'arm64-v8a'))!;
      await expectLater(svc.download(info, tmp), throwsA(isA<UpdateException>()));
      expect(tmp.listSync(), isEmpty);
    });
  });

  group('UpdateController', () {
    late Directory tmp;
    late FakeVpn vpn;
    late ProviderContainer c;

    ProviderContainer make(UpdateService svc) {
      final c = ProviderContainer(overrides: [
        vpnPlatformProvider.overrideWithValue(vpn),
        updateServiceProvider.overrideWithValue(svc),
        updateDirProvider.overrideWithValue(() async => Directory('${tmp.path}/updates')),
      ]);
      c.listen(updateControllerProvider, (_, _) {});
      return c;
    }

    Future<void> settle() async {
      for (var i = 0; i < 50 && c.read(updateControllerProvider).status != UpdateStatus.available; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('tunnely_upd');
      vpn = FakeVpn();
      c = make(UpdateService(client: _client(_release())));
    });
    tearDown(() async {
      c.dispose();
      await tmp.delete(recursive: true);
    });

    test('first launch checks automatically and remembers the time', () async {
      await settle();
      final u = c.read(updateControllerProvider);
      expect(u.current, '0.3.0');
      expect(u.info?.version, '0.4.0');
      expect((await SharedPreferences.getInstance()).getInt('update_last_check'), isNotNull);
    });

    test('download then install; retry after permission reuses the file', () async {
      await settle();
      vpn.installAllowed = false;
      await c.read(updateControllerProvider.notifier).downloadAndInstall();
      expect(vpn.installs.single, endsWith('Tunnely-0.4.0-arm64-v8a.apk'));
      expect(c.read(updateControllerProvider).error, contains('Разрешите'));
      expect(c.read(updateControllerProvider).downloaded, isTrue);

      vpn.installAllowed = true;
      await c.read(updateControllerProvider.notifier).downloadAndInstall();
      expect(vpn.installs, hasLength(2));
      expect(vpn.installs.last, vpn.installs.first);
      expect(c.read(updateControllerProvider).error, isNull);
    });

    test('recent check is not repeated on launch', () async {
      c.dispose();
      SharedPreferences.setMockInitialValues({'update_last_check': DateTime.now().millisecondsSinceEpoch});
      var requests = 0;
      c = make(UpdateService(client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      })));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, 0);
      expect(c.read(updateControllerProvider).status, UpdateStatus.idle);
      expect(c.read(updateControllerProvider).current, '0.3.0');
    });
  });
}
