#!/bin/bash
#
# One-time setup on the Mac that publishes releases. Creates, if missing:
#
#   1. "Bondex Notch Local Signing", a self-signed code-signing certificate in
#      the login keychain. macOS remembers permission grants against the
#      signing identity; with this one every build and every release keeps
#      them, where an ad-hoc signature lost them each time. It is not an Apple
#      Developer ID, so a first install still needs "Open Anyway".
#
#   2. Sparkle's EdDSA update key. The private half stays in the login
#      keychain and signs each release; the public half is written to
#      Resources/SparklePublicKey.txt, is committed, and is built into the
#      app so it accepts only updates signed with the private half.
#
# Both are permanent: every future release must be signed with the same two
# keys, or installed copies will refuse it (Sparkle) or ask for permissions
# again (macOS). Back them up as printed at the end.
#
# Usage:
#   ./scripts/setup-release-signing.sh
#
# Environment:
#   KEYCHAIN   keychain for the certificate (default: the login keychain)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="Bondex Notch Local Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY_FILE="$ROOT/Resources/SparklePublicKey.txt"

if [[ ! -x "$SPARKLE_BIN/generate_keys" ]]; then
  echo "==> Fetching Sparkle's tools"
  (cd "$ROOT" && swift package resolve)
fi

# 1. Code-signing identity
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$IDENTITY\""; then
  echo "==> \"$IDENTITY\" is already in the keychain"
else
  echo "==> Creating \"$IDENTITY\""
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/bondex-signing.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/certificate.conf" <<EOF
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = $IDENTITY
[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  # The system's LibreSSL, whose PKCS#12 output the keychain can import;
  # OpenSSL 3 from Homebrew writes a format it rejects.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/certificate.conf" \
    -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
  PASSPHRASE="$(uuidgen)"
  /usr/bin/openssl pkcs12 -export -name "$IDENTITY" \
    -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASSPHRASE"
  # -T lets codesign use the key; macOS may still ask once, and "Always
  # Allow" makes that the last time.
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSPHRASE" -T /usr/bin/codesign >/dev/null
  echo "    created; valid for ten years"
fi

# 2. Sparkle update key
echo "==> Sparkle update key"
# Creates the key only if the keychain has none; otherwise prints the existing one.
"$SPARKLE_BIN/generate_keys" >/dev/null
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
if [[ -z "$PUBLIC_KEY" ]]; then
  echo "error: Sparkle's generate_keys returned no public key" >&2
  exit 1
fi
if [[ -f "$PUBLIC_KEY_FILE" && "$(tr -d '[:space:]' < "$PUBLIC_KEY_FILE")" != "$PUBLIC_KEY" ]]; then
  echo "error: the keychain's Sparkle key does not match Resources/SparklePublicKey.txt." >&2
  echo "       Copies already installed trust only the committed key. Import the" >&2
  echo "       private key it belongs to with: $SPARKLE_BIN/generate_keys -f <file>" >&2
  exit 1
fi
printf '%s\n' "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"
echo "    public key: $PUBLIC_KEY"
echo "    written to Resources/SparklePublicKey.txt — commit it"

cat <<EOF

Back up both keys somewhere safe, outside this Mac:
  • Keychain Access › My Certificates › "$IDENTITY" › Export… (.p12)
  • $SPARKLE_BIN/generate_keys -x <file>
Losing either means installed copies cannot take another update.

With an Apple Developer ID later, set
  SIGN_IDENTITY="Developer ID Application: …" and NOTARY_PROFILE=<profile>
before running scripts/release.sh, and first installs open without a warning.
Installed copies take that update as usual (Sparkle checks the update key,
which stays the same), then ask for their permissions once more, because the
signing identity changed.
EOF
