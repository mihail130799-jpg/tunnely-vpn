# Builds signed release APKs (one per ABI) and puts them into releases/ with SHA-256 sums.
#
#   .\scripts\build_android.ps1            # tests + release build
#   .\scripts\build_android.ps1 -SkipTests
#   .\scripts\build_android.ps1 -RebuildCore   # also rebuild the Mihomo AAR first
#
# Signing: vpn_client/android/key.properties (not in git) or env vars
# TUNNELY_KEYSTORE_PATH / TUNNELY_KEYSTORE_PASSWORD / TUNNELY_KEY_ALIAS / TUNNELY_KEY_PASSWORD.
param(
    [switch]$SkipTests,
    [switch]$RebuildCore
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$client = "$root\vpn_client"

function Need($path, $hint) { if (-not (Test-Path $path)) { throw "Не найдено: $path. $hint" } }

# --- environment -----------------------------------------------------------
$flutterBin = if ($env:FLUTTER_ROOT) { "$env:FLUTTER_ROOT\bin" } else { "D:\dev\flutter\bin" }
Need "$flutterBin\flutter.bat" "Установите Flutter или задайте FLUTTER_ROOT (см. WINDOWS_SETUP.md)."
$jbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not $env:JAVA_HOME -and (Test-Path $jbr)) { $env:JAVA_HOME = $jbr }
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
Need $sdk "Установите Android SDK через Android Studio."
$env:Path = "C:\Program Files\Git\cmd;$flutterBin;$env:JAVA_HOME\bin;$env:Path"

$signed = (Test-Path "$client\android\key.properties") -or $env:TUNNELY_KEYSTORE_PATH
if (-not $signed) { throw "Нет ключа подписи: создайте android\key.properties (см. ANDROID_BUILD.md)." }

if ($RebuildCore -or -not (Test-Path "$client\android\app\libs\tunnelycore.aar")) {
    & "$PSScriptRoot\build_core_android.ps1"
}

# --- version ---------------------------------------------------------------
$verLine = Select-String -Path "$client\pubspec.yaml" -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$version = $verLine.Matches[0].Groups[1].Value   # e.g. 0.1.0+1
$versionName = $version.Split('+')[0]

# Native tools write warnings to stderr; PS 5.1 would turn them into fatal errors.
# Failures are detected through $LASTEXITCODE instead.
$ErrorActionPreference = "Continue"
Push-Location $client
try {
    flutter pub get | Out-Null
    if (-not $SkipTests) {
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze нашёл ошибки" }
        flutter test
        if ($LASTEXITCODE -ne 0) { throw "Тесты не прошли" }
    }
    flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "Сборка APK не удалась" }
} finally {
    Pop-Location
}

# --- collect artifacts -----------------------------------------------------
$out = "$root\releases\$versionName"
New-Item -ItemType Directory -Force $out | Out-Null
$apksigner = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name -Descending |
    ForEach-Object { "$($_.FullName)\apksigner.bat" } | Where-Object { Test-Path $_ } | Select-Object -First 1

$sums = @()
foreach ($abi in @("arm64-v8a", "armeabi-v7a", "x86_64")) {
    $src = "$client\build\app\outputs\flutter-apk\app-$abi-release.apk"
    if (-not (Test-Path $src)) { continue }
    $dst = "$out\Tunnely-$versionName-$abi.apk"
    Copy-Item $src $dst -Force
    if ($apksigner) {
        $certs = & $apksigner verify --print-certs $dst 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Подпись $dst не прошла проверку" }
        $certs | Select-String "SHA-256" | Select-Object -First 1 | Out-Host
    }
    $hash = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
    $sums += "$hash  $(Split-Path -Leaf $dst)"
}
$sums | Set-Content -Encoding ascii "$out\SHA256SUMS.txt"
Write-Host "`nГотово: $out"
$sums | ForEach-Object { Write-Host "  $_" }
