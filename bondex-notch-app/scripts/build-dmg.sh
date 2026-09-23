#!/bin/bash
#
# Packages Bondex Notch.app into a distributable .dmg file with a drag-to-Applications link.
#
# Usage:
#   ./scripts/build-dmg.sh [--rebuild]
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bondex Notch"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
DMG_PATH="$ROOT/build/$APP_NAME.dmg"
VOLUME_NAME="Bondex Notch"

REBUILD=false
for arg in "$@"; do
  if [[ "$arg" == "--rebuild" ]]; then
    REBUILD=true
  fi
done

if [[ ! -d "$APP_BUNDLE" || "$REBUILD" == true ]]; then
  echo "==> Building universal release app..."
  "$ROOT/scripts/build-app.sh" release --universal
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
