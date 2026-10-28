import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_log.dart';
import '../services/update_service.dart';
import 'app_controller.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, error }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.current = '',
    this.info,
    this.progress = 0,
    this.error,
    this.lastCheck,
    this.downloaded = false,
  });

  final UpdateStatus status;

  /// Installed version, e.g. "0.3.0".
  final String current;
  final UpdateInfo? info;

  /// Download progress 0..1.
  final double progress;
  final String? error;
  final DateTime? lastCheck;

  /// The verified APK is already on the device; only installation is left.
  final bool downloaded;

  bool get hasUpdate => info != null;
  bool get busy =>
      status == UpdateStatus.checking || status == UpdateStatus.downloading || status == UpdateStatus.installing;

  UpdateState copyWith({
    UpdateStatus? status,
    String? current,
    UpdateInfo? info,
    bool clearInfo = false,
    double? progress,
    String? error,
    DateTime? lastCheck,
    bool? downloaded,
  }) =>
      UpdateState(
        status: status ?? this.status,
        current: current ?? this.current,
        info: clearInfo ? null : info ?? this.info,
        progress: progress ?? this.progress,
        error: error,
        lastCheck: lastCheck ?? this.lastCheck,
        downloaded: downloaded ?? this.downloaded,
      );
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// Directory the APK is downloaded to; must match res/xml/file_paths.xml (cache/updates).
final updateDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async => Directory('${(await getTemporaryDirectory()).path}/updates'),
);

final updateControllerProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Checks GitHub Releases once a day and on demand; downloads, verifies and
/// hands the APK to the system installer (the user always confirms there).
class UpdateController extends Notifier<UpdateState> {
  static const checkEvery = Duration(hours: 24);
  static const _kLastCheck = 'update_last_check';

  String _abi = '';

  /// Verified APK from an earlier attempt (e.g. before the install permission was granted).
  File? _downloaded;

  @override
  UpdateState build() {
    Future.microtask(_init);
    return const UpdateState();
  }

  Future<void> _init() async {
    try {
      final info = await ref.read(vpnPlatformProvider).appInfo();
      if (!ref.mounted) return;
      _abi = info.abi;
      state = state.copyWith(current: info.version);
    } catch (e) {
      appLog('update', 'app info unavailable: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastCheck);
    final last = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    if (!ref.mounted) return;
    state = state.copyWith(lastCheck: last);
    if (last == null || DateTime.now().difference(last) >= checkEvery) await check(silent: true);
  }

  /// [silent]: background check — errors are logged, not shown.
  Future<void> check({bool silent = false}) async {
    if (state.busy || state.current.isEmpty) return;
    state = state.copyWith(status: UpdateStatus.checking);
    try {
      final info = await ref.read(updateServiceProvider).check(current: state.current, abi: _abi);
      final now = DateTime.now();
      (await SharedPreferences.getInstance()).setInt(_kLastCheck, now.millisecondsSinceEpoch);
      if (!ref.mounted) return;
      appLog('update', info == null ? 'up to date (${state.current})' : 'available ${info.version} (${info.apkName})');
      state = state.copyWith(
        status: info == null ? UpdateStatus.upToDate : UpdateStatus.available,
        info: info,
        clearInfo: info == null,
        lastCheck: now,
        downloaded: info != null && state.downloaded && info.version == state.info?.version,
      );
    } catch (e) {
      appLog('update', 'check failed: $e');
      if (!ref.mounted) return;
      state = state.copyWith(
        status: state.hasUpdate ? UpdateStatus.available : (silent ? UpdateStatus.idle : UpdateStatus.error),
        error: silent ? null : '$e',
      );
    }
  }

  /// Downloads (with SHA-256 check) and opens the system installer.
  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null || state.busy) return;
    final ready = _downloaded;
    if (ready != null && ready.path.endsWith(info.apkName) && await ready.exists()) return install(ready.path);
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      final dir = await ref.read(updateDirProvider)();
      // Old downloads are not needed any more.
      if (await dir.exists()) await dir.delete(recursive: true);
      final file = await ref.read(updateServiceProvider).download(
            info,
            dir,
            onProgress: (p) => state = state.copyWith(status: UpdateStatus.downloading, progress: p),
          );
      _downloaded = file;
      state = state.copyWith(downloaded: true);
      appLog('update', 'downloaded ${info.apkName}, sha256 ok');
      await install(file.path);
    } catch (e) {
      appLog('update', 'download failed: $e');
      state = state.copyWith(status: UpdateStatus.available, error: '$e');
    }
  }

  Future<void> install(String path) async {
    state = state.copyWith(status: UpdateStatus.installing, progress: 1);
    try {
      final started = await ref.read(vpnPlatformProvider).installApk(path);
      state = state.copyWith(
        status: UpdateStatus.available,
        error: started ? null : 'Разрешите установку из Tunnely, вернитесь и нажмите «Установить»',
      );
    } catch (e) {
      appLog('update', 'install failed: $e');
      state = state.copyWith(status: UpdateStatus.available, error: 'Не удалось открыть установщик');
    }
  }
}
