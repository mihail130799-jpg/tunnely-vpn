import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/link_parser.dart';
import '../core/xray_config.dart';
import '../core/subscription_parser.dart';
import '../models/app_settings.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';
import '../services/app_log.dart';
import '../services/storage.dart';
import '../services/subscription_service.dart';
import '../services/vpn_platform.dart';

/// Short message for a snackbar. [id] changes on every new message.
class UiMessage {
  UiMessage(this.text, {this.isError = false}) : id = _next++;
  static int _next = 0;
  final int id;
  final String text;
  final bool isError;
}

class ImportResult {
  const ImportResult({this.added = 0, this.duplicates = 0, this.errors = const [], this.subscription});
  final int added;
  final int duplicates;
  final List<String> errors;
  final Subscription? subscription;

  bool get ok => added > 0 || subscription != null;
}

class AppState {
  const AppState({
    this.loaded = false,
    this.servers = const [],
    this.subscriptions = const [],
    this.selectedId,
    this.settings = const AppSettings(),
    this.vpn = VpnStateInfo.disconnected,
    this.traffic = TrafficInfo.zero,
    this.latency = const {},
    this.testing = false,
    this.refreshing = const {},
    this.failures = const {},
    this.message,
  });

  final bool loaded;
  final List<ServerProfile> servers;
  final List<Subscription> subscriptions;

  /// Chosen server id, or null for automatic (lowest latency).
  final String? selectedId;
  final AppSettings settings;
  final VpnStateInfo vpn;
  final TrafficInfo traffic;

  /// Server id -> latency ms (-1 = unreachable). Missing = not measured.
  final Map<String, int> latency;
  final bool testing;

  /// Subscription ids currently refreshing.
  final Set<String> refreshing;

  /// Server id (or [autoLatencyKey]) -> user-facing reason of the last failed check.
  final Map<String, String> failures;
  final UiMessage? message;

  ServerProfile? get selected {
    for (final s in servers) {
      if (s.id == selectedId) return s;
    }
    return null;
  }

  bool get isAuto => selected == null;

  AppState copyWith({
    bool? loaded,
    List<ServerProfile>? servers,
    List<Subscription>? subscriptions,
    String? selectedId,
    bool clearSelected = false,
    AppSettings? settings,
    VpnStateInfo? vpn,
    TrafficInfo? traffic,
    Map<String, int>? latency,
    bool? testing,
    Set<String>? refreshing,
    Map<String, String>? failures,
    UiMessage? message,
  }) =>
      AppState(
        loaded: loaded ?? this.loaded,
        servers: servers ?? this.servers,
        subscriptions: subscriptions ?? this.subscriptions,
        selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
        settings: settings ?? this.settings,
        vpn: vpn ?? this.vpn,
        traffic: traffic ?? this.traffic,
        latency: latency ?? this.latency,
        testing: testing ?? this.testing,
        refreshing: refreshing ?? this.refreshing,
        failures: failures ?? this.failures,
        message: message ?? this.message,
      );
}

final storageProvider = Provider<AppStorage>((ref) => SecureAppStorage());
final vpnPlatformProvider = Provider<VpnPlatform>((ref) => VpnPlatform());
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) => SubscriptionService());

/// Loads the CIDR list routed directly in "Russian sites direct" mode.
final ruIpsLoaderProvider = Provider<Future<List<String>> Function()>((ref) => () async {
      final text = await rootBundle.loadString('assets/routing/ru_ipv4.txt');
      return [
        for (final l in const LineSplitter().convert(text))
          if (l.trim().isNotEmpty && !l.startsWith('#')) l.trim(),
      ];
    });

final appControllerProvider = NotifierProvider<AppController, AppState>(AppController.new);

class AppController extends Notifier<AppState> {
  static const subscriptionRefreshInterval = Duration(hours: 24);

  StreamSubscription<VpnStateInfo>? _vpnSub;
  Timer? _trafficTimer;
  Timer? _refreshTimer;
  XrayConfig? _activeConfig;
  List<String>? _ruIps;

  AppStorage get _storage => ref.read(storageProvider);
  VpnPlatform get _vpn => ref.read(vpnPlatformProvider);
  SubscriptionService get _subs => ref.read(subscriptionServiceProvider);

  @override
  AppState build() {
    ref.onDispose(() {
      _vpnSub?.cancel();
      _trafficTimer?.cancel();
      _refreshTimer?.cancel();
    });
    return const AppState();
  }

