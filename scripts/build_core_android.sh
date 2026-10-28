#!/usr/bin/env bash
# Builds vpn_core (Xray-core wrapper) into an Android AAR via gomobile (Linux/macOS/CI).
# Windows: use build_core_android.ps1. Requires Go, JDK 17+, ANDROID_HOME with an NDK.
set -euo pipefail
# -checklinkname=0: Xray's anet dependency links to net internals (as in v2rayNG/libXray builds).

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
# -checklinkname=0: Xray's anet dependency links to net internals (as in v2rayNG/libXray builds).
gomobile bind "-target=$TARGETS" -androidapi 24 -javapkg com.tunnely.core -trimpath \
  -ldflags "-s -w -buildid= -checklinkname=0" -o build/tunnelycore.aar ./tunnelycore

mkdir -p "$ROOT/vpn_client/android/app/libs"
cp build/tunnelycore.aar "$ROOT/vpn_client/android/app/libs/"
sha256sum "$ROOT/vpn_client/android/app/libs/tunnelycore.aar" 2>/dev/null || shasum -a 256 "$ROOT/vpn_client/android/app/libs/tunnelycore.aar"
