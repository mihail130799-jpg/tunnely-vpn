#!/usr/bin/env bash
# Builds vpn_core (Mihomo wrapper) into an Android AAR via gomobile (Linux/macOS/CI).
# Windows: use build_core_android.ps1. Requires Go, JDK 17+, ANDROID_HOME with an NDK.
# Tag "cmfa" = Mihomo embedded-in-Android-app mode (no /data/system/packages.xml access).
set -euo pipefail

MIHOMO_VERSION="${MIHOMO_VERSION:-1.19.33}"
TARGETS="${TARGETS:-android/arm64,android/arm,android/amd64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

: "${ANDROID_HOME:?ANDROID_HOME is not set}"
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  ANDROID_NDK_HOME="$(ls -d "$ANDROID_HOME"/ndk/*/ 2>/dev/null | sort -V | tail -1)"
  ANDROID_NDK_HOME="${ANDROID_NDK_HOME%/}"
fi
[ -d "$ANDROID_NDK_HOME" ] || { echo "Android NDK not found under $ANDROID_HOME/ndk" >&2; exit 1; }
export ANDROID_NDK_HOME
export PATH="$(go env GOPATH)/bin:$PATH"

command -v gomobile >/dev/null || {
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
}

cd "$ROOT/vpn_core"
mkdir -p build
gomobile bind "-target=$TARGETS" -androidapi 24 -javapkg com.tunnely.core -trimpath \
  -ldflags "-s -w -buildid= -X github.com/metacubex/mihomo/constant.Version=$MIHOMO_VERSION" \
  -tags "with_gvisor,cmfa" -o build/tunnelycore.aar ./tunnelycore

mkdir -p "$ROOT/vpn_client/android/app/libs"
cp build/tunnelycore.aar "$ROOT/vpn_client/android/app/libs/"
sha256sum "$ROOT/vpn_client/android/app/libs/tunnelycore.aar" 2>/dev/null || shasum -a 256 "$ROOT/vpn_client/android/app/libs/tunnelycore.aar"
