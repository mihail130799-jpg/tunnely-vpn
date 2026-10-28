import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Where releases are published (public repo, see PRODUCT_DECISIONS №16).
const releasesRepo = 'mihail130799-jpg/tunnely-vpn';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkName,
    required this.apkUrl,
    required this.size,
    required this.sha256,
    required this.pageUrl,
  });

  final String version;
  final String notes;
  final String apkName;
  final String apkUrl;
  final int size;

  /// Expected SHA-256 of the APK (from the release's SHA256SUMS.txt).
  final String sha256;
  final String pageUrl;
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Compares dotted versions ("0.10.1" > "0.9.3"). Ignores a leading "v" and "+build".
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp('^v'), '')
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Checks GitHub Releases for a newer APK and downloads it with hash check.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'Tunnely-Updater'};

  /// Latest stable release if it is newer than [current] and has an APK for
  /// [abi]; null when up to date.
  Future<UpdateInfo?> check({required String current, required String abi}) async {
    final http.Response r;
    try {
      r = await _client
          .get(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw UpdateException('Сервер обновлений не ответил');
    } on SocketException {
      throw UpdateException('Нет связи с сервером обновлений');
    } on http.ClientException {
      throw UpdateException('Не удалось проверить обновления');
    }
    if (r.statusCode == 404) return null; // no releases yet
    if (r.statusCode != 200) throw UpdateException('Сервер обновлений вернул ошибку ${r.statusCode}');

    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['draft'] == true || j['prerelease'] == true) return null;
    final version = '${j['tag_name']}'.replaceFirst(RegExp('^v'), '');
    if (compareVersions(version, current) <= 0) return null;

    final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => '${a['name']}'.endsWith('-$abi.apk')).firstOrNull ??
        assets.where((a) => '${a['name']}'.endsWith('-arm64-v8a.apk')).firstOrNull;
    if (apk == null) throw UpdateException('В новой версии нет файла для этого телефона');
    final sums = assets.where((a) => a['name'] == 'SHA256SUMS.txt').firstOrNull;
    if (sums == null) throw UpdateException('В новой версии нет контрольных сумм');

    final sumsBody = await _client
        .get(Uri.parse('${sums['browser_download_url']}'), headers: {'User-Agent': 'Tunnely-Updater'})
        .timeout(const Duration(seconds: 20));
    final hash = parseSha256Sums(utf8.decode(sumsBody.bodyBytes, allowMalformed: true))['${apk['name']}'];
    if (hash == null) throw UpdateException('Нет контрольной суммы для ${apk['name']}');

    return UpdateInfo(
      version: version,
      notes: '${j['body'] ?? ''}',
      apkName: '${apk['name']}',
      apkUrl: '${apk['browser_download_url']}',
      size: (apk['size'] as num?)?.toInt() ?? 0,
      sha256: hash,
      pageUrl: '${j['html_url']}',
    );
  }

  /// Downloads the APK to [dir], reporting progress 0..1, and verifies SHA-256.
  Future<File> download(UpdateInfo info, Directory dir, {void Function(double)? onProgress}) async {
    await dir.create(recursive: true);
    final file = File('${dir.path}/${info.apkName}');
    final req = http.Request('GET', Uri.parse(info.apkUrl))..headers['User-Agent'] = 'Tunnely-Updater';
    final http.StreamedResponse resp;
    try {
      resp = await _client.send(req).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw UpdateException('Не удалось начать загрузку обновления');
    }
    if (resp.statusCode != 200) throw UpdateException('Загрузка обновления: ошибка ${resp.statusCode}');
    final total = resp.contentLength ?? info.size;
    final sink = file.openWrite();
    var got = 0;
    final hashSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashSink);
    try {
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
    } catch (_) {
      await sink.close();
      throw UpdateException('Загрузка прервалась, попробуйте ещё раз');
    }
    await sink.close();
    hasher.close();
    if (hashSink.value.toString() != info.sha256.toLowerCase()) {
      await file.delete();
      throw UpdateException('Файл обновления повреждён (контрольная сумма не совпала)');
    }
    return file;
  }
}

/// Parses "hash  filename" lines.
Map<String, String> parseSha256Sums(String text) => {
      for (final l in const LineSplitter().convert(text))
        if (RegExp(r'^[0-9a-fA-F]{64}\s+\S').hasMatch(l.trim()))
          l.trim().split(RegExp(r'\s+')).last.replaceFirst('*', ''): l.trim().split(RegExp(r'\s+')).first.toLowerCase(),
    };

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
