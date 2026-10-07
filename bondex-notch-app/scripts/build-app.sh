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
#
# Environment:
#   BUILD_DIR        where the bundle goes (default: build/)
#   BONDEX_VERSION   version to stamp (default: the latest v* tag)
#   BONDEX_UPDATES=1 build an updatable copy: adds Sparkle's feed and key.
#                    build-dmg.sh sets it; a developer's own build never
#                    updates itself.
#   SIGN_IDENTITY    codesign identity (default: "Bondex Notch Local Signing"
#                    when it is in the keychain, otherwise ad-hoc)
#   SIGN_KEYCHAIN    keychain to find it in (default: the search list), for CI

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
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
BUNDLE="$BUILD_DIR/$APP_NAME.app"
LOCAL_IDENTITY="Bondex Notch Local Signing"

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
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUNDLE/Contents/Frameworks"

cp "$EXECUTABLE" "$BUNDLE/Contents/MacOS/BondexNotch"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

# Sparkle, found through the @executable_path/../Frameworks run path set in
# Package.swift. Its XPC services exist for sandboxed apps; this one is not
# sandboxed, so they would only be more code to sign.
ditto "$BIN_PATH/Sparkle.framework" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
rm -rf "$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$BUNDLE/Contents/Frameworks/Sparkle.framework/XPCServices"

PLIST="$BUNDLE/Contents/Info.plist"
VERSION="${BONDEX_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
if [[ -n "$VERSION" ]]; then
  # Sparkle compares CFBundleVersion, so both carry the release number.
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

if [[ "${BONDEX_UPDATES:-}" == "1" ]]; then
  PUBLIC_KEY="$(tr -d '[:space:]' < "$ROOT/Resources/SparklePublicKey.txt" 2>/dev/null || true)"
  if [[ -z "$PUBLIC_KEY" ]]; then
    echo "error: Resources/SparklePublicKey.txt is missing; run scripts/setup-release-signing.sh" >&2
    exit 1
  fi
  # The feed and Sparkle's security settings, kept in one file the tests read.
  /usr/libexec/PlistBuddy -c "Merge $ROOT/Resources/SparkleInfo.plist" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" "$PLIST"
fi
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

# macOS remembers permission grants against the signature's identity. An
# ad-hoc signature is a hash of this exact build, so every rebuild — and every
# release — looked like a different app and had to be granted Automation,
# Downloads and clipboard access again. A certificate, even a self-signed one
# from scripts/setup-release-signing.sh, stays the same across builds.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null \
    | grep -qF "\"$LOCAL_IDENTITY\""; then
  IDENTITY="$LOCAL_IDENTITY"
fi
IDENTITY="${IDENTITY:--}"

SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
  SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
fi
APP_SIGN_ARGS=()
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
  # Notarization requires the hardened runtime and a secure timestamp.
  SIGN_ARGS+=(--options runtime --timestamp)
  APP_SIGN_ARGS=(--entitlements "$ROOT/Resources/BondexNotch.entitlements")
else
  SIGN_ARGS+=(--timestamp=none)
fi

echo "==> Signing (${IDENTITY/#-/ad-hoc})"
sign() {
  if ! codesign "$@" >/dev/null 2>&1; then
    if [[ "$IDENTITY" == "-" ]]; then
      echo "warning: ad-hoc signing failed for ${*: -1}; the app will still run locally" >&2
    else
      echo "error: signing with \"$IDENTITY\" failed for ${*: -1}" >&2
      codesign "$@" || true
      exit 1
    fi
  fi
}
# Inside out: a bundle's signature covers the code nested in it.
FRAMEWORK="$BUNDLE/Contents/Frameworks/Sparkle.framework"
sign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
sign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
sign "${SIGN_ARGS[@]}" "$FRAMEWORK"
sign "${SIGN_ARGS[@]}" ${APP_SIGN_ARGS[@]+"${APP_SIGN_ARGS[@]}"} "$BUNDLE"

echo "==> Built $BUNDLE"
