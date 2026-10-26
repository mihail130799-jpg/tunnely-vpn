# PROJECT_STATUS

> При перезапуске Claude Code: сначала прочитать этот файл и PRODUCT_DECISIONS.md.

## Текущий этап
Этап 5 — согласование функций (вопросы заданы владельцу). Бренд, дизайн (концепция C, DESIGN_SYSTEM.md), ядро Mihomo и лицензия GPL-3.0 согласованы. Ядро собрано в AAR.
Далее технически: Android VpnService + MethodChannel, Dart-парсер ссылок и генератор YAML Mihomo, экраны по концепции C.

Установлено 2026-10-26: Flutter stable (D:\dev\flutter, первичная инициализация), Go 1.27.0. Git не был в PATH текущей сессии — в setup_windows.ps1 добавлять PATH явно.

Примечание по логотипу: исходник 640×640 JPG — для иконки iOS (1024×1024) и адаптивной иконки Android нужен векторный/крупный вариант знака без текста. План: перерисовать знак в SVG, показать владельцу на сверку.

## Окружение (проверено 2026-10-26)
| Компонент | Состояние |
|---|---|
| ОС | Windows 11 Pro 10.0.26300, i5-12400, 15.8 ГБ RAM |
| Диск D: | ~130 ГБ свободно |
| Git | установлен 2026-10-26 (winget, Git 2.56.0.3) |
| Flutter / Dart | Flutter 3.47.8 stable, Dart 3.13.7 — `D:\dev\flutter` (PATH не прописан глобально) |
| Go / gomobile | Go 1.27.0 установлен; gomobile ещё нет — нужен для сборки sing-box (libbox) |
| Android Studio | установлен, JBR OpenJDK 25.0.3 |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk`: platform 35, build-tools 35.0.0, NDK 27.2.12479018, cmdline-tools, emulator |
| Образ эмулятора | android-37.0 google_apis_playstore x86_64; AVD ещё не создан |
| Гипервизор | присутствует (эмулятор должен работать через WHPX — не проверено) |
| Физическое Android-устройство | не подключено |
| Node.js, Python 3.12, winget, GitHub CLI | есть; gh авторизован (аккаунт mihail130799-jpg) |
| JAVA_HOME / ANDROID_HOME | не заданы — задать в setup_windows.ps1 |

## Ограничения окружения
- Нет Mac → iOS-сборка и Xcode не могут быть запущены локально; только исходники + CI на macOS (GitHub Actions) или облачный Mac.
- Apple Developer Program не оплачен → NetworkExtension-entitlement и установка на iPhone невозможны до оплаты.
- Нет тестового VLESS Reality ключа в проекте → реальное подключение проверить можно будет, когда владелец даст тестовый ключ (не коммитить его).
- JDK 25 из Android Studio может быть слишком новым для Gradle/AGP — при необходимости установить JDK 17/21.

## Выполненные задачи
- Проверено окружение, установлены Git, Flutter, Go.
- Бренд, темы и концепция C согласованы; DESIGN_SYSTEM.md написан.
- Создан Flutter-проект `vpn_client/` (package `tunnely`, org `com.tunnely`, Android + iOS), git-репозиторий (ветка main).
- Ядро Mihomo v1.19.33 подтверждено, лицензия проекта GPL-3.0 (LICENSE). Анимация: выразительная. Android-референс: Husi (docs/HUSI_ANALYSIS.md).
- `vpn_core/tunnelycore` — Go-обёртка Mihomo (Start/Stop/Validate/TrafficNow/Delay/SelectProxy/NowProxy, Protector для VpnService.protect, LogSink). `go vet` чистый.
- **Собран `tunnelycore.aar`** (gomobile, arm64 / armv7 / x86_64, minSdk 24, ~80 МБ на все ABI) скриптом `scripts/build_core_android.ps1`. Запуск ядра на устройстве ещё НЕ проверялся.

## Результаты тестирования
Пока нет.

## Известные ошибки
Нет.

## Непроверенные функции
Всё (код ещё не написан).

## Следующие действия
1. Согласовать анимации, затем функции (этап 5).
2. Технически: установить gomobile, собрать libXray `.aar`; создать AVD и проверить эмулятор; Android VpnService + MethodChannel.
3. Перерисовать знак логотипа в SVG для иконок.
4. Получить от владельца тестовый ключ VLESS Reality (не коммитить; хранить в secrets/).
