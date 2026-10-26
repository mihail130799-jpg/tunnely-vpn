# Prepares a Windows machine for building Tunnely (Android).
#
#   .\scripts\setup_windows.ps1                 # check only, print what is missing
#   .\scripts\setup_windows.ps1 -Install        # install what can be installed safely
#   .\scripts\setup_windows.ps1 -Install -PersistEnv   # also save JAVA_HOME/ANDROID_HOME/PATH for the user
#
# Installs (with -Install): Git, Go (winget), Flutter (git clone, stable), gomobile,
# Android SDK packages (sdkmanager). Android Studio itself must be installed manually.
param(
    [switch]$Install,
    [switch]$PersistEnv,
    [string]$FlutterDir = "D:\dev\flutter"
)
$ErrorActionPreference = "Continue"
$ok = $true
function Report($name, $good, $detail) {
    $mark = if ($good) { "[OK]  " } else { "[--]  " }
    Write-Host ("{0}{1,-22} {2}" -f $mark, $name, $detail)
    if (-not $good) { $script:ok = $false }
}

$git = "C:\Program Files\Git\cmd\git.exe"
$go = "C:\Program Files\Go\bin\go.exe"
$jbr = "C:\Program Files\Android\Android Studio\jbr"
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
$sdkPackages = @("platform-tools", "platforms;android-36", "build-tools;36.0.0", "ndk;27.2.12479018", "ndk;28.2.13676358")

# --- Git / Go via winget --------------------------------------------------
if (-not (Test-Path $git) -and $Install) {
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}
Report "Git" (Test-Path $git) $git

if (-not (Test-Path $go) -and $Install) {
    winget install --id GoLang.Go -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}
$goVer = if (Test-Path $go) { (& $go version) } else { "не установлен" }
Report "Go" (Test-Path $go) $goVer

# --- Android Studio / SDK --------------------------------------------------
$hasJbr = Test-Path "$jbr\bin\java.exe"
Report "Android Studio (JBR)" $hasJbr $(if ($hasJbr) { $jbr } else { "установите вручную: https://developer.android.com/studio" })
Report "Android SDK" (Test-Path $sdk) $sdk
if ((Test-Path $sdkmanager) -and (Test-Path "$jbr\bin\java.exe")) {
    $env:JAVA_HOME = $jbr
    foreach ($pkg in $sdkPackages) {
        $dir = Join-Path $sdk ($pkg -replace ';', '\')
        if (-not (Test-Path $dir) -and $Install) {
            "y`ny`ny`n" | & $sdkmanager --install $pkg | Out-Null
        }
        Report "  $pkg" (Test-Path $dir) ""
    }
} else {
    Report "sdkmanager" $false "SDK Manager → SDK Tools → Android SDK Command-line Tools"
}

# --- Flutter ---------------------------------------------------------------
if (-not (Test-Path "$FlutterDir\bin\flutter.bat") -and $Install -and (Test-Path $git)) {
    New-Item -ItemType Directory -Force (Split-Path $FlutterDir) | Out-Null
    & $git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterDir
}
$flutterOk = Test-Path "$FlutterDir\bin\flutter.bat"
if ($flutterOk) {
    $env:Path = "C:\Program Files\Git\cmd;$FlutterDir\bin;$env:Path"
    & "$FlutterDir\bin\flutter.bat" --disable-analytics | Out-Null
    & "$FlutterDir\bin\flutter.bat" config --android-sdk $sdk | Out-Null
    $fv = (& "$FlutterDir\bin\flutter.bat" --version 2>$null | Select-Object -First 1)
}
Report "Flutter" $flutterOk $(if ($flutterOk) { $fv } else { "-Install склонирует stable в $FlutterDir" })

# --- gomobile --------------------------------------------------------------
$gomobile = "$env:USERPROFILE\go\bin\gomobile.exe"
if (-not (Test-Path $gomobile) -and $Install -and (Test-Path $go)) {
    & $go install golang.org/x/mobile/cmd/gomobile@latest
    & $go install golang.org/x/mobile/cmd/gobind@latest
}
Report "gomobile" (Test-Path $gomobile) $gomobile

# --- environment -----------------------------------------------------------
if ($PersistEnv) {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $jbr, "User")
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
    [Environment]::SetEnvironmentVariable("FLUTTER_ROOT", $FlutterDir, "User")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($p in @("C:\Program Files\Git\cmd", "C:\Program Files\Go\bin", "$FlutterDir\bin", "$env:USERPROFILE\go\bin", "$sdk\platform-tools")) {
        if ($userPath -notlike "*$p*") { $userPath = "$userPath;$p" }
    }
    [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
    Write-Host "Переменные окружения сохранены для пользователя (откройте новый терминал)."
}

$keyProps = Join-Path (Split-Path -Parent $PSScriptRoot) "vpn_client\android\key.properties"
Report "Ключ подписи" (Test-Path $keyProps) "нужен только для release (см. ANDROID_BUILD.md)"

if ($ok) { Write-Host "`nОкружение готово." } else { Write-Host "`nЕсть недостающие компоненты (см. [--] выше)." ; exit 1 }
