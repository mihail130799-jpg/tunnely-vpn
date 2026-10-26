import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tunnely/core/mihomo_config.dart';
import 'package:tunnely/models/app_settings.dart';
import 'package:tunnely/providers/app_controller.dart';
import 'package:tunnely/services/storage.dart';
import 'package:tunnely/services/subscription_service.dart';
import 'package:tunnely/services/vpn_platform.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';
const _vless = 'vless://$_uuid@a.example.com:443?security=reality&pbk=K&sid=1#🇩🇪 Германия';
const _trojan = 'trojan://pw@b.example.com:443#Нидерланды';

class FakeVpn implements VpnPlatform {
  final _states = StreamController<VpnStateInfo>.broadcast();
  bool granted = true;
  String? validateError;
  String? startedConfig;
  String? startedServerName;
  int stops = 0;
  final selects = <(String, String)>[];
  VpnStateInfo current = VpnStateInfo.disconnected;
  int delayResult = 42;

  void emit(VpnStateInfo s) {
    current = s;
    _states.add(s);
  }

  @override
  Stream<VpnStateInfo> get states => _states.stream;
  @override
  Future<bool> prepare() async => granted;
  @override
  Future<void> start({required String config, String? serverName}) async {
    startedConfig = config;
    startedServerName = serverName;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<VpnStateInfo> state() async => current;
  @override
  Future<TrafficInfo> traffic() async => const TrafficInfo(up: 1, down: 2);
  @override
  Future<int> delay(String proxyName, String url, {int timeoutMs = 5000}) async => delayResult;
  @override
  Future<bool> select(String group, String name) async {
    selects.add((group, name));
    return true;
  }

  @override
  Future<String?> validate(String config) async => validateError;
  @override
  Future<String> coreVersion() async => 'test';
}

void main() {
  late FakeVpn vpn;
  late MemoryAppStorage storage;
  late ProviderContainer c;
  var subBody = '';
  var subStatus = 200;
  var subHeaders = <String, String>{};
  var fetches = 0;

  AppController ctrl() => c.read(appControllerProvider.notifier);
  AppState st() => c.read(appControllerProvider);

  setUp(() async {
    vpn = FakeVpn();
    storage = MemoryAppStorage();
    subBody = base64.encode(utf8.encode('$_vless\n$_trojan'));
    subStatus = 200;
    subHeaders = {'profile-title': 'Мой VPN', 'subscription-userinfo': 'upload=1; download=2; total=100; expire=0'};
    fetches = 0;
    final client = MockClient((req) async {
      fetches++;
      expect(req.headers['User-Agent'], SubscriptionService.userAgent);
      return http.Response.bytes(utf8.encode(subBody), subStatus, headers: subHeaders);
    });
    c = ProviderContainer(overrides: [
      storageProvider.overrideWithValue(storage),
      vpnPlatformProvider.overrideWithValue(vpn),
      subscriptionServiceProvider.overrideWithValue(SubscriptionService(client: client)),
      tcpPingProvider.overrideWithValue((host, port) async => host.startsWith('a') ? 30 : -1),
    ]);
    c.listen(appControllerProvider, (_, _) {}); // keep alive
    await ctrl().init();
  });

  tearDown(() => c.dispose());

  test('import single key selects it and persists', () async {
    final r = await ctrl().importText(_vless);
    expect(r.added, 1);
    expect(st().servers.single.type, 'vless');
    expect(st().selectedId, st().servers.single.id);
    expect(storage.servers.length, 1);
    expect(storage.selected, st().selectedId);
  });

  test('duplicate key is detected', () async {
    await ctrl().importText(_vless);
    final r = await ctrl().importText('  $_vless  ');
    expect(r.added, 0);
    expect(r.duplicates, 1);
    expect(st().servers.length, 1);
    expect(st().message!.text, contains('уже добавлен'));
  });

  test('invalid key reports error', () async {
    final r = await ctrl().importText('vless://nope');
    expect(r.ok, false);
    expect(st().message!.isError, true);
  });

  test('empty clipboard', () async {
    final r = await ctrl().importText('   ');
    expect(r.ok, false);
  });

  test('subscription url is fetched and grouped', () async {
    final r = await ctrl().importText('https://sub.example.com/abc');
    expect(r.subscription, isNotNull);
    expect(st().subscriptions.single.name, 'Мой VPN');
    expect(st().subscriptions.single.total, 100);
    expect(st().servers.length, 2);
    expect(st().servers.every((s) => s.subscriptionId == r.subscription!.id), true);
  });

  test('deep link tunnely://import?url=', () async {
    await ctrl().importText('tunnely://import?url=${Uri.encodeComponent('https://sub.example.com/x')}');
    expect(st().subscriptions.length, 1);
  });

  test('re-adding same subscription refreshes it instead of duplicating', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    await ctrl().addSubscription('https://sub.example.com/abc');
    expect(st().subscriptions.length, 1);
    expect(fetches, 2);
  });

  test('refresh keeps ids stable and removes vanished servers', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    final vlessId = st().servers.firstWhere((s) => s.type == 'vless').id;
    await ctrl().select(vlessId);
    subBody = _vless; // trojan disappeared
    await ctrl().refreshSubscription(st().subscriptions.single.id);
    expect(st().servers.single.id, vlessId);
    expect(st().selectedId, vlessId);
    expect(st().subscriptions.single.lastError, isNull);
  });

