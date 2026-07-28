#!/bin/bash
# Creates a STABLE self-signed code-signing identity for FriendList so the
# Full Disk Access grant (keyed on the code signature) survives rebuilds.
#
# Ad-hoc signing (CODE_SIGN_IDENTITY = "-") mints a new cdhash every build, so
# TCC treats each rebuild as a new app and drops FDA. A stable identity fixes it.
#
# Uses a DEDICATED keychain with a known password ("friendlist") so it never
# needs your login-keychain password and never prompts. Idempotent.
set -euo pipefail

IDENTITY="FriendList Dev"
KC_NAME="friendlist-signing"
KC_PASS="friendlist"
KC_PATH="$HOME/Library/Keychains/${KC_NAME}.keychain-db"

# NOTE: no -v here. This self-signed cert is untrusted, so `find-identity -v`
# reports "0 valid identities" and the name never matches — which made this
# script delete+recreate the keychain on EVERY run, breaking any open Xcode's
# cached keychain handle mid-build. codesign accepts the identity by name
# regardless of trust, so match on presence, not validity.
if security find-identity -p codesigning "$KC_PATH" 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✓ Signing identity '$IDENTITY' already exists in $KC_NAME."
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  cat > "$TMP/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

  # Use macOS system LibreSSL — it writes an Apple-readable PKCS12. Homebrew
  # OpenSSL 3 defaults to a SHA-256 MAC that `security import` rejects
  # ("MAC verification failed").
  SSL=/usr/bin/openssl
  "$SSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.conf" >/dev/null 2>&1
  "$SSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:"$KC_PASS" -name "$IDENTITY" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1

  # Fresh dedicated keychain (recreate cleanly if partially set up).
  security delete-keychain "$KC_PATH" 2>/dev/null || true
  security create-keychain -p "$KC_PASS" "$KC_PATH"
  security set-keychain-settings "$KC_PATH"                 # no auto-lock timeout
  security unlock-keychain -p "$KC_PASS" "$KC_PATH"
  security import "$TMP/id.p12" -k "$KC_PATH" -P "$KC_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security
  # Allow codesign to use the private key without an interactive prompt.
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KC_PASS" "$KC_PATH" >/dev/null 2>&1
  echo "✓ Created signing identity '$IDENTITY' in $KC_NAME."
fi

# Ensure the keychain is in the user search list and unlocked for the build.
EXISTING="$(security list-keychains -d user | sed 's/[",]//g' | xargs)"
if ! echo "$EXISTING" | grep -q "$KC_NAME"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s $EXISTING "$KC_PATH"
fi
security unlock-keychain -p "$KC_PASS" "$KC_PATH"

echo
echo "Done. project.yml is set to sign with '$IDENTITY'."
echo "If the keychain ever locks, rerun: security unlock-keychain -p $KC_PASS \"$KC_PATH\""
