import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tunnely/core/xray_config.dart';
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
  List<String> startedBypass = const [];
  List<String> installed = const ['ru.sberbankmobile', 'com.vkontakte.android', 'org.telegram.messenger'];
  int stops = 0;
  int starts = 0;
  VpnStateInfo current = VpnStateInfo.disconnected;

  /// Outbound tag -> result; unknown tags succeed with [defaultDelay].
  final delays = <String, DelayResult>{};
  DelayResult defaultDelay = const DelayResult(42, null);
  final probeConfigs = <String?>[];

  void emit(VpnStateInfo s) {
    current = s;
    _states.add(s);
  }

  @override
  Stream<VpnStateInfo> get states => _states.stream;
  @override
  Future<bool> prepare() async => granted;
  @override
  Future<void> start({required String config, String? serverName, List<String> bypassApps = const []}) async {
    starts++;
    startedBypass = bypassApps;
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
  Future<DelayResult> delay(String tag, String url, {int timeoutMs = 5000, String? probeConfig}) async {
    probeConfigs.add(probeConfig);
    return delays[tag] ?? defaultDelay;
  }

  @override
  Future<NativeLogs> logs() async => const NativeLogs('core line', 'service line');
  @override
  Future<void> clearLogs() async {}
  @override
  Future<List<String>> installedPackages() async => installed;
  @override
  Future<List<InstalledApp>> installedApps() async =>
      [for (final p in installed) InstalledApp(package: p, label: p)];
  @override
  Future<String?> validate(String config) async => validateError;
  @override
  Future<String> coreVersion() async => 'test';

  String appVersion = '0.3.0';
  final installs = <String>[];
  bool installAllowed = true;
  @override
  Future<({String version, String abi})> appInfo() async => (version: appVersion, abi: 'arm64-v8a');
  @override
  Future<bool> installApk(String path) async {
    installs.add(path);
    return installAllowed;
  }
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
      ruIpsLoaderProvider.overrideWithValue(() async => const ['2.56.24.0/22']),
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

  test('connect with a selected server routes everything to it', () async {
    await ctrl().importText('$_vless\n$_trojan');
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    await ctrl().connect();
    final cfg = jsonDecode(vpn.startedConfig!) as Map<String, dynamic>;
    final rules = ((cfg['routing'] as Map)['rules'] as List).cast<Map>();
    expect(rules.last['outboundTag'], 'p-${trojan.id}');
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

  test('switching server while connected restarts the tunnel on it', () async {
    await ctrl().importText('$_vless\n$_trojan');
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    final starts = vpn.starts;
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    expect(vpn.starts, starts + 1);
    expect(vpn.startedServerName, 'Нидерланды');
  });

  test('latency while disconnected uses a probe config (real handshake)', () async {
    await ctrl().importText('$_vless\n$_trojan');
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    vpn.delays['p-${trojan.id}'] = const DelayResult(-1, 'context deadline exceeded');
    await ctrl().testLatency();
    final vless = st().servers.firstWhere((s) => s.type == 'vless');
    expect(st().latency[vless.id], 42);
    expect(st().latency[trojan.id], -1);
    expect(st().failures[trojan.id], contains('тайм-аут'));
    expect(vpn.probeConfigs.every((c) => c != null && c.contains('outbounds')), true);
    expect(st().testing, false);
  });

  test('latency while connected goes through the running core', () async {
    await ctrl().importText(_vless);
    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    vpn.probeConfigs.clear();
    await ctrl().testLatency();
    expect(st().latency.values.first, 42);
    expect(vpn.probeConfigs.every((c) => c == null), true);
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

  test('dead selected server is reported with the reason', () async {
    await ctrl().importText('$_vless\n$_trojan');
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    await ctrl().select(trojan.id);
    await ctrl().connect();
    vpn.delays['p-${trojan.id}'] = const DelayResult(-1, 'EOF');
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(st().message!.isError, true);
    expect(st().message!.text, contains('ключ не принят'));
    expect(st().latency[trojan.id], -1);
  });

  test('all servers dead in auto: expired subscription is detected', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    vpn.defaultDelay = const DelayResult(-1, 'EOF');
    await ctrl().connect();
    subStatus = 404;
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(st().message!.text, contains('больше не действует'));
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

  test('auto mode probes servers first and starts on the fastest live one', () async {
    await ctrl().addSubscription('https://sub.example.com/abc'); // no server selected -> Auto
    expect(st().isAuto, true);
    final vless = st().servers.firstWhere((s) => s.type == 'vless');
    final trojan = st().servers.firstWhere((s) => s.type == 'trojan');
    vpn.delays['p-${vless.id}'] = const DelayResult(-1, 'EOF');
    vpn.delays['p-${trojan.id}'] = const DelayResult(120, null);
    await ctrl().connect();
    final cfg = jsonDecode(vpn.startedConfig!) as Map<String, dynamic>;
    final balancer = ((cfg['routing'] as Map)['balancers'] as List).single as Map;
    expect(balancer['fallbackTag'], 'p-${trojan.id}');
    expect(vpn.startedServerName, 'Авто: Нидерланды');
  });

  test('diagnostics report has no secrets', () async {
    await ctrl().addSubscription('https://sub.example.com/abc');
    final r = await ctrl().diagnosticsReport();
    expect(r, contains('Проверка серверов'));
    expect(r, isNot(contains(_uuid)));
    expect(r, isNot(contains('sub.example.com/abc')));
    expect(r, contains('core line'));
    expect(r, contains('service line'));
  });

  test('app log records connects and errors without secrets', () async {
    await ctrl().importText(_vless);
    vpn.granted = false;
    await ctrl().connect();
    final log = await ctrl().fullLog();
    expect(log, contains('[import] добавлено 1'));
    expect(log, contains('разрешите Tunnely'));
    expect(log, isNot(contains(_uuid)));
  });

  test('foreign-only mode sends installed Russian apps as bypass list', () async {
    await ctrl().importText(_vless);
    await ctrl().connect();
    expect(vpn.startedBypass, ['com.vkontakte.android', 'ru.sberbankmobile']);
  });

  test('global mode bypasses only manual choices', () async {
    await ctrl().importText(_vless);
    await ctrl().updateSettings(const AppSettings(routing: RoutingMode.global, alwaysDirectApps: {'org.telegram.messenger'}));
    await ctrl().connect();
    expect(vpn.startedBypass, ['org.telegram.messenger']);
  });

  test('setAppDirect records only deviations and reconnects when on', () async {
    await ctrl().importText(_vless);
    expect(ctrl().appIsDirect('ru.sberbankmobile'), true);
    expect(ctrl().appIsDirect('org.telegram.messenger'), false);
    await ctrl().setAppDirect('ru.sberbankmobile', false);
    await ctrl().setAppDirect('org.telegram.messenger', true);
    expect(st().settings.alwaysVpnApps, {'ru.sberbankmobile'});
    expect(st().settings.alwaysDirectApps, {'org.telegram.messenger'});
    await ctrl().setAppDirect('ru.sberbankmobile', true);
    expect(st().settings.alwaysVpnApps, isEmpty, reason: 'back to automatic');

    await ctrl().connect();
    vpn.emit(VpnStateInfo(VpnStatus.connected, connectedSince: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final starts = vpn.starts;
    await ctrl().setAppDirect('com.vkontakte.android', false);
    expect(vpn.starts, starts + 1);
    expect(vpn.startedBypass, ['org.telegram.messenger', 'ru.sberbankmobile']);
  });

  test('stableId is deterministic', () {
    expect(stableId('x'), stableId('x'));
    expect(stableId('x'), isNot(stableId('y')));
    expect(stableId('x').length, 16);
  });
}
