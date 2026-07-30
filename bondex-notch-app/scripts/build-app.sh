#!/bin/bash
#
# Builds BondexNotch and assembles a runnable .app bundle.
#
# SwiftPM produces a bare executable; a notch app needs a real bundle so macOS
# honours LSUIElement, reads the usage descriptions for the TCC prompts, and
# gives the process a stable bundle identifier for its permission grants.
#
# Usage:
#   ./scripts/build-app.sh [debug|release] [--universal]

set -euo pipefail

CONFIG="${1:-release}"
UNIVERSAL=""
for arg in "$@"; do
  [[ "$arg" == "--universal" ]] && UNIVERSAL="--arch arm64 --arch x86_64"
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bondex Notch"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "==> Building ($CONFIG)"
# shellcheck disable=SC2086
swift build -c "$CONFIG" $UNIVERSAL

BIN_PATH="$(swift build -c "$CONFIG" $UNIVERSAL --show-bin-path)"
EXECUTABLE="$BIN_PATH/BondexNotch"

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "error: expected executable at $EXECUTABLE" >&2
  exit 1
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$BUNDLE/Contents/MacOS/BondexNotch"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Ad-hoc signature. Enough for local runs and for TCC to remember grants for
# this build; replace with a Developer ID identity before distributing, or the
# grants reset on every rebuild.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 || {
  echo "warning: ad-hoc signing failed; the app will still run locally" >&2
}

echo "==> Built $BUNDLE"