  test('refresh failure keeps old servers and records error', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    subStatus = 403;
    await ctrl().refreshSubscription(st().subscriptions.single.id);
    expect(st().servers.length, 2);
    expect(st().subscriptions.single.lastError, contains('403'));
  });

  test('refresh with selected server removed falls back to auto', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    final trojanId = st().servers.firstWhere((s) => s.type == 'trojan').id;
    await ctrl().select(trojanId);
    subBody = _vless;
    await ctrl().refreshSubscription(st().subscriptions.single.id);
    expect(st().selectedId, isNull);
  });

  test('stale subscriptions refresh after 24h only', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    final before = fetches;
    await ctrl().refreshStaleSubscriptions();
    expect(fetches, before);
  });

  test('remove subscription removes its servers', () async {
    await ctrl().importText(_trojan);
    await ctrl().addSubscription('https://sub.example.com/abc');
    // trojan existed manually, so the subscription only adds vless
    expect(st().servers.length, 2);
    await ctrl().removeSubscription(st().subscriptions.single.id);
    expect(st().servers.single.type, 'trojan');
  });

  test('connect without servers', () async {
    await ctrl().connect();
    expect(vpn.startedConfig, isNull);
    expect(st().message!.isError, true);
  });

  test('connect denied permission', () async {
    await ctrl().importText(_vless);
    vpn.granted = false;
    await ctrl().connect();
    expect(vpn.startedConfig, isNull);
    expect(st().message!.text, contains('разрешите'));
  });

  test('connect with invalid config does not start', () async {
    await ctrl().importText(_vless);
    vpn.validateError = 'boom';
    await ctrl().connect();
    expect(vpn.startedConfig, isNull);
  });

  test('connect starts with selected server first', () async {
    await ctrl().importText('$_vless\n$_trojan');
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    await ctrl().connect();
    final cfg = jsonDecode(vpn.startedConfig!) as Map<String, dynamic>;
    expect(((cfg['proxy-groups'] as List).first as Map)['proxies'].first, 'Нидерланды');
    expect(vpn.startedServerName, 'Нидерланды');
  });

  test('state stream drives UI state and toggle stops', () async {
    await ctrl().importText(_vless);
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(st().vpn.status, VpnStatus.connected);
    await ctrl().toggle();
    expect(vpn.stops, 1);
  });

  test('error state shows message once', () async {
    vpn.emit(const VpnStateInfo(VpnStatus.error, error: 'Не удалось подключиться: x'));
    await Future<void>.delayed(Duration.zero);
    expect(st().message!.text, contains('Не удалось'));
  });

  test('switching server while connected uses core selector', () async {
    await ctrl().importText('$_vless\n$_trojan');
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    expect(vpn.selects.last, (selectorGroup, 'Нидерланды'));
    await ctrl().select(null);
    expect(vpn.selects.last, (selectorGroup, autoGroup));
  });

  test('latency uses tcp ping when disconnected', () async {
    await ctrl().importText('$_vless\n$_trojan');
    await ctrl().testLatency();
    final byType = {for (final s in st().servers) s.type: st().latency[s.id]};
    expect(byType, {'vless': 30, 'trojan': -1});
    expect(st().testing, false);
  });

  test('latency uses core delay when connected', () async {
    await ctrl().importText(_vless);
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    await ctrl().testLatency();
    expect(st().latency.values.single, 42);
  });

  test('changing routing while connected reconnects', () async {
    await ctrl().importText(_vless);
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    vpn.startedConfig = null;
    await ctrl().updateSettings(const AppSettings(routing: RoutingMode.global));
    expect(vpn.startedConfig, isNotNull);
    expect(storage.settings.routing, RoutingMode.global);
  });

  test('adding a subscription keeps the current selection', () async {
    await ctrl().importText('vless://$_uuid@local.example.com:8443?security=reality&pbk=K#Local');
    final local = st().selectedId;
    expect(local, isNotNull);
    await ctrl().addSubscription('https://sub.example.com/abc');
    expect(st().selectedId, local);
    await ctrl().refreshSubscription(st().subscriptions.single.id);
    expect(st().selectedId, local);
  });

  test('dead server after switching is reported', () async {
    await ctrl().importText('$_vless\n$_trojan');
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    vpn.delayResult = -1;
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    expect(st().message!.isError, true);
    expect(st().message!.text, contains('не отвечает'));
    expect(st().latency[trojan.id], -1);
  });

  test('healthy server after connect is not reported', () async {
    await ctrl().importText(_vless);
    await ctrl().connect();
    final before = st().message?.id;
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(st().message?.id, before);
    expect(st().latency.values.single, 42);
  });

  test('stableId is deterministic', () {
    expect(stableId('x'), stableId('x'));
    expect(stableId('x'), isNot(stableId('y')));
    expect(stableId('x').length, 16);
  });
}
