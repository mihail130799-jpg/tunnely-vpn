import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/link_parser.dart';
import '../core/mihomo_config.dart';
import '../core/subscription_parser.dart';
import '../models/app_settings.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';
import '../services/latency_service.dart';
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
        message: message ?? this.message,
      );
}

final storageProvider = Provider<AppStorage>((ref) => SecureAppStorage());
final vpnPlatformProvider = Provider<VpnPlatform>((ref) => VpnPlatform());
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) => SubscriptionService());

/// TCP ping used for latency while disconnected; overridable in tests.
final tcpPingProvider = Provider<Future<int> Function(String, int)>((ref) => tcpPing);

final appControllerProvider = NotifierProvider<AppController, AppState>(AppController.new);

class AppController extends Notifier<AppState> {
  static const subscriptionRefreshInterval = Duration(hours: 24);

  StreamSubscription<VpnStateInfo>? _vpnSub;
  Timer? _trafficTimer;
  Timer? _refreshTimer;
  MihomoConfig? _activeConfig;

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
    final servers = await _storage.loadServers();
    final subs = await _storage.loadSubscriptions();
    final selected = await _storage.loadSelectedId();
    final settings = await _storage.loadSettings();
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
    if (kDebugMode) debugPrint('[tunnely] ${error ? 'error' : 'info'}: $text');
    state = state.copyWith(message: UiMessage(text, isError: error));
  }

  /// Shows a snackbar message from UI code.
  void showMessage(String text, {bool error = false}) => _say(text, error: error);

  void _onVpnState(VpnStateInfo s) {
    final prev = state.vpn.status;
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
      if (!quiet) _say('Подписка «${updated.name}» обновлена');
    } on ImportException catch (e) {
      updated = sub.copyWith(lastError: e.message);
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

  /// Selects a server (null = automatic). Applies instantly when connected.
  Future<void> select(String? id) async {
    state = state.copyWith(selectedId: id, clearSelected: id == null);
    await _storage.saveSelectedId(id);
    if (state.vpn.status == VpnStatus.connected) {
      final cfg = _activeConfig;
      final name = id == null ? autoGroup : cfg?.proxyNames[id];
      final switched = name != null && await _vpn.select(selectorGroup, name);
      if (!switched) {
        await connect(); // server not in the running config: reapply
      } else {
        await checkActiveServer();
      }
    }
  }

  /// Measures the active server through the running core. The tunnel can be up
  /// while the server rejects us (wrong keys, server down), so tell the user.
  Future<void> checkActiveServer() async {
    final cfg = _activeConfig;
    if (cfg == null || state.vpn.status != VpnStatus.connected) return;
    final id = state.selectedId;
    final name = id == null ? autoGroup : cfg.proxyNames[id];
    if (name == null) return;
    final ms = await _vpn.delay(name, latencyTestUrl, timeoutMs: 6000);
    if (id != null) state = state.copyWith(latency: {...state.latency, id: ms});
    if (ms < 0 && state.vpn.status == VpnStatus.connected && state.selectedId == id) {
      final who = id == null ? 'Ни один сервер' : 'Сервер «${state.selected?.name ?? ''}»';
      _say(
        id == null
            ? '$who не отвечает. Проверьте подписку или интернет'
            : '$who не отвечает. Выберите другой сервер или «Авто»',
        error: true,
      );
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
    final cfg = buildMihomoConfig(
      servers: state.servers,
      selected: state.selectedId,
      tunFd: 0,
      routing: state.settings.routing,
      ipv6: state.settings.ipv6,
    );
    final problem = await _vpn.validate(cfg.json);
    if (problem != null) {
      _say('Ошибка в настройках сервера: $problem', error: true);
      return;
    }
    _activeConfig = cfg;
    final name = state.selected?.name ?? 'Авто: самый быстрый';
    await _vpn.start(config: cfg.json, serverName: name);
  }

  Future<void> disconnect() => _vpn.stop();

  // ---------------------------------------------------------------- latency

  Future<void> testLatency() async {
    if (state.testing || state.servers.isEmpty) return;
    state = state.copyWith(testing: true);
    final connected = state.vpn.status == VpnStatus.connected;
    final names = _activeConfig?.proxyNames ?? const {};
    final ping = ref.read(tcpPingProvider);
    final results = Map<String, int>.of(state.latency);
    final queue = List.of(state.servers);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeLast();
        final name = names[s.id];
        final ms = connected && name != null
            ? await _vpn.delay(name, latencyTestUrl)
            : await ping(s.server, s.port);
        results[s.id] = ms;
        state = state.copyWith(latency: Map.of(results));
      }
    }

    await Future.wait(List.generate(8, (_) => worker()));
    state = state.copyWith(testing: false);
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings(AppSettings s) async {
    final reconnect = state.vpn.status == VpnStatus.connected &&
        (s.routing != state.settings.routing || s.ipv6 != state.settings.ipv6);
    state = state.copyWith(settings: s);
    await _storage.saveSettings(s);
    if (reconnect) await connect();
  }
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
