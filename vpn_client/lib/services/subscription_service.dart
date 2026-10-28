import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/link_parser.dart';
import '../core/subscription_parser.dart';

class FetchedSubscription {
  FetchedSubscription(this.batch, this.meta);
  final ParsedBatch batch;
  final SubscriptionMeta meta;
}

/// Downloads subscription bodies. TLS certificates are always verified.
class SubscriptionService {
  SubscriptionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Panels (Marzban, Remnawave, 3x-ui) pick the response format by User-Agent.
  /// A neutral UA gets the standard base64 list of share links (vless:// etc.),
  /// the same format Happ/v2rayNG receive. Clash YAML is still parsed if served.
  static const userAgent = 'Tunnely/0.3.0';
  static const _maxBytes = 5 * 1024 * 1024;

  static bool isSubscriptionUrl(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('https://') || t.startsWith('http://');
  }

  Future<FetchedSubscription> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      throw ImportException('Неверная ссылка на подписку');
    }
    final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: {'User-Agent': userAgent, 'Accept': '*/*'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ImportException('Сервер подписки не ответил за 20 секунд');
    } on HandshakeException {
      throw ImportException('Ошибка защищённого соединения с сервером подписки (сертификат)');
    } on SocketException {
      throw ImportException('Нет связи с сервером подписки. Проверьте интернет');
    } on http.ClientException {
      throw ImportException('Не удалось загрузить подписку');
    }
    if (resp.statusCode == 404) throw ImportException('Подписка не найдена (404). Проверьте ссылку');
    if (resp.statusCode == 403 || resp.statusCode == 401) {
      throw ImportException('Доступ к подписке запрещён (${resp.statusCode}). Возможно, она истекла');
    }
    if (resp.statusCode != 200) throw ImportException('Сервер подписки вернул ошибку ${resp.statusCode}');
    if (resp.bodyBytes.length > _maxBytes) throw ImportException('Подписка слишком большая');

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    return FetchedSubscription(parseBatch(body), SubscriptionMeta.fromHeaders(resp.headers));
  }
}
