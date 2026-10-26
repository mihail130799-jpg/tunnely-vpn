import 'dart:convert';

/// Error with a message safe to show to end users (never contains secrets).
class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

const supportedSchemes = ['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic'];

/// Parses a single share link into a Mihomo proxy map.
///
/// Supported: vless://, vmess://, trojan://, ss://, hysteria2:// (hy2://), tuic://.
Map<String, dynamic> parseLink(String raw) {
  final link = raw.trim();
  final schemeEnd = link.indexOf('://');
  if (schemeEnd <= 0) throw ImportException('Это не похоже на ключ VPN');
  final scheme = link.substring(0, schemeEnd).toLowerCase();
  return switch (scheme) {
    'vless' => _parseVless(link),
    'trojan' => _parseTrojan(link),
    'ss' => _parseShadowsocks(link),
    'vmess' => _parseVmess(link),
    'hysteria2' || 'hy2' => _parseHysteria2(link),
    'tuic' => _parseTuic(link),
    _ => throw ImportException('Протокол «$scheme» не поддерживается'),
  };
}

/// True if [line] starts with a supported scheme.
bool looksLikeLink(String line) {
  final i = line.indexOf('://');
  return i > 0 && supportedSchemes.contains(line.substring(0, i).toLowerCase());
}

Uri _uri(String link) {
  try {
    return Uri.parse(link);
  } on FormatException {
    throw ImportException('Ключ повреждён: не удалось разобрать адрес');
  }
}

String _name(Uri u, String fallback) {
  if (u.fragment.isEmpty) return fallback;
  try {
    return Uri.decodeComponent(u.fragment).trim();
  } catch (_) {
    return u.fragment.trim();
  }
}

String _host(Uri u) {
  final h = u.host;
  if (h.isEmpty) throw ImportException('В ключе не указан адрес сервера');
  return h;
}

int _port(Uri u) {
  if (!u.hasPort || u.port <= 0 || u.port > 65535) {
    throw ImportException('В ключе не указан или неверен порт сервера');
  }
  return u.port;
}

String _user(Uri u, String what) {
  final s = Uri.decodeComponent(u.userInfo);
  if (s.isEmpty) throw ImportException('В ключе нет $what');
  return s;
}

