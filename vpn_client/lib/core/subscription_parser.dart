import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'link_parser.dart';

/// Result of parsing a subscription body or a pasted blob of keys.
class ParsedBatch {
  ParsedBatch(this.proxies, this.errors);

  final List<Map<String, dynamic>> proxies;

  /// User-facing reasons for lines that could not be imported.
  final List<String> errors;
}

/// Metadata from standard subscription response headers.
class SubscriptionMeta {
  SubscriptionMeta({this.title, this.updateIntervalHours, this.upload, this.download, this.total, this.expire});

  final String? title;
  final int? updateIntervalHours;
  final int? upload;
  final int? download;
  final int? total;
  final DateTime? expire;

  /// Parses `profile-title`, `profile-update-interval`, `subscription-userinfo`.
  factory SubscriptionMeta.fromHeaders(Map<String, String> headers) {
    String? h(String k) => headers[k] ?? headers[k.toLowerCase()];

    String? title = h('profile-title');
    if (title != null && title.startsWith('base64:')) {
      title = tryBase64Decode(title.substring(7)) ?? title;
    }

    final info = <String, int>{};
    for (final part in (h('subscription-userinfo') ?? '').split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        final v = int.tryParse(kv[1].trim());
        if (v != null) info[kv[0].trim()] = v;
      }
    }
    final expire = info['expire'];
    return SubscriptionMeta(
      title: title?.trim().isEmpty ?? true ? null : title!.trim(),
      updateIntervalHours: int.tryParse(h('profile-update-interval') ?? ''),
      upload: info['upload'],
      download: info['download'],
      total: info['total'],
      expire: expire == null || expire == 0 ? null : DateTime.fromMillisecondsSinceEpoch(expire * 1000),
    );
  }
}

/// Parses any supported text: Clash/Mihomo YAML, base64 list of links,
/// or plain newline-separated links.
ParsedBatch parseBatch(String body) {
  final text = body.trim();
  if (text.isEmpty) return ParsedBatch([], ['Пустой ответ: в подписке нет серверов']);

  final yamlProxies = _tryClashYaml(text);
  if (yamlProxies != null) return yamlProxies;

  var lines = _lines(text);
  if (!lines.any(looksLikeLink)) {
    final decoded = tryBase64Decode(text);
    if (decoded != null) {
      final fromYaml = _tryClashYaml(decoded.trim());
      if (fromYaml != null) return fromYaml;
      lines = _lines(decoded);
    }
  }

  final proxies = <Map<String, dynamic>>[];
  final errors = <String>[];
  for (final line in lines) {
    if (!line.contains('://')) continue;
    try {
      proxies.add(parseLink(line));
    } on ImportException catch (e) {
      errors.add(e.message);
    }
  }
  if (proxies.isEmpty && errors.isEmpty) {
    errors.add('Не найдено ни одного ключа или сервера');
  }
  return ParsedBatch(proxies, errors);
}

List<String> _lines(String s) =>
    const LineSplitter().convert(s).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

ParsedBatch? _tryClashYaml(String text) {
  if (!text.contains('proxies')) return null;
  final Object? doc;
  try {
    doc = loadYaml(text);
  } catch (_) {
    return null;
  }
  if (doc is! YamlMap || doc['proxies'] is! YamlList) return null;
  final proxies = <Map<String, dynamic>>[];
  final errors = <String>[];
  for (final item in doc['proxies'] as YamlList) {
    if (item is! YamlMap) continue;
    final p = _plain(item) as Map<String, dynamic>;
    if (p['name'] == null || p['type'] == null || p['server'] == null || p['port'] == null) {
      errors.add('Сервер в подписке описан не полностью');
      continue;
    }
    p['port'] = int.tryParse('${p['port']}') ?? p['port'];
    proxies.add(p);
  }
  return ParsedBatch(proxies, errors);
}

Object? _plain(Object? node) {
  if (node is YamlMap) {
    return <String, dynamic>{for (final e in node.entries) '${e.key}': _plain(e.value)};
  }
  if (node is YamlList) return [for (final v in node) _plain(v)];
  return node;
}
