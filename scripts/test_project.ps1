# Runs every automated check of the project.
#
#   .\scripts\test_project.ps1              # analyzer + Dart tests + Go tests
#   .\scripts\test_project.ps1 -BuildDebug  # also build a debug APK
#
# Order matters: the Dart tests write golden Mihomo configs that the Go test
# then validates with the real Mihomo parser.
param([switch]$BuildDebug)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$flutterBin = if ($env:FLUTTER_ROOT) { "$env:FLUTTER_ROOT\bin" } else { "D:\dev\flutter\bin" }
$jbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not $env:JAVA_HOME -and (Test-Path $jbr)) { $env:JAVA_HOME = $jbr }
$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\Go\bin;$flutterBin;$env:Path"

$results = [ordered]@{}
function Step($name, [scriptblock]$body) {
    Write-Host "`n=== $name"
    & $body
    $results[$name] = ($LASTEXITCODE -eq 0)
}

Push-Location "$root\vpn_client"
Step "flutter pub get" { flutter pub get | Out-Null }
Step "flutter analyze" { flutter analyze }
Step "flutter test" { flutter test }
if ($BuildDebug) { Step "debug APK" { flutter build apk --debug } }
Pop-Location

Push-Location "$root\vpn_core"
Step "go vet" { go vet ./... }
Step "go test (Mihomo validates generated configs)" { go test ./tunnelycore/ }
Pop-Location

Write-Host "`n=== Итог"
$failed = 0
foreach ($k in $results.Keys) {
    $m = if ($results[$k]) { "OK  " } else { "FAIL"; $failed++ }
    Write-Host "  $m  $k"
}
if ($failed -gt 0) { exit 1 }
