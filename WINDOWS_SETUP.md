# Подготовка Windows для сборки Tunnely

## Автоматически
```powershell
.\scripts\setup_windows.ps1                    # только проверка, ничего не меняет
.\scripts\setup_windows.ps1 -Install           # поставить недостающее
.\scripts\setup_windows.ps1 -Install -PersistEnv   # + сохранить JAVA_HOME, ANDROID_HOME, FLUTTER_ROOT, PATH
```
Скрипт ставит Git и Go (winget), Flutter stable (git clone в `D:\dev\flutter`, параметр `-FlutterDir`), gomobile, пакеты Android SDK. **Android Studio нужно установить вручную** (из него берутся JDK и SDK Manager).

## Что нужно
| Компонент | Версия (проверено) | Где |
|---|---|---|
| Windows 10/11 x64 | 11 Pro 26300 | |
| Android Studio | с JBR (JDK 25) | `C:\Program Files\Android\Android Studio` |
| Android SDK | platform 36, build-tools 36.0.0, NDK 27.2 (ядро) и 28.2 (плагин jni), cmdline-tools | `%LOCALAPPDATA%\Android\Sdk` |
| Flutter / Dart | 3.47.8 / 3.13.7 | `D:\dev\flutter` |
| Go | 1.27.0 | `C:\Program Files\Go` |
| gomobile/gobind | golang.org/x/mobile latest | `%USERPROFILE%\go\bin` |
| Git | 2.56 | `C:\Program Files\Git` |
| ~15 ГБ диска | | |

## Эмулятор для проверок
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" "system-images;android-35;google_apis;x86_64"
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n tunnely_test -k "system-images;android-35;google_apis;x86_64" -d pixel_7
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd tunnely_test
```
Нужна аппаратная виртуализация (WHPX): `emulator -accel-check`.

## Особенности Windows
- Проект на `D:`, кэш pub на `C:` → в `vpn_client/android/gradle.properties` выключена инкрементальная компиляция Kotlin (`kotlin.incremental=false`), иначе ломаются кэши.
- Скрипты `.ps1` сохранены в UTF-8 с BOM — иначе Windows PowerShell 5.1 искажает русский текст.
- Не запускайте две сборки одновременно в одной папке: они портят общие промежуточные файлы.
