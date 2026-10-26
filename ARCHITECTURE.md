# Архитектура Tunnely

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│ screens/  HomeScreen · ServersPanel · ImportSheet · Settings   │
│ widgets/  TunnelButton (CustomPainter, анимации)               │
│ providers/AppController (Riverpod Notifier) ── AppState        │
│ core/     link_parser · subscription_parser · mihomo_config     │
│ services/ VpnPlatform (каналы) · SubscriptionService (HTTP)     │
│           SecureAppStorage (Keystore) · tcpPing                 │
└───────────────┬───────────── MethodChannel "tunnely/vpn" ──────┘
                │              EventChannel  "tunnely/vpn/state"
┌───────────────▼──────────── Android (Kotlin) ──────────────────┐
│ VpnBridge          каналы ⇄ сервис; запрос разрешения VPN       │
│ TunnelyVpnService  VpnService + foreground; TUN → fd → ядро     │
│ ConfigStore        конфиг ядра, AES-GCM ключом Android Keystore │
│ VpnState           единое состояние → UI, плитка, виджет        │
│ TunnelTileService · TunnelWidget · QuickToggle                  │
└───────────────┬────────────────── JNI (gomobile) ──────────────┘
┌───────────────▼──────────── vpn_core (Go) ─────────────────────┐
│ tunnelycore: Start/Stop/Validate/TrafficNow/Delay/HealthCheck/  │
│              SelectProxy/CloseAllConnections, Protector, Logs   │
│ Mihomo v1.19.33 (теги with_gvisor, cmfa): TUN gVisor, DNS,      │
│ правила, VLESS/Reality/…                                        │
└────────────────────────────────────────────────────────────────┘
```

## Поток подключения
1. Пользователь нажимает туннель → `AppController.connect()`.
2. `VpnPlatform.prepare()` — системный запрос разрешения VPN (один раз).
3. `buildMihomoConfig()` строит конфиг (JSON — валидный YAML для Mihomo): прокси, группы `PROXY` (select) и `Авто` (url-test), DNS fake-ip через DoH, правила, `tun.file-descriptor: 0`.
4. `validate()` прогоняет конфиг настоящим парсером Mihomo до запуска.
5. `start()` → Kotlin шифрует конфиг (`ConfigStore`) и запускает `TunnelyVpnService`.
6. Сервис создаёт TUN (172.19.0.1/30, fdfe:dcba:9876::1/126, MTU 9000, DNS 172.19.0.2), исключает собственное приложение из туннеля, подставляет fd в текст конфига (без пересериализации) и вызывает `Tunnelycore.start`.
7. Если Mihomo не поднял TUN, `Start` возвращает ошибку — «Защищено» не показывается без рабочего туннеля.
8. После CONNECTED приложение делает `HealthCheck(Авто)` (в режиме «Авто») и `Delay` выбранного сервера; мёртвый сервер → предупреждение.

## Почему так
- **Конфиг хранится в Kotlin** (зашифрованным): плитка и виджет запускают VPN без Flutter-интерфейса.
- **Свой процесс не идёт через туннель** (`addDisallowedApplication` + `protect`): загрузка подписок и сокеты ядра не зацикливаются.
- **Смена сети:** `NetworkCallback` → `setUnderlyingNetworks` + `CloseAllConnections`, приложения быстро переподключаются через новую сеть.
- **Переключение сервера на лету:** `SelectProxy(PROXY, имя)` без перезапуска туннеля; имена серверов детерминированы (`MihomoConfig.proxyNames`).
- **Стабильные id серверов** (FNV-1a от тип|адрес|порт|секрет) — выбор и задержки переживают обновление подписки.
- **Совместимость Reality** (`withRealityCompat`): MLKEM768 + отпечаток chrome — см. VPN_PROTOCOLS.md.

## Данные
| Что | Где |
|---|---|
| Серверы, подписки (содержат ключи) | flutter_secure_storage → Android Keystore |
| Выбранный сервер, настройки | SharedPreferences (без секретов) |
| Конфиг для сервиса/плитки/виджета | `noBackupFilesDir/active_config.bin`, AES-256-GCM, ключ в Keystore |
| Rule-set «Россия» | assets → `filesDir/mihomo/ruleset` при обновлении приложения |
Резервное копирование данных приложения отключено (`allowBackup=false`, data extraction rules).

## Решения (ADR)
- `docs/adr/0001-vpn-core.md` — Xray (отклонено владельцем, запасной вариант)
- `docs/adr/0002-vpn-core-mihomo.md` — Mihomo, GPL, совместимость с новыми Xray-серверами
