# Архитектура Tunnely

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│ screens/  HomeScreen · ServersPanel · ImportSheet · Settings   │
│           LogsScreen (журнал) · About (диагностика)            │
│ widgets/  TunnelButton (CustomPainter, анимации)               │
│ providers/AppController (Riverpod Notifier) ── AppState        │
│ core/     link_parser · subscription_parser · xray_config       │
│ services/ VpnPlatform (каналы) · SubscriptionService (HTTP)     │
│           SecureAppStorage (Keystore) · AppLog (журнал)         │
└───────────────┬───────────── MethodChannel "tunnely/vpn" ──────┘
                │              EventChannel  "tunnely/vpn/state"
┌───────────────▼──────────── Android (Kotlin) ──────────────────┐
│ VpnBridge          каналы ⇄ сервис; запрос разрешения VPN       │
│ TunnelyVpnService  VpnService + foreground; TUN fd → ядро       │
│ ConfigStore        конфиг ядра, AES-GCM ключом Android Keystore │
│ VpnState           единое состояние → UI, плитка, виджет        │
│ TunnelTileService · TunnelWidget · QuickToggle                  │
└───────────────┬────────────────── JNI (gomobile) ──────────────┘
┌───────────────▼──────────── vpn_core (Go) ─────────────────────┐
│ tunnelycore: StartWithFd/Stop/Validate/TrafficNow/DelayError/   │
│              RecentLogs/RecentEvents/AppendEvent, Protector     │
│ Xray-core v26.10.21: inbound tun (fd через "xray.tun.fd"),      │
│ VLESS/Reality/Vision/Encryption/XHTTP, Trojan, SS, VMess,       │
│ DNS, routing, balancer leastPing + observatory, stats           │
└────────────────────────────────────────────────────────────────┘
```

## Поток подключения
1. Пользователь нажимает туннель → `AppController.connect()`.
2. `VpnPlatform.prepare()` — системный запрос разрешения VPN (один раз).
3. Режим «Авто»: все серверы проверяются настоящим HTTP-запросом через временное ядро (`buildProbeConfig`), самый быстрый живой становится `fallbackTag` балансировщика.
4. `buildXrayConfig()` строит JSON-конфиг Xray: inbound `tun` со сниффингом, outbound'ы серверов, `direct`/`block`/`dns-out`, DNS, правила, балансировщик `auto` (leastPing) + observatory — либо прямой маршрут на выбранный сервер.
5. `validate()` прогоняет конфиг через загрузчик Xray до запуска.
6. `start()` → Kotlin шифрует конфиг (`ConfigStore`) и запускает `TunnelyVpnService`.
7. Сервис создаёт TUN (172.19.0.1/30, fdfe:dcba:9876::1/126, MTU 9000, DNS 172.19.0.2), исключает собственное приложение и выбранные приложения (`bypass_apps.txt` от `ConfigStore`) из туннеля и вызывает `Tunnelycore.startWithFd(config, fd)`.
8. После CONNECTED приложение проверяет активный сервер (или все в «Авто») через работающее ядро. Если сервер не отвечает — сообщение с причиной; если не отвечает ни один — подписка обновляется, и при 404/403 пользователь узнаёт, что подписка больше не действует.

## Журнал
- **Приложение** (`AppLog`, файл в app-support): запуск, импорт, проверки серверов, подключения, ошибки, настройки.
- **VPN-служба** (`events.log`): команды, TUN, старт/стоп ядра, смена сети, отзыв разрешения.
- **Ядро** (`core.log`): журнал ошибок Xray (warning; в подробном режиме — info).
- Экран «Настройки → Журнал работы»; «Скопировать всё» и «Проверить соединение и скопировать отчёт».
- В журнал никогда не пишутся ключи, UUID, пароли, ссылки подписок.

## Обновление приложения
- `services/update_service.dart`: GitHub API `releases/latest` → APK `*-<ABI>.apk` + хеш из `SHA256SUMS.txt`; загрузка потоком с проверкой SHA-256.
- `providers/update_controller.dart`: автопроверка раз в сутки при запуске, состояние для баннера на главном экране и раздела «Обновление приложения» в настройках.
- Kotlin `Updater`: `appInfo` (версия, ABI) и `installApk` (FileProvider → системный установщик; если нет разрешения — экран «Установка неизвестных приложений»).

## Почему так
- **Ядро Xray** — то же, что у Happ и на серверах владельца (Reality, VLESS Encryption, XHTTP). Отпечаток из ключа используется как есть. См. ADR 0003.
- **Конфиг хранится в Kotlin** (зашифрованным): плитка и виджет запускают VPN без Flutter-интерфейса.
- **Свой процесс не идёт через туннель** (`addDisallowedApplication` + `protect` через `RegisterDialerController`): загрузка подписок и сокеты ядра не зацикливаются.
- **Смена сервера** — перезапуск ядра с новым маршрутом (TUN пересоздаётся, ~1 с).
- **Стабильные id серверов** (FNV-1a от тип|адрес|порт|секрет) — выбор и задержки переживают обновление подписки.
- **Скорость** — по счётчикам outbound (tun-inbound занижает).

## Данные
| Что | Где |
|---|---|
| Серверы, подписки (содержат ключи) | flutter_secure_storage → Android Keystore |
| Выбранный сервер, настройки (режим VPN, выбор приложений), время проверки обновлений | SharedPreferences (без секретов) |
| Скачанное обновление | `cache/updates/*.apk` (удаляется перед следующей загрузкой) |
| Конфиг для сервиса/плитки/виджета | `noBackupFilesDir/active_config.bin`, AES-256-GCM, ключ в Keystore |
| Журналы | `filesDir/xray/{core,events}.log`, app-support `app.log` (до ~0,5 МБ каждый) |
| Российские IP для маршрутизации | asset `assets/routing/ru_ipv4.txt` (ipverse, CC0) |

## Решения (ADR)
- `docs/adr/0001-vpn-core.md` — первичный выбор Xray (заменён владельцем на Mihomo)
- `docs/adr/0002-vpn-core-mihomo.md` — Mihomo (заменено)
- `docs/adr/0003-vpn-core-xray.md` — **текущее ядро Xray-core**