List<String>? _alpn(String? v) {
  if (v == null || v.isEmpty) return null;
  return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

bool _truthy(String? v) => v == '1' || v == 'true';

/// Applies transport (`type=`) and TLS/Reality (`security=`) query params
/// shared by vless:// and trojan:// links.
void _applyStreamParams(Map<String, dynamic> p, Map<String, String> q, {required bool defaultTls}) {
  final network = (q['type'] ?? 'tcp').toLowerCase();
  final host = q['host'];
  final path = q['path'];

  switch (network) {
    case 'tcp':
    case 'raw':
      if (q['headerType'] == 'http') {
        p['network'] = 'http';
        p['http-opts'] = {
          if (path != null) 'path': path.split(','),
          if (host != null) 'headers': {'Host': host.split(',')},
        };
      }
    case 'ws':
      p['network'] = 'ws';
      p['ws-opts'] = {
        'path': path ?? '/',
        if (host != null && host.isNotEmpty) 'headers': {'Host': host},
      };
    case 'grpc':
      p['network'] = 'grpc';
      p['grpc-opts'] = {'grpc-service-name': q['serviceName'] ?? ''};
    case 'http':
    case 'h2':
      p['network'] = 'h2';
      p['h2-opts'] = {
        'path': path ?? '/',
        if (host != null) 'host': host.split(','),
      };
    case 'xhttp':
    case 'splithttp':
      p['network'] = 'xhttp';
      p['xhttp-opts'] = {
        'path': path ?? '/',
        if (host != null && host.isNotEmpty) 'host': host,
        if (q['mode'] != null && q['mode']!.isNotEmpty) 'mode': q['mode'],
      };
    case 'httpupgrade':
      p['network'] = 'ws';
      p['ws-opts'] = {
        'path': path ?? '/',
        'v2ray-http-upgrade': true,
        if (host != null && host.isNotEmpty) 'headers': {'Host': host},
      };
    default:
      throw ImportException('Транспорт «$network» не поддерживается');
  }

  final security = (q['security'] ?? (defaultTls ? 'tls' : 'none')).toLowerCase();
  final sni = q['sni'] ?? q['peer'];
  final fp = q['fp'];
  final alpn = _alpn(q['alpn']);
  switch (security) {
    case 'none':
      break;
    case 'tls':
    case 'xtls':
      p['tls'] = true;
      if (sni != null && sni.isNotEmpty) p[p['type'] == 'trojan' ? 'sni' : 'servername'] = sni;
      if (fp != null && fp.isNotEmpty) p['client-fingerprint'] = fp;
      if (alpn != null) p['alpn'] = alpn;
      if (_truthy(q['allowInsecure']) || _truthy(q['insecure'])) p['skip-cert-verify'] = true;
    case 'reality':
      final pbk = q['pbk'];
      if (pbk == null || pbk.isEmpty) throw ImportException('В ключе Reality нет публичного ключа (pbk)');
      p['tls'] = true;
      if (sni != null && sni.isNotEmpty) p[p['type'] == 'trojan' ? 'sni' : 'servername'] = sni;
      p['client-fingerprint'] = (fp != null && fp.isNotEmpty) ? fp : 'chrome';
      p['reality-opts'] = {
        'public-key': pbk,
        if (q['sid'] != null && q['sid']!.isNotEmpty) 'short-id': q['sid'],
      };
      if (alpn != null) p['alpn'] = alpn;
    default:
      throw ImportException('Тип шифрования «$security» не поддерживается');
  }
}

Map<String, dynamic> _parseVless(String link) {
  final u = _uri(link);
  final q = u.queryParameters;
  final server = _host(u);
  final port = _port(u);
  final p = <String, dynamic>{
    'name': _name(u, '$server:$port'),
    'type': 'vless',
    'server': server,
    'port': port,
    'uuid': _user(u, 'идентификатора пользователя (UUID)'),
    'udp': true,
  };
  final flow = q['flow'];
  if (flow != null && flow.isNotEmpty) p['flow'] = flow;
  final enc = q['encryption'];
  if (enc != null && enc.isNotEmpty && enc != 'none') p['encryption'] = enc;
  _applyStreamParams(p, q, defaultTls: false);
  return p;
}

Map<String, dynamic> _parseTrojan(String link) {
  final u = _uri(link);
  final q = u.queryParameters;
  final server = _host(u);
  final port = _port(u);
  final p = <String, dynamic>{
    'name': _name(u, '$server:$port'),
    'type': 'trojan',
    'server': server,
    'port': port,
    'password': _user(u, 'пароля'),
    'udp': true,
  };
  _applyStreamParams(p, q, defaultTls: true);
  p.remove('tls'); // trojan is always TLS in Mihomo
  return p;
}

String _b64decode(String s) {
  var t = s.trim().replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s'), '');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return utf8.decode(base64.decode(t));
}

/// Decodes standard or URL-safe base64 with or without padding; null if invalid.
String? tryBase64Decode(String s) {
  try {
    return _b64decode(s);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _parseShadowsocks(String link) {
  var body = link.substring('ss://'.length);
  var name = '';
  final hash = body.indexOf('#');
  if (hash >= 0) {
    name = Uri.decodeComponent(body.substring(hash + 1)).trim();
    body = body.substring(0, hash);
  }
  var query = '';
  final qm = body.indexOf('?');
  if (qm >= 0) {
    query = body.substring(qm + 1);
    body = body.substring(0, qm);
  }
  body = body.replaceAll(RegExp(r'/$'), '');

  String userInfo;
  String hostPort;
  final at = body.lastIndexOf('@');
  if (at >= 0) {
    // SIP002: userinfo is base64(method:password) or percent-encoded method:password.
    final enc = body.substring(0, at);
    hostPort = body.substring(at + 1);
    final decoded = Uri.decodeComponent(enc);
    userInfo = decoded.contains(':') ? decoded : (tryBase64Decode(enc) ?? '');
  } else {
    // Legacy: base64(method:password@host:port)
    final decoded = tryBase64Decode(body);
    if (decoded == null || !decoded.contains('@')) throw ImportException('Ключ Shadowsocks повреждён');
    final i = decoded.lastIndexOf('@');
    userInfo = decoded.substring(0, i);
    hostPort = decoded.substring(i + 1);
  }
  final colon = userInfo.indexOf(':');
  if (colon <= 0) throw ImportException('В ключе Shadowsocks нет метода шифрования или пароля');

  final u = _uri('ss://x@$hostPort');
  final server = _host(u);
  final port = _port(u);
  final p = <String, dynamic>{
    'name': name.isEmpty ? '$server:$port' : name,
    'type': 'ss',
    'server': server,
    'port': port,
    'cipher': userInfo.substring(0, colon),
    'password': userInfo.substring(colon + 1),
    'udp': true,
  };
  final plugin = Uri.splitQueryString(query)['plugin'];
  if (plugin != null && plugin.isNotEmpty) {
    final parts = plugin.split(';');
    final opts = <String, String>{};
    for (final kv in parts.skip(1)) {
      final i = kv.indexOf('=');
      if (i > 0) opts[kv.substring(0, i)] = kv.substring(i + 1);
    }
    if (parts.first == 'obfs-local' || parts.first == 'simple-obfs') {
      p['plugin'] = 'obfs';
      p['plugin-opts'] = {'mode': opts['obfs'] ?? 'http', if (opts['obfs-host'] != null) 'host': opts['obfs-host']};
    } else {
      throw ImportException('Плагин Shadowsocks «${parts.first}» не поддерживается');
    }
  }
  return p;
}

Map<String, dynamic> _parseVmess(String link) {
  final decoded = tryBase64Decode(link.substring('vmess://'.length));
  if (decoded == null) throw ImportException('Ключ VMess повреждён');
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    throw ImportException('Ключ VMess повреждён');
  }
  final server = '${j['add'] ?? ''}';
  final port = int.tryParse('${j['port'] ?? ''}') ?? 0;
  if (server.isEmpty) throw ImportException('В ключе не указан адрес сервера');
  if (port <= 0 || port > 65535) throw ImportException('В ключе не указан или неверен порт сервера');
  final p = <String, dynamic>{
    'name': '${j['ps'] ?? ''}'.trim().isEmpty ? '$server:$port' : '${j['ps']}'.trim(),
    'type': 'vmess',
    'server': server,
    'port': port,
    'uuid': '${j['id'] ?? ''}',
    'alterId': int.tryParse('${j['aid'] ?? 0}') ?? 0,
    'cipher': '${j['scy'] ?? ''}'.isEmpty ? 'auto' : '${j['scy']}',
    'udp': true,
  };
  if ((p['uuid'] as String).isEmpty) throw ImportException('В ключе нет идентификатора пользователя (UUID)');
  final q = <String, String>{
    'type': '${j['net'] ?? 'tcp'}',
    if ('${j['host'] ?? ''}'.isNotEmpty) 'host': '${j['host']}',
    if ('${j['path'] ?? ''}'.isNotEmpty) 'path': '${j['path']}',
    if ('${j['path'] ?? ''}'.isNotEmpty && j['net'] == 'grpc') 'serviceName': '${j['path']}',
    if (j['type'] == 'http') 'headerType': 'http',
    'security': '${j['tls'] ?? ''}'.isEmpty ? 'none' : '${j['tls']}',
    if ('${j['sni'] ?? ''}'.isNotEmpty) 'sni': '${j['sni']}',
    if ('${j['alpn'] ?? ''}'.isNotEmpty) 'alpn': '${j['alpn']}',
    if ('${j['fp'] ?? ''}'.isNotEmpty) 'fp': '${j['fp']}',
  };
  _applyStreamParams(p, q, defaultTls: false);
  return p;
}

Map<String, dynamic> _parseHysteria2(String link) {
  final u = _uri(link.replaceFirst(RegExp(r'^hy2://', caseSensitive: false), 'hysteria2://'));
  final q = u.queryParameters;
  final server = _host(u);
  // Port may be absent (default 443) or a hop range in `mport`.
  final port = u.hasPort ? u.port : 443;
  final p = <String, dynamic>{
    'name': _name(u, '$server:$port'),
    'type': 'hysteria2',
    'server': server,
    'port': port,
    'password': _user(u, 'пароля'),
    'udp': true,
  };
  if (q['sni'] != null && q['sni']!.isNotEmpty) p['sni'] = q['sni'];
  if (_truthy(q['insecure'])) p['skip-cert-verify'] = true;
  if (q['obfs'] != null && q['obfs']!.isNotEmpty && q['obfs'] != 'none') {
    p['obfs'] = q['obfs'];
    if (q['obfs-password'] != null) p['obfs-password'] = q['obfs-password'];
  }
  final ports = q['mport'] ?? q['ports'];
  if (ports != null && ports.isNotEmpty) p['ports'] = ports;
  final alpn = _alpn(q['alpn']);
  if (alpn != null) p['alpn'] = alpn;
  return p;
}

Map<String, dynamic> _parseTuic(String link) {
  final u = _uri(link);
  final q = u.queryParameters;
  final server = _host(u);
  final port = _port(u);
  final cred = _user(u, 'UUID и пароля');
  final i = cred.indexOf(':');
  if (i <= 0) throw ImportException('В ключе TUIC нет UUID или пароля');
  final p = <String, dynamic>{
    'name': _name(u, '$server:$port'),
    'type': 'tuic',
    'server': server,
    'port': port,
    'uuid': cred.substring(0, i),
    'password': cred.substring(i + 1),
    'udp': true,
  };
  if (q['sni'] != null && q['sni']!.isNotEmpty) p['sni'] = q['sni'];
  p['alpn'] = _alpn(q['alpn']) ?? ['h3'];
  if (q['congestion_control'] != null) p['congestion-controller'] = q['congestion_control'];
  if (q['udp_relay_mode'] != null) p['udp-relay-mode'] = q['udp_relay_mode'];
  if (_truthy(q['allow_insecure']) || _truthy(q['insecure'])) p['skip-cert-verify'] = true;
  if (_truthy(q['disable_sni'])) p['disable-sni'] = true;
  return p;
}
