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

## Поддержка в ядре Xray
VLESS, VMess, Trojan, Shadowsocks — да; транспорты raw/tcp (вкл. HTTP-заголовок), WS, HTTPUpgrade, gRPC, XHTTP; безопасность TLS и Reality; VLESS Encryption.
**Не поддерживаются:** Hysteria2, TUIC, Shadowsocks с плагинами, транспорт h2 — такие серверы показываются в списке, но в подключение не попадают.

## Что проверено на реальных серверах
| Конфигурация | Где | Результат |
|---|---|---|
| VLESS + Reality + Vision + VLESS Encryption `mlkem768x25519plus`, отпечаток firefox — серверы владельца Frankfurt и Finland | ПК (Xray probe) и эмулятор, release 0.2.0 | ✅ |
| Trojan, SS, VMess, XHTTP, WS, gRPC | юнит-тесты + загрузка конфигов настоящим загрузчиком Xray | ⚠️ на живых серверах не проверено |

## Совместимость с серверами
Ядро — Xray-core, то же, что у Happ и на серверах владельца, поэтому отпечаток браузера (`fp`) и все параметры Reality/VLESS Encryption из ключа используются без изменений. Обходы, нужные для Mihomo в версиях 0.1.x (замена `firefox` на `chrome`, MLKEM), больше не нужны.

## Маршрутизация
- `ruDirect` (по умолчанию): российские домены (`.ru`, `.рф`, `.su` и крупные сервисы РФ на других доменах) и 8 672 российских IPv4-диапазона (ipverse/rir-ip, CC0) — напрямую; DNS для российских доменов — Яндекс DoH напрямую, остальное — Cloudflare/Google DoH через VPN.
- `global`: всё через VPN.
- Приложения: в режиме `ruDirect` российские приложения (`core/russian_apps.dart`: банки, госсервисы, VK, Яндекс, маркетплейсы, операторы, транспорт и любые пакеты `ru.*`) исключаются из VPN на уровне Android (`addDisallowedApplication`) — их трафик вообще не попадает в туннель. Ручные исключения/включения хранятся в настройках (`alwaysDirectApps` / `alwaysVpnApps`) и сильнее автоматического правила.
- Всегда напрямую: локальные сети (10/8, 172.16/12, 192.168/16, 169.254/16, fe80::/10, fc00::/7, `.local`).
- DoT-проба Android Private DNS на 172.19.0.2:853 отклоняется, чтобы Android сразу перешёл на обычный DNS (его обслуживает DNS-модуль Xray).
