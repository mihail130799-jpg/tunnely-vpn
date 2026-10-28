# Builds vpn_core (Xray-core wrapper) into an Android AAR via gomobile.
# Output: vpn_core/build/tunnelycore.aar, copied to vpn_client/android/app/libs/.
param(
    [string]$Targets = "android/arm64,android/arm,android/amd64"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$ndk = Get-ChildItem "$sdk\ndk" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if (-not $ndk) { throw "Android NDK not found in $sdk\ndk. Install it via Android Studio SDK Manager." }
$jbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not $env:JAVA_HOME -and (Test-Path $jbr)) { $env:JAVA_HOME = $jbr }
if (-not $env:JAVA_HOME) { throw "JAVA_HOME is not set and Android Studio JBR was not found." }

$env:ANDROID_HOME = $sdk
$env:ANDROID_NDK_HOME = $ndk.FullName
$env:Path = "C:\Program Files\Go\bin;$env:USERPROFILE\go\bin;$env:JAVA_HOME\bin;$env:Path"

if (-not (Get-Command go -ErrorAction SilentlyContinue)) { throw "Go is not installed. Run scripts/setup_windows.ps1." }
if (-not (Get-Command gomobile -ErrorAction SilentlyContinue)) {
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
}

# gomobile/go print progress to stderr; check $LASTEXITCODE instead of failing on it.
$ErrorActionPreference = "Continue"
Push-Location "$root\vpn_core"
try {
    New-Item -ItemType Directory -Force build | Out-Null
    # -checklinkname=0: Xray's anet dependency links to net internals (as in v2rayNG/libXray builds).
    $ldflags = "-s -w -buildid= -checklinkname=0"
    gomobile bind "-target=$Targets" -androidapi 24 -javapkg com.tunnely.core -trimpath `
        -ldflags $ldflags -o build/tunnelycore.aar ./tunnelycore
    if ($LASTEXITCODE -ne 0) { throw "gomobile bind failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$libs = "$root\vpn_client\android\app\libs"
New-Item -ItemType Directory -Force $libs | Out-Null
Copy-Item "$root\vpn_core\build\tunnelycore.aar" $libs -Force
$hash = (Get-FileHash "$libs\tunnelycore.aar" -Algorithm SHA256).Hash
Write-Host "OK: $libs\tunnelycore.aar  SHA256=$hash"
