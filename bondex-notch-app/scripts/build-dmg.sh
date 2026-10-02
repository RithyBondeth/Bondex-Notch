#!/bin/bash
#
# Packages Bondex Notch.app into a distributable .dmg file with a drag-to-Applications link.
#
# Usage:
#   ./scripts/build-dmg.sh [--skip-build]
#
# Always builds a fresh universal release first, so a stale debug or
# single-architecture bundle in build/ can never be shipped by accident.
# --skip-build packages the existing bundle, and still refuses one that is not
# universal.
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bondex Notch"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
DMG_PATH="$ROOT/build/$APP_NAME.dmg"
VOLUME_NAME="Bondex Notch"

SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --rebuild) ;; # Former flag; rebuilding is now the default.
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done

if [[ "$SKIP_BUILD" == false ]]; then
  echo "==> Building universal release app..."
  "$ROOT/scripts/build-app.sh" release --universal
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: $APP_BUNDLE does not exist; run without --skip-build" >&2
  exit 1
fi

ARCHS="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/BondexNotch")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "error: app is built for '$ARCHS' only; the DMG must be universal (arm64 x86_64)" >&2
  exit 1
fi

echo "==> Preparing DMG staging area..."
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bondex-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

# Copy the application bundle into staging
cp -R "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"

# Create symlink to /Applications for drag-and-drop installation
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG at $DMG_PATH..."
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Built $DMG_PATH successfully"
