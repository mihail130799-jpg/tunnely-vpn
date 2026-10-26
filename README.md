# Tunnely VPN

VPN-клиент под собственным брендом для клиентов VPN-сервиса владельца. Пользователь получает ключ или ссылку на подписку, вставляет её одним нажатием и подключается кнопкой-туннелем.

- **Платформа:** Android 7.0+ (APK вне Google Play). iOS отложена — см. PRODUCT_DECISIONS №15.
- **Ядро:** [Mihomo](https://github.com/MetaCubeX/mihomo) v1.19.33 (Go, через gomobile).
- **Протоколы:** VLESS (Reality, Vision, XHTTP, WS, gRPC, VLESS Encryption), Trojan, Shadowsocks, VMess, Hysteria2, TUIC.
- **Лицензия:** GNU GPL v3 (следствие зависимостей Mihomo). Название и логотип Tunnely — бренд владельца.

## Возможности
- Импорт: буфер обмена, QR-код, файл, ручной ввод, системные ссылки `vless://`, `trojan://`, … и `tunnely://import?url=<подписка>`.
- Подписки: base64-список ссылок и Clash/Mihomo YAML; название, трафик и срок из заголовков панели; автообновление раз в сутки.
- Режим «Авто» (самый быстрый живой сервер), ручной выбор, переключение на лету без переподключения.
- Проверка, что выбранный сервер реально отвечает («Сервер не отвечает» вместо ложного «Защищено»).
- Маршрутизация: российские сайты напрямую или весь трафик через VPN; локальная сеть всегда напрямую.
- Плитка в шторке, виджет на рабочий стол, уведомление с кнопкой «Отключить».
- Светлая и тёмная тема, анимация «свет в туннеле».
- Ключи и подписки хранятся только на устройстве в зашифрованном виде (Android Keystore), без аналитики.

## Быстрый старт (Windows)
```powershell
.\scripts\setup_windows.ps1 -Install      # Git, Go, Flutter, gomobile, пакеты Android SDK
.\scripts\test_project.ps1                # анализ + 79 Dart-тестов + Go-тесты
.\scripts\build_android.ps1 -RebuildCore  # ядро + подписанные release APK в releases/<версия>/
```
Подробнее: [WINDOWS_SETUP.md](WINDOWS_SETUP.md), [ANDROID_BUILD.md](ANDROID_BUILD.md).

## Структура
```
vpn_client/     Flutter-приложение (lib/), Android-часть (android/app/src/main/kotlin)
vpn_core/       Go-обёртка Mihomo для gomobile (tunnelycore)
scripts/        сборка и проверки (PowerShell + bash для CI)
releases/       собранные APK (в git только SHA256SUMS)
secrets/        ключ подписи и тестовые ключи — НЕ в git
docs/           анализ Happ/Husi, ADR, макеты, скриншоты
```

## Документация
| Файл | О чём |
|---|---|
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | что сделано, что проверено, что дальше |
| [PRODUCT_DECISIONS.md](PRODUCT_DECISIONS.md) | согласованные с владельцем решения |
| [ARCHITECTURE.md](ARCHITECTURE.md) | устройство приложения |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | цвета, шрифты, экраны |
| [VPN_PROTOCOLS.md](VPN_PROTOCOLS.md) | форматы ссылок, совместимость с серверами |
| [SECURITY.md](SECURITY.md) | хранение данных, разрешения, лицензии |
| [TESTING.md](TESTING.md) | автотесты и ручные проверки |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | частые проблемы и решения |
| [ANDROID_BUILD.md](ANDROID_BUILD.md) | сборка, подпись, установка, обновление |
| [WINDOWS_SETUP.md](WINDOWS_SETUP.md) | подготовка компьютера |
| [IOS_BUILD.md](IOS_BUILD.md) | статус iOS (отложена) |