  Future<void> init() async {
    appLog('app', 'запуск');
    final servers = await _storage.loadServers();
    final subs = await _storage.loadSubscriptions();
    final selected = await _storage.loadSelectedId();
    final settings = await _storage.loadSettings();
    appLog('app', 'загружено: серверов ${servers.length}, подписок ${subs.length}, '
        'маршрутизация ${settings.routing.name}, IPv6 ${settings.ipv6}');
    state = state.copyWith(
      loaded: true,
      servers: servers,
      subscriptions: subs,
      selectedId: selected,
      clearSelected: selected == null,
      settings: settings,
    );

    try {
      _onVpnState(await _vpn.state());
      _vpnSub = _vpn.states.listen(_onVpnState);
    } catch (_) {
      // Platform without the native side (tests, unsupported OS).
    }

    if (settings.connectOnLaunch && servers.isNotEmpty && !state.vpn.isOn) {
      unawaited(connect());
    }
    unawaited(refreshStaleSubscriptions());
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) => refreshStaleSubscriptions());
  }

  void _say(String text, {bool error = false}) {
    // Messages are user-facing texts and never contain keys or URLs.
    appLog(error ? 'error' : 'info', text);
    state = state.copyWith(message: UiMessage(text, isError: error));
  }

  /// Shows a snackbar message from UI code.
  void showMessage(String text, {bool error = false}) => _say(text, error: error);

  void _onVpnState(VpnStateInfo s) {
    final prev = state.vpn.status;
    if (s.status != prev) {
      appLog('vpn', '${prev.name} → ${s.status.name}${s.serverName != null ? ' (${s.serverName})' : ''}'
          '${s.error != null ? ': ${s.error}' : ''}');
    }
    state = state.copyWith(vpn: s, traffic: s.status == VpnStatus.connected ? null : TrafficInfo.zero);
    if (s.status == VpnStatus.connected && prev != VpnStatus.connected) {
      unawaited(checkActiveServer());
    }
    if (s.status == VpnStatus.connected) {
      _trafficTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _pollTraffic());
    } else {
      _trafficTimer?.cancel();
      _trafficTimer = null;
    }
    if (s.status == VpnStatus.error && prev != VpnStatus.error && s.error != null) {
      _say(s.error!, error: true);
    }
  }

  Future<void> _pollTraffic() async {
    try {
      state = state.copyWith(traffic: await _vpn.traffic());
    } catch (_) {}
  }

  // ---------------------------------------------------------------- import

  /// Imports whatever the user pasted/scanned/opened: a subscription URL,
  /// one or many share links, base64 or Clash YAML.
  Future<ImportResult> importText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return const ImportResult(errors: ['Буфер обмена пуст']);

    final deep = _unwrapDeepLink(t);
    if (deep != null) return importText(deep);

    final firstLine = t.split(RegExp(r'\s+')).first;
    if (SubscriptionService.isSubscriptionUrl(firstLine) && !t.contains('://', firstLine.length)) {
      return addSubscription(firstLine);
    }
    final batch = parseBatch(t);
    return _addManual(batch);
  }

  /// tunnely://import?url=<sub>  |  tunnely://add/<link>  |  tunnely://import/<sub>
  String? _unwrapDeepLink(String t) {
    if (!t.toLowerCase().startsWith('tunnely://')) return null;
    final uri = Uri.tryParse(t);
    if (uri == null) return null;
    final q = uri.queryParameters['url'];
    if (q != null && q.isNotEmpty) return q;
    final rest = t.substring('tunnely://'.length);
    for (final prefix in ['import/', 'add/']) {
      if (rest.startsWith(prefix)) return Uri.decodeComponent(rest.substring(prefix.length));
    }
    return null;
  }

  Future<ImportResult> _addManual(ParsedBatch batch) async {
    final existing = {for (final s in state.servers) s.dedupKey};
    final added = <ServerProfile>[];
    var dup = 0;
    for (final p in batch.proxies) {
      final key = ServerProfile.dedupKeyOf(p);
      if (!existing.add(key)) {
        dup++;
        continue;
      }
      added.add(ServerProfile(id: stableId(key), proxy: p));
    }
    if (added.isNotEmpty) {
      final servers = [...state.servers, ...added];
      state = state.copyWith(servers: servers, selectedId: state.selectedId ?? (state.servers.isEmpty ? added.first.id : null));
      await _storage.saveServers(servers);
      await _storage.saveSelectedId(state.selectedId);
    }
    final r = ImportResult(added: added.length, duplicates: dup, errors: batch.errors);
    _reportImport(r);
    return r;
  }

  void _reportImport(ImportResult r) {
    appLog('import', 'добавлено ${r.added}, дубликатов ${r.duplicates}, ошибок ${r.errors.length}'
        '${r.subscription != null ? ', подписка «${r.subscription!.name}»' : ''}'
        '${r.errors.isNotEmpty ? ': ${r.errors.take(3).join('; ')}' : ''}');
    if (r.subscription != null) {
      _say('Подписка «${r.subscription!.name}» добавлена');
    } else if (r.added > 0) {
      _say(r.added == 1 ? 'Сервер добавлен' : 'Добавлено серверов: ${r.added}');
    } else if (r.duplicates > 0) {
      _say('Этот сервер уже добавлен');
    } else {
      _say(r.errors.isNotEmpty ? r.errors.first : 'Не удалось распознать ключ', error: true);
    }
  }

  Future<ImportResult> addSubscription(String url) async {
    final existing = state.subscriptions.where((s) => s.url == url.trim()).firstOrNull;
    if (existing != null) {
      await refreshSubscription(existing.id);
      return ImportResult(subscription: existing);
    }
    final FetchedSubscription fetched;
    try {
      fetched = await _subs.fetch(url);
    } on ImportException catch (e) {
      final r = ImportResult(errors: [e.message]);
      _reportImport(r);
      return r;
    }
    if (fetched.batch.proxies.isEmpty) {
      final r = ImportResult(errors: fetched.batch.errors);
      _reportImport(r);
      return r;
    }
    final uri = Uri.parse(url.trim());
    final sub = Subscription(
      id: stableId('sub|${url.trim()}'),
      url: url.trim(),
      name: fetched.meta.title ?? uri.host,
      updatedAt: DateTime.now(),
      upload: fetched.meta.upload,
      download: fetched.meta.download,
      total: fetched.meta.total,
      expire: fetched.meta.expire,
    );
    final subs = [...state.subscriptions, sub];
    final servers = _mergeSubscriptionServers(sub.id, fetched.batch.proxies);
    state = state.copyWith(subscriptions: subs, servers: servers);
    await _storage.saveSubscriptions(subs);
    await _storage.saveServers(servers);
    final r = ImportResult(subscription: sub, added: servers.where((s) => s.subscriptionId == sub.id).length);
    _reportImport(r);
    return r;
  }

  /// Replaces the servers of [subId] with [proxies], keeping ids stable and
  /// skipping entries that already exist elsewhere.
  List<ServerProfile> _mergeSubscriptionServers(String subId, List<Map<String, dynamic>> proxies) {
    final others = state.servers.where((s) => s.subscriptionId != subId).toList();
    final seen = {for (final s in others) s.dedupKey};
    final fresh = <ServerProfile>[];
    for (final p in proxies) {
      final key = ServerProfile.dedupKeyOf(p);
      if (!seen.add(key)) continue;
      fresh.add(ServerProfile(id: stableId(key), proxy: p, subscriptionId: subId));
    }
    // Subscription servers first (in provider order), then manual keys.
    final insertAt = others.indexWhere((s) => s.subscriptionId == null);
    if (insertAt < 0) return [...others, ...fresh];
    return [...others.sublist(0, insertAt), ...fresh, ...others.sublist(insertAt)];
  }

  Future<void> refreshSubscription(String id, {bool quiet = false}) async {
    final sub = state.subscriptions.where((s) => s.id == id).firstOrNull;
    if (sub == null || state.refreshing.contains(id)) return;
    state = state.copyWith(refreshing: {...state.refreshing, id});
    Subscription updated;
    try {
      final fetched = await _subs.fetch(sub.url);
      if (fetched.batch.proxies.isEmpty) {
        throw ImportException(
          fetched.batch.errors.isNotEmpty ? fetched.batch.errors.first : 'В подписке нет серверов',
        );
      }
      updated = sub.copyWith(
        name: fetched.meta.title,
        updatedAt: DateTime.now(),
        clearError: true,
        upload: fetched.meta.upload,
        download: fetched.meta.download,
        total: fetched.meta.total,
        expire: fetched.meta.expire,
      );
      final servers = _mergeSubscriptionServers(id, fetched.batch.proxies);
      final keepSelected = state.selectedId == null || servers.any((s) => s.id == state.selectedId);
      state = state.copyWith(servers: servers, clearSelected: !keepSelected);
      await _storage.saveServers(servers);
      if (!keepSelected) await _storage.saveSelectedId(null);
      appLog('subscription', '«${updated.name}» обновлена: серверов '
          '${servers.where((s) => s.subscriptionId == id).length}');
      if (!quiet) _say('Подписка «${updated.name}» обновлена');
    } on ImportException catch (e) {
      updated = sub.copyWith(lastError: e.message);
      appLog('subscription', '«${sub.name}» не обновлена: ${e.message}');
      if (!quiet) _say(e.message, error: true);
    }
    final subs = [for (final s in state.subscriptions) s.id == id ? updated : s];
    state = state.copyWith(subscriptions: subs, refreshing: {...state.refreshing}..remove(id));
    await _storage.saveSubscriptions(subs);
  }

  Future<void> refreshAllSubscriptions() async {
    await Future.wait(state.subscriptions.map((s) => refreshSubscription(s.id)));
  }

  Future<void> refreshStaleSubscriptions() async {
    final now = DateTime.now();
    for (final s in state.subscriptions) {
      final at = s.updatedAt;
      if (at == null || now.difference(at) >= subscriptionRefreshInterval) {
        await refreshSubscription(s.id, quiet: true);
      }
    }
  }

  Future<void> removeSubscription(String id) async {
    final subs = state.subscriptions.where((s) => s.id != id).toList();
    final servers = state.servers.where((s) => s.subscriptionId != id).toList();
    final keepSelected = servers.any((s) => s.id == state.selectedId);
    state = state.copyWith(subscriptions: subs, servers: servers, clearSelected: !keepSelected);
    await _storage.saveSubscriptions(subs);
    await _storage.saveServers(servers);
    if (!keepSelected) await _storage.saveSelectedId(null);
  }

  Future<void> removeServer(String id) async {
    final servers = state.servers.where((s) => s.id != id).toList();
    final clear = state.selectedId == id;
    state = state.copyWith(servers: servers, clearSelected: clear);
    await _storage.saveServers(servers);
    if (clear) await _storage.saveSelectedId(null);
  }

  Future<void> renameServer(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final servers = [
      for (final s in state.servers) s.id == id ? s.copyWith(proxy: {...s.proxy, 'name': n}) : s,
    ];
    state = state.copyWith(servers: servers);
    await _storage.saveServers(servers);
  }

  // ---------------------------------------------------------------- selection & connection

  /// Selects a server (null = automatic). Reconnects when the tunnel is up.
  Future<void> select(String? id) async {
    state = state.copyWith(selectedId: id, clearSelected: id == null);
    await _storage.saveSelectedId(id);
    if (state.vpn.isOn) await connect();
  }

  Future<List<String>> _loadRuIps() async {
    if (_ruIps != null) return _ruIps!;
    try {
      _ruIps = await ref.read(ruIpsLoaderProvider)();
    } catch (_) {
      _ruIps = const [];
    }
    return _ruIps!;
  }

  void _recordResult(String key, DelayResult r) {
    final who = key == autoLatencyKey
        ? 'Авто'
        : (state.servers.where((s) => s.id == key).firstOrNull?.name ?? key);
    appLog('check', r.ok ? '$who: ${r.ms} мс' : '$who: ошибка: ${r.error ?? '-'}');
    final failures = Map<String, String>.of(state.failures);
    if (r.ok) {
      failures.remove(key);
    } else {
      failures[key] = describeFailure(r.error);
    }
    state = state.copyWith(latency: {...state.latency, key: r.ms}, failures: failures);
  }

  /// Measures servers with a real handshake: through the running tunnel when
  /// connected, otherwise through a temporary core. Returns id -> result.
  Future<Map<String, DelayResult>> _probe(List<ServerProfile> servers, {int timeoutMs = 5000}) async {
    final connected = state.vpn.status == VpnStatus.connected && _activeConfig != null;
    final probeConfig = connected ? null : buildProbeConfig(servers);
    final out = <String, DelayResult>{};
    await Future.wait([
      for (final s in servers)
        () async {
          final r = await _vpn.delay(outboundTagFor(s), latencyTestUrl,
              timeoutMs: timeoutMs, probeConfig: probeConfig);
          out[s.id] = r;
          _recordResult(s.id, r);
        }(),
    ]);
    return out;
  }

  /// Checks the active server through the running core. The tunnel can be up
  /// while the server rejects us (wrong keys, expired subscription), so tell
  /// the user why.
  Future<void> checkActiveServer() async {
    if (_activeConfig == null || state.vpn.status != VpnStatus.connected) return;
    final id = state.selectedId;
    final targets = id == null ? state.servers : state.servers.where((s) => s.id == id).toList();
    if (targets.isEmpty) return;
    final results = await _probe(targets, timeoutMs: 6000);
    if (state.vpn.status != VpnStatus.connected || state.selectedId != id) return;
    final alive = results.values.where((r) => r.ok).toList();
    if (id == null) {
      final best = alive.isEmpty ? -1 : alive.map((r) => r.ms).reduce((a, b) => a < b ? a : b);
      _recordResult(autoLatencyKey,
          DelayResult(best, alive.isEmpty ? results.values.firstOrNull?.error : null));
    }
    if (alive.isNotEmpty) return;
    final reason = describeFailure(results.values.firstOrNull?.error);
    _say(
      id == null
          ? 'Ни один сервер не отвечает: $reason'
          : 'Сервер «${state.selected?.name ?? ''}» не отвечает: $reason. Выберите другой сервер или «Авто»',
      error: true,
    );
    await _recheckSubscriptionsAfterFailure();
  }

  /// When servers reject us, the subscription may have been revoked: refresh
  /// it and say so plainly if the panel no longer knows it.
  Future<void> _recheckSubscriptionsAfterFailure() async {
    for (final sub in state.subscriptions) {
      await refreshSubscription(sub.id, quiet: true);
      final updated = state.subscriptions.where((s) => s.id == sub.id).firstOrNull;
      final err = updated?.lastError;
      if (err != null && (err.contains('404') || err.contains('403') || err.contains('401'))) {
        _say('Подписка «${sub.name}» больше не действует. Получите новую ссылку у провайдера', error: true);
        return;
      }
    }
  }

  Future<void> toggle() async {
    if (state.vpn.isOn) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    if (state.servers.isEmpty) {
      _say('Сначала добавьте ключ или подписку', error: true);
      return;
    }
    final bool granted;
    try {
      granted = await _vpn.prepare();
    } catch (_) {
      _say('VPN недоступен на этом устройстве', error: true);
      return;
    }
    if (!granted) {
      _say('Чтобы подключиться, разрешите Tunnely создать VPN', error: true);
      return;
    }

    // "Auto": find the fastest live server first so the tunnel starts on it.
    String? preferred;
    if (state.selectedId == null && state.vpn.status != VpnStatus.connected) {
      final results = await _probe(state.servers, timeoutMs: 4000);
      final alive = results.entries.where((e) => e.value.ok).toList()
        ..sort((a, b) => a.value.ms.compareTo(b.value.ms));
      preferred = alive.isEmpty ? null : alive.first.key;
    }

    final XrayConfig cfg;
    try {
      cfg = buildXrayConfig(
        servers: state.servers,
        selected: state.selectedId,
        routing: state.settings.routing,
        ipv6: state.settings.ipv6,
        ruIps: state.settings.routing == RoutingMode.ruDirect ? await _loadRuIps() : const [],
        preferredAuto: preferred,
        logLevel: state.settings.verboseLogs ? 'info' : 'warning',
      );
    } on ArgumentError {
      _say('Ни один из ваших серверов не поддерживается приложением', error: true);
      return;
    }
    final problem = await _vpn.validate(cfg.json);
    if (problem != null) {
      _say('Ошибка в настройках сервера: $problem', error: true);
      return;
    }
    _activeConfig = cfg;
    appLog('connect', 'старт: ${state.selected?.name ?? 'Авто'}, серверов в конфиге ${cfg.outboundTags.length}'
        '${cfg.unsupported.isNotEmpty ? ', не поддерживаются: ${cfg.unsupported.length}' : ''}'
        '${preferred != null ? ', лучший по проверке: ${state.servers.firstWhere((s) => s.id == preferred).name}' : ''}');
    final preferredName = preferred == null ? null : state.servers.firstWhere((s) => s.id == preferred).name;
    final name = state.selected?.name ?? (preferredName != null ? 'Авто: $preferredName' : 'Авто: самый быстрый');
    await _vpn.start(config: cfg.json, serverName: name);
  }

  Future<void> disconnect() {
    appLog('connect', 'отключение по запросу пользователя');
    return _vpn.stop();
  }

  // ---------------------------------------------------------------- latency

  Future<void> testLatency() async {
    if (state.testing || state.servers.isEmpty) return;
    state = state.copyWith(testing: true);
    try {
      await _probe(state.servers);
    } finally {
      state = state.copyWith(testing: false);
    }
  }

  /// Report for support: versions, modes and per-server check results.
  /// Contains no keys, passwords or subscription URLs.
  Future<String> diagnosticsReport() async {
    final b = StringBuffer()
      ..writeln('Tunnely — диагностика')
      ..writeln('Ядро: Xray ${await _safe(_vpn.coreVersion)}')
      ..writeln('VPN: ${state.vpn.status.name}${state.vpn.error != null ? ' (${state.vpn.error})' : ''}')
      ..writeln('Маршрутизация: ${state.settings.routing.name}, IPv6: ${state.settings.ipv6}')
      ..writeln('Подписок: ${state.subscriptions.length}, серверов: ${state.servers.length}');
    for (final sub in state.subscriptions) {
      b.writeln('Подписка «${sub.name}»: ${sub.lastError ?? 'обновлена ${sub.updatedAt?.toIso8601String() ?? '-'}'}');
    }
    b.writeln('--- Проверка серверов');
    await _probe(state.servers, timeoutMs: 6000);
    for (final s in state.servers) {
      final ms = state.latency[s.id];
      b.writeln('${s.name} [${s.protocolLabel}]: '
          '${ms != null && ms >= 0 ? '$ms мс' : (state.failures[s.id] ?? 'нет данных')}');
    }
    b.write(await fullLog(tailLines: 60));
    return b.toString();
  }

  /// All logs (app, VPN service, Xray core), newest lines last.
  Future<String> fullLog({int tailLines = 400}) async {
    String tail(String s) {
      final l = s.trim().isEmpty ? <String>[] : s.trim().split('\n');
      return l.sublist(l.length > tailLines ? l.length - tailLines : 0).join('\n');
    }

    NativeLogs native = const NativeLogs('', '');
    try {
      native = await _vpn.logs();
    } catch (_) {}
    return '--- Приложение\n${tail(await AppLog.instance.read())}\n'
        '--- VPN-служба\n${tail(native.events)}\n'
        '--- Ядро Xray\n${tail(native.core)}\n';
  }

  Future<void> clearLogs() async {
    await AppLog.instance.clear();
    try {
      await _vpn.clearLogs();
    } catch (_) {}
    appLog('app', 'журнал очищен');
  }

  Future<String> _safe(Future<String> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return '?';
    }
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings(AppSettings s) async {
    appLog('settings', 'маршрутизация ${s.routing.name}, IPv6 ${s.ipv6}, подробный журнал ${s.verboseLogs}, '
        'автоподключение ${s.connectOnLaunch}');
    final reconnect = state.vpn.status == VpnStatus.connected &&
        (s.routing != state.settings.routing ||
            s.ipv6 != state.settings.ipv6 ||
            s.verboseLogs != state.settings.verboseLogs);
    state = state.copyWith(settings: s);
    await _storage.saveSettings(s);
    if (reconnect) await connect();
  }
}

