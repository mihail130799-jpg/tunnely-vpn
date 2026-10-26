# Протоколы и форматы

## Поддерживаемые ссылки
| Схема | Протокол | Параметры, которые разбираются |
|---|---|---|
| `vless://uuid@host:port?…#имя` | VLESS | `type` (tcp/raw, ws, grpc, http/h2, xhttp/splithttp, httpupgrade), `security` (none/tls/reality), `sni`, `fp`, `alpn`, `pbk`, `sid`, `flow`, `encryption` (VLESS Encryption, напр. `mlkem768x25519plus…`), `path`, `host`, `serviceName`, `mode`, `headerType`, `allowInsecure` |
| `trojan://пароль@host:port?…` | Trojan | как у VLESS (TLS по умолчанию, Reality тоже) |
| `ss://…` | Shadowsocks | SIP002 (base64 или percent-encoded `метод:пароль`, в т.ч. 2022-blake3), устаревший полностью base64 формат, плагин `obfs-local` |
| `vmess://base64(json)` | VMess | `add, port, id, aid, scy, net, type, host, path, tls, sni, alpn, fp` |
| `hysteria2://` / `hy2://` | Hysteria2 | `sni`, `insecure`, `obfs`, `obfs-password`, `mport`, `alpn`; порт по умолчанию 443 |
| `tuic://uuid:пароль@host:port` | TUIC v5 | `sni`, `alpn`, `congestion_control`, `udp_relay_mode`, `allow_insecure`, `disable_sni` |

Ошибки ссылок показываются по-русски и без секретов («В ключе Reality нет публичного ключа (pbk)» и т. п.).

## Подписки
- Запрос с `User-Agent: Tunnely/0.1.0` → панели (3x-ui, Marzban, Remnawave) отдают стандартный base64-список ссылок.
- Также понимается Clash/Mihomo YAML (берётся только раздел `proxies`).
- Заголовки: `profile-title` (в т.ч. `base64:`), `profile-update-interval`, `subscription-userinfo` (трафик и срок).
- Ограничения: 20 с на ответ, до 5 МБ. TLS-сертификаты проверяются всегда. `http://` разрешён, но помечается «без HTTPS».
- Дубликаты (тип+адрес+порт+ключ) не добавляются повторно.

## Что проверено на реальных серверах
| Конфигурация | Где | Результат |
|---|---|---|
| VLESS + Reality + Vision (Mihomo-сервер) | локальный тест | ✅ |
| VLESS + Reality + Vision + VLESS Encryption `mlkem768x25519plus`, Xray-сервер владельца (Frankfurt, Finland) | эмулятор, release | ✅ `loc=DE`, `loc=FI` |
| Trojan, SS, VMess, Hysteria2, TUIC, XHTTP, WS, gRPC | только юнит-тесты + валидация конфигов парсером Mihomo | ⚠️ на живых серверах не проверено |

## Совместимость Reality с новыми Xray-серверами (важно)
С 2026-09 REALITY-сервер Xray отклоняет ClientHello без ключа **X25519MLKEM768** перед X25519. Mihomo по умолчанию этот ключ убирает, а его шаблон отпечатка `firefox` не умеет отправлять его правильно — результат `REALITY authentication failed`, хотя Xray-клиенты (Happ, v2rayNG) работают.

Tunnely автоматически, для каждого Reality-сервера:
- включает `support-x25519mlkem768: true`;
- использует отпечаток `chrome` (оставляет `chrome`/`edge`, остальные заменяет).

Остаточный риск: Mihomo сообщает серверу версию клиента 1.8.2. Если на сервере Xray ≥ 26.7.11 действует `minClientVer` (по умолчанию 26.3.27), подключение будет отклонено. Лечится на сервере: `"minClientVer": "1.8.2"` в `realitySettings`. На серверах владельца это не требуется.

## Маршрутизация
- `ruDirect` (по умолчанию): российские домены (`.ru`, `.рф`, `.su`, geosite `category-ru`) и IP (geoip `ru`) — напрямую, DNS для них — Яндекс DoH; остальное — через VPN.
- `global`: всё через VPN.
- Всегда напрямую: локальные сети (10/8, 172.16/12, 192.168/16, 169.254/16, fe80::/10, fc00::/7, `.local`).
- DoT-проба Android Private DNS на 172.19.0.2:853 отклоняется, чтобы Android сразу перешёл на обычный DNS (его перехватывает Mihomo).
