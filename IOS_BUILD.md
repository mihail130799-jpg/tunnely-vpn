# iOS — отложено

Решение владельца от 2026-10-27 (PRODUCT_DECISIONS №15): сейчас развивается только Android.

## Почему
- VPN на iPhone требует entitlement Network Extension → только платный Apple Developer Program ($99/год). Бесплатный Apple ID и AltStore/Sideloadly туннель не запустят.
- Публикация VPN в App Store — только аккаунтом **организации** (App Review Guideline 5.4), нужен D-U-N-S; регистрация и оплата из России затруднены.
- RuStore для iPhone недоступен (2026-10).
- GPL-3.0 плохо совместима с условиями App Store.

## План, когда вернёмся
1. Без оплаты: Xcode-проект, `PacketTunnel` (NEPacketTunnelProvider) + App Group + Keychain, ядро `tunnelycore.xcframework` (`gomobile bind -target=ios`), сборка на macOS в GitHub Actions. Общий Dart-код уже готов (каналы `tunnely/vpn` — те же).
2. Личный платный аккаунт: Ad Hoc (до 100 iPhone/год) или TestFlight — проверка реального VPN на iPhone.
3. Аккаунт организации: App Store, Unlisted, вне российского региона.

Пока iPhone-клиенты могут пользоваться Happ с подпиской владельца (название профиля «✦ Tunnely VPN ✦» приходит из панели).