/// Key in [AppState.latency] for the automatic group.
const autoLatencyKey = '';

/// Turns a core error into a short Russian explanation for users.
String describeFailure(String? error) {
  final e = (error ?? '').toLowerCase();
  if (e.isEmpty) return 'нет ответа';
  if (e.contains('reality') || e.contains('x509') || e.contains('certificate') || e.contains('tls:')) {
    return 'сервер отклонил защищённое подключение';
  }
  if (e.contains('no such host') || e.contains('lookup') || e.contains('dns')) {
    return 'не удаётся найти адрес сервера';
  }
  if (e.contains('refused')) return 'сервер отказал в подключении';
  if (e.contains('unreachable') || e.contains('no route')) return 'сервер недоступен из этой сети';
  if (e.contains('eof') || e.contains('reset') || e.contains('closed') || e.contains('read response')) {
    return 'ключ не принят сервером (подписка могла истечь)';
  }
  if (e.contains('timeout') || e.contains('deadline')) return 'сервер не отвечает (тайм-аут)';
  return error!.length > 80 ? '${error.substring(0, 80)}…' : error;
}


/// Deterministic short id (FNV-1a 64-bit, hex) so servers keep their ids
/// across subscription refreshes.
String stableId(String key) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(key)) {
    h ^= b;
    h *= 0x100000001b3; // wraps at 64 bits on the Dart VM

  }
  // Dart ints are signed: print the two 32-bit halves to get 16 hex digits.
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return half(h >> 32) + half(h);
}
