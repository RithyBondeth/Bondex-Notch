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

# Foundation Models and App Intents require plugins shipped with full Xcode.
# Prefer the standard Xcode install when the machine is currently pointed at
# the standalone Command Line Tools, while respecting an explicit override.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  ACTIVE_DEVELOPER_ROOT="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$ACTIVE_DEVELOPER_ROOT" == "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

CONFIG="${1:-release}"
ARCH_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--universal" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
  fi
done

# The Darwin build system emits the Swift constant-value files required by the
# App Intents metadata extractor. Supplying the host architecture selects it
# even for a non-universal local build.
if [[ ${#ARCH_ARGS[@]} -eq 0 ]]; then
  ARCH_ARGS=(--arch "$(uname -m)")
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bondex Notch"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "==> Building ($CONFIG)"
# The Xcode build system runs Swift's constant-value emission pass, which the
# App Intents metadata processor consumes below. SwiftPM's native build system
# does not currently emit those files for a single-architecture executable.
swift build -c "$CONFIG" --build-system xcode "${ARCH_ARGS[@]}"

BIN_PATH="$(swift build -c "$CONFIG" --build-system xcode "${ARCH_ARGS[@]}" --show-bin-path)"
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
CHECKOUT_URL="${BONDEX_CHECKOUT_URL:-https://bondex-notch.bondeth.site/checkout/}"
if [[ ! "$CHECKOUT_URL" =~ ^https?:// ]]; then
  echo "error: BONDEX_CHECKOUT_URL must begin with http:// or https://" >&2
  exit 1
fi
plutil -replace BondexCheckoutURL -string "$CHECKOUT_URL" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Resources/PreviewAssets" "$BUNDLE/Contents/Resources/PreviewAssets"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "==> Extracting App Intents metadata"
CONFIG_DIR="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
INTERMEDIATES="$ROOT/.build/apple/Intermediates.noindex/BondexNotch.build/$CONFIG_DIR/BondexNotch.build"
if [[ ! -d "$INTERMEDIATES/Objects-normal" ]]; then
  echo "error: App Intents build intermediates were not produced" >&2
  exit 1
fi
SWIFT_FILE_LIST="$(find "$INTERMEDIATES/Objects-normal" -name 'BondexNotch.SwiftFileList' -print -quit)"
if [[ -z "$SWIFT_FILE_LIST" ]]; then
  echo "error: App Intents source metadata was not produced" >&2
  exit 1
fi

OBJECTS_DIR="$(dirname "$SWIFT_FILE_LIST")"
METADATA_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bondex-app-intents.XXXXXX")"
trap 'rm -rf "$METADATA_TEMP"' EXIT
find "$OBJECTS_DIR" -name '*.swiftconstvalues' -print | sort \
  > "$METADATA_TEMP/const-values.txt"
if [[ ! -s "$METADATA_TEMP/const-values.txt" ]]; then
  echo "error: App Intents constant-value metadata was not produced" >&2
  exit 1
fi

DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"
PROCESSOR="$DEVELOPER_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor"
XCODE_BUILD="$(DEVELOPER_DIR="$DEVELOPER_ROOT" xcodebuild -version | awk 'NR == 2 { print $3 }')"
SDK_ROOT="$(DEVELOPER_DIR="$DEVELOPER_ROOT" xcrun --sdk macosx --show-sdk-path)"
METADATA_ARCH="$(basename "$OBJECTS_DIR")"

"$PROCESSOR" \
  --output "$BUNDLE/Contents/Resources" \
  --toolchain-dir "$DEVELOPER_ROOT/Toolchains/XcodeDefault.xctoolchain" \
  --module-name BondexNotch \
  --sdk-root "$SDK_ROOT" \
  --xcode-version "$XCODE_BUILD" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple "$METADATA_ARCH-apple-macos14.0" \
  --source-file-list "$SWIFT_FILE_LIST" \
  --swift-const-vals-list "$METADATA_TEMP/const-values.txt" \
  --metadata-file-list "$INTERMEDIATES/BondexNotch.DependencyMetadataFileList" \
  --static-metadata-file-list "$INTERMEDIATES/BondexNotch.DependencyStaticMetadataFileList" \
  --stringsdata-file "$OBJECTS_DIR/BondexAppIntents.stringsdata" \
  --deployment-aware-processing \
  --force \
  --quiet-warnings

if [[ ! -f "$BUNDLE/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]; then
  echo "error: App Intents metadata extraction did not produce actions" >&2
  exit 1
fi

# Ad-hoc signature. Enough for local runs and for TCC to remember grants for
# this build; replace with a Developer ID identity before distributing, or the
# grants reset on every rebuild.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 || {
  echo "warning: ad-hoc signing failed; the app will still run locally" >&2
}

echo "==> Built $BUNDLE"
