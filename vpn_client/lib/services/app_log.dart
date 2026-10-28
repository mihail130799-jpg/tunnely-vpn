import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent application log (app-private storage, survives restarts).
///
/// Rule: never log keys, passwords, UUIDs or subscription URLs — only server
/// names, protocols, states and error texts.
class AppLog {
  AppLog._();
  static final instance = AppLog._();

  static const _maxLines = 600;
  final _lines = <String>[];
  File? _file;
  Future<void>? _loading;
  Timer? _flush;

  Future<void> _ensureLoaded() => _loading ??= () async {
        try {
          final dir = await getApplicationSupportDirectory();
          _file = File('${dir.path}/app.log');
          if (await _file!.exists()) {
            final old = await _file!.readAsLines();
            _lines.insertAll(0, old.length > _maxLines ? old.sublist(old.length - _maxLines) : old);
          }
        } catch (_) {
          // Tests or platforms without a support directory: memory only.
        }
      }();

  /// Adds a line: "2026-10-28 10:15:02 [tag] message".
  void log(String tag, String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _lines.add('$ts [$tag] $message');
    if (_lines.length > _maxLines) _lines.removeRange(0, _lines.length - _maxLines);
    if (kDebugMode) debugPrint('[tunnely][$tag] $message');
    unawaited(_ensureLoaded());
    _flush ??= Timer(const Duration(seconds: 1), () {
      _flush = null;
      unawaited(_write());
    });
  }

  Future<void> _write() async {
    await _ensureLoaded();
    try {
      await _file?.writeAsString('${_lines.join('\n')}\n', flush: true);
    } catch (_) {}
  }

  Future<String> read() async {
    await _ensureLoaded();
    return _lines.join('\n');
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _lines.clear();
    await _write();
  }
}

/// Shorthand used across the app.
void appLog(String tag, String message) => AppLog.instance.log(tag, message);
