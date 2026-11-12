#!/bin/bash
# Creates a stable, self-signed code-signing identity for SwitchDeck.
#
# Why: an ad-hoc signature identifies the app by its CDHash, which changes on
# every build. macOS ties Accessibility/Automation grants to that identity, so
# every rebuild looks like a brand new app and asks for permission again.
# A certificate-based signature keeps the same designated requirement across
# rebuilds, so the grant survives.
#
# Run once per machine. `scripts/build-app.sh` picks the identity up
# automatically when it exists.
set -euo pipefail

NAME="SwitchDeck Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identity already present: $NAME"
  exit 0
fi

echo "==> Creating certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

echo "==> Importing into the login keychain"
# macOS cannot read OpenSSL 3+ PKCS#12 defaults; ask for the legacy ciphers.
openssl pkcs12 -export -out "$TMP/cert.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:switchdeck \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P switchdeck -T /usr/bin/codesign -A

echo "==> Trusting it for code signing (user trust domain)"
security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "$NAME"
echo "Done. Rebuild with scripts/build-app.sh."
