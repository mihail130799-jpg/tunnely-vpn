import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';

/// Everything the app persists. Implementations must be safe to call often.
abstract class AppStorage {
  Future<List<ServerProfile>> loadServers();
  Future<void> saveServers(List<ServerProfile> servers);
  Future<List<Subscription>> loadSubscriptions();
  Future<void> saveSubscriptions(List<Subscription> subs);
  Future<String?> loadSelectedId();
  Future<void> saveSelectedId(String? id);
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
}

/// Keys and subscription URLs (credentials) live in Android Keystore / iOS
/// Keychain-backed secure storage; non-secret preferences in SharedPreferences.
class SecureAppStorage implements AppStorage {
  SecureAppStorage({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const _kServers = 'servers.v1';
  static const _kSubs = 'subscriptions.v1';
  static const _kSelected = 'selected.v1';
  static const _kSettings = 'settings.v1';

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = await _secure.read(key: key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ServerProfile>> loadServers() async =>
      (await _readList(_kServers)).map(ServerProfile.fromJson).toList();

  @override
  Future<void> saveServers(List<ServerProfile> servers) =>
      _secure.write(key: _kServers, value: jsonEncode(servers.map((s) => s.toJson()).toList()));

  @override
  Future<List<Subscription>> loadSubscriptions() async =>
      (await _readList(_kSubs)).map(Subscription.fromJson).toList();

  @override
  Future<void> saveSubscriptions(List<Subscription> subs) =>
      _secure.write(key: _kSubs, value: jsonEncode(subs.map((s) => s.toJson()).toList()));

  @override
  Future<String?> loadSelectedId() async => (await SharedPreferences.getInstance()).getString(_kSelected);

  @override
  Future<void> saveSelectedId(String? id) async {
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove(_kSelected);
    } else {
      await p.setString(_kSelected, id);
    }
  }

  @override
  Future<AppSettings> loadSettings() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kSettings);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async =>
      (await SharedPreferences.getInstance()).setString(_kSettings, jsonEncode(settings.toJson()));
}

/// In-memory storage for tests and previews.
class MemoryAppStorage implements AppStorage {
  List<ServerProfile> servers = [];
  List<Subscription> subs = [];
  String? selected;
  AppSettings settings = const AppSettings();

  @override
  Future<List<ServerProfile>> loadServers() async => List.of(servers);
  @override
  Future<void> saveServers(List<ServerProfile> s) async => servers = List.of(s);
  @override
  Future<List<Subscription>> loadSubscriptions() async => List.of(subs);
  @override
  Future<void> saveSubscriptions(List<Subscription> s) async => subs = List.of(s);
  @override
  Future<String?> loadSelectedId() async => selected;
  @override
  Future<void> saveSelectedId(String? id) async => selected = id;
  @override
  Future<AppSettings> loadSettings() async => settings;
  @override
  Future<void> saveSettings(AppSettings s) async => settings = s;
}
