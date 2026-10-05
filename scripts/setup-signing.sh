#!/usr/bin/env bash
# Choose a stable code-signing identity for local builds and save it to .signing-identity.
#
# Why: macOS stores each permission grant (Microphone, Accessibility...) against the app's code
# signature. An ad-hoc signature changes on every build, so grants silently stop applying (the
# toggle stays on while the app is treated as untrusted). A stable identity keeps them.
#
# Usage:
#   scripts/setup-signing.sh                 pick an existing identity (Apple Development preferred)
#   scripts/setup-signing.sh --self-signed   create a local "Murmur Local Signing" identity first
set -euo pipefail
cd "$(dirname "$0")/.."

self_signed_name="Murmur Local Signing"

list_identities() {
  security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^ *[0-9]*) [0-9A-F]* "\(.*\)"$/\1/p'
}

create_self_signed() {
  local tmp keychain
  tmp="$(mktemp -d)"
  keychain="$HOME/Library/Keychains/login.keychain-db"
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $self_signed_name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  # /usr/bin/openssl is LibreSSL on macOS; its PKCS#12 output is what `security import` expects.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" >/dev/null 2>&1
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$self_signed_name" -passout pass:murmur -out "$tmp/identity.p12" >/dev/null 2>&1
  security import "$tmp/identity.p12" -k "$keychain" -P murmur -T /usr/bin/codesign >/dev/null
  echo "Trusting the certificate for code signing (macOS will ask for your password)…"
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$tmp/cert.pem"
  rm -rf "$tmp"
  echo "Created \"$self_signed_name\"."
}

if [ "${1:-}" = "--self-signed" ]; then
  if list_identities | grep -qx "$self_signed_name"; then
    echo "\"$self_signed_name\" already exists."
  else
    create_self_signed
  fi
fi

identities="$(list_identities)"
choice="$(printf '%s\n' "$identities" | grep -m1 '^Apple Development' || true)"
[ -n "$choice" ] || choice="$(printf '%s\n' "$identities" | grep -m1 '^Developer ID Application' || true)"
[ -n "$choice" ] || choice="$(printf '%s\n' "$identities" | grep -m1 -x "$self_signed_name" || true)"

if [ -z "$choice" ]; then
  cat <<'EOF'
No code-signing identity found. Pick one:

  A) Free Apple ID (recommended): open Xcode ▸ Settings ▸ Accounts, add your Apple ID, select the
     team, click "Manage Certificates…", then + ▸ "Apple Development". Re-run this script.

  B) No Xcode or Apple ID: run  scripts/setup-signing.sh --self-signed
     to create a local signing certificate in your login keychain.
EOF
  exit 1
fi

printf '%s\n' "$choice" > .signing-identity
echo "Using \"$choice\" (saved to .signing-identity). Keep using the same identity to keep permissions."
