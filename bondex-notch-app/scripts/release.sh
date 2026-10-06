#!/bin/bash
#
# Publishes a release: tests, a signed universal DMG, a signed Sparkle appcast,
# a git tag, and a GitHub release carrying both files.
#
# Installed copies check
#   https://github.com/RithyBondeth/Bondex-Notch/releases/latest/download/appcast.xml
# which GitHub redirects to the newest release's appcast.xml — so publishing
# the release is what offers the update. Nothing else is hosted anywhere.
#
# Usage:
#   ./scripts/release.sh <version> --notes <notes.md> [--dry-run]
#
#   --dry-run   build and sign everything into build/release/, publish nothing
#
# Needs, once: scripts/setup-release-signing.sh. With a Developer ID, also set
# SIGN_IDENTITY and NOTARY_PROFILE (see build-dmg.sh).
#
# Environment:
#   SPARKLE_KEY_FILE  sign with this private key file instead of the keychain's

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="RithyBondeth/Bondex-Notch"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
OUT="$ROOT/build/release"

VERSION=""
NOTES=""
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -*) echo "error: unknown option $1" >&2; exit 1 ;;
    *) VERSION="$1"; shift ;;
  esac
done

fail() { echo "error: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "give a version like 1.1.0"
[[ -n "$NOTES" && -s "$NOTES" ]] || fail "give the release notes with --notes <file.md>"
NOTES="$(cd "$(dirname "$NOTES")" && pwd)/$(basename "$NOTES")"
TAG="v$VERSION"

cd "$ROOT"

# MARK: Checks — everything that can be wrong is found before anything is built.

echo "==> Checking"
command -v gh >/dev/null || fail "the GitHub CLI (gh) is not installed"
if [[ "$DRY_RUN" == false ]]; then
  gh auth status >/dev/null 2>&1 || fail "gh is not signed in (gh auth login)"
  [[ "$(git branch --show-current)" == "main" ]] || fail "release from main"
  git fetch --quiet origin main --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || fail "main is not the same as origin/main; pull or push first"
fi
# What ships is the working tree, so it must be exactly what is committed.
if [[ -n "$(git status --porcelain -- .)" ]]; then
  [[ "$DRY_RUN" == true ]] || fail "bondex-notch-app has uncommitted changes"
  echo "    (uncommitted changes: fine for a dry run, refused for a release)"
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "$TAG already exists"
fi
LATEST="$(git tag --list 'v[0-9]*' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
if [[ -n "$LATEST" ]]; then
  NEWEST="$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ "$NEWEST" == "$VERSION" && "$VERSION" != "$LATEST" ]] || fail "$VERSION is not newer than $LATEST"
fi
[[ -s Resources/SparklePublicKey.txt ]] || fail "no Sparkle key; run scripts/setup-release-signing.sh"
[[ -x "$SPARKLE_BIN/sign_update" ]] || swift package resolve
SIGN_KEY_ARGS=()
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
  SIGN_KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
else
  # Installed copies trust only the committed public key; a different private
  # key here would publish an update every one of them refuses.
  [[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$(tr -d '[:space:]' < Resources/SparklePublicKey.txt)" ]] \
    || fail "the keychain's Sparkle key is not the one in Resources/SparklePublicKey.txt"
fi

echo "==> Testing"
swift test >/dev/null 2>&1 || fail "the tests fail; run swift test"

# MARK: Build

rm -rf "$OUT"
mkdir -p "$OUT"
# A build directory of its own, so the developer's build/Bondex Notch.app —
# which their agent hooks may run — is left alone.
BUILD_DIR="$OUT/build" BONDEX_VERSION="$VERSION" "$ROOT/scripts/build-dmg.sh"
APP="$OUT/build/Bondex Notch.app"

codesign -dv "$APP" 2>&1 | grep -q '^Signature=adhoc' \
  && fail "the app is signed ad-hoc; installed copies would lose their permissions. Run scripts/setup-release-signing.sh"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]] \
  || fail "the app was not stamped $VERSION"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" >/dev/null 2>&1 \
  || fail "the app has no update feed"

# GitHub turns spaces in asset names into dots; naming it so here keeps the
# appcast's URL and the uploaded name the same.
DMG="$OUT/Bondex.Notch.dmg"
mv "$OUT/build/Bondex Notch.dmg" "$DMG"

echo "==> Signing the update"
SIGNATURE="$("$SPARKLE_BIN/sign_update" ${SIGN_KEY_ARGS[@]+"${SIGN_KEY_ARGS[@]}"} "$DMG")" \
  || fail "sign_update could not sign; is the Sparkle key in this keychain?"

# MARK: Appcast

echo "==> Writing the appcast"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DESCRIPTION="$(python3 - "$NOTES" <<'PY'
import html, re, sys
# The few Markdown forms release notes use, as the HTML Sparkle shows.
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
out, in_list = [], False
def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return re.sub(r"\[(.+?)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', text)
for line in lines:
    item = re.match(r"^\s*[-*] (.*)", line)
    if item:
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(item.group(1))}</li>"); continue
    if in_list: out.append("</ul>"); in_list = False
    heading = re.match(r"^#{1,6} (.*)", line)
    if heading: out.append(f"<h3>{inline(heading.group(1))}</h3>")
    elif line.strip(): out.append(f"<p>{inline(line)}</p>")
if in_list: out.append("</ul>")
print("\n".join(out).replace("]]>", "]]&gt;"))
PY
)"

cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Bondex Notch</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Bondex Notch $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
$DESCRIPTION
      ]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/Bondex.Notch.dmg"
                 type="application/octet-stream"
                 $SIGNATURE/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$OUT/appcast.xml" || fail "the appcast is not valid XML"
# Signs the feed itself; the app requires it (SURequireSignedFeed).
"$SPARKLE_BIN/sign_update" ${SIGN_KEY_ARGS[@]+"${SIGN_KEY_ARGS[@]}"} "$OUT/appcast.xml" >/dev/null \
  || fail "sign_update could not sign the appcast"

if [[ "$DRY_RUN" == true ]]; then
  echo "==> Dry run: nothing published"
  echo "    $DMG"
  echo "    $OUT/appcast.xml"
  exit 0
fi

# MARK: Publish

echo "==> Publishing $TAG"
git tag -a "$TAG" -m "Bondex Notch $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$OUT/appcast.xml" \
  --repo "$REPO" \
  --title "Bondex Notch $VERSION" \
  --notes-file "$NOTES" \
  --verify-tag

echo "==> Released https://github.com/$REPO/releases/tag/$TAG"
