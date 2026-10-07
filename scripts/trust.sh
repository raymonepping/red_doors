#!/usr/bin/env bash
# scripts/trust.sh — make the Mac (Safari/Chrome/curl via the keychain) trust
# the two CAs Red Doors uses. Asks for your password (System keychain).
#
#   trust.sh trust     OpenShift Local ingress CA (doors/keycloak) + Red Doors Project CA (Vault)
#   trust.sh untrust   remove both again
#   trust.sh status    which of them the keychain trusts
#
# vault-tls/ingress-ca.pem is a bundle whose FIRST cert is the
# *.apps-crc.testing server cert; `security add-trusted-cert` only reads the
# first cert of a file, so the CA certs are extracted first.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

KEYCHAIN=/Library/Keychains/System.keychain
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Split a PEM bundle and keep only CA certificates.
ca_certs() { # <bundle>
  awk -v dir="$TMP" '/BEGIN CERT/{n++; f=sprintf("%s/%s-%d.pem", dir, FILENAME_TAG, n)} n{print > f}' FILENAME_TAG="$(basename "$1" .pem)" "$1"
  for c in "$TMP/$(basename "$1" .pem)"-*.pem; do
    openssl x509 -in "$c" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE' && echo "$c"
  done
}

collect() {
  [ -s "$ROOT/vault-tls/ingress-ca.pem" ] || die "vault-tls/ingress-ca.pem missing — run make identity-up (or make up)"
  [ -s "$ROOT/vault-tls/ca.pem" ] || die "vault-tls/ca.pem missing — run make tls"
  ca_certs "$ROOT/vault-tls/ingress-ca.pem"
  ca_certs "$ROOT/vault-tls/ca.pem"
}

subject() { openssl x509 -in "$1" -noout -subject | sed 's/^subject= *//'; }
sha1() { openssl x509 -in "$1" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :; }
present() { security find-certificate -a -Z "$KEYCHAIN" 2>/dev/null | grep -qi "SHA-1 hash: $(sha1 "$1")"; }
# macOS's own verdict — a cert can sit in the keychain without being trusted
# (crc setup adds the ingress CA there, untrusted).
trusted() { security verify-cert -c "$1" -q >/dev/null 2>&1; }

case "${1:-trust}" in
  trust)
    while read -r c; do
      if trusted "$c"; then ok "already trusted: $(subject "$c")"; continue; fi
      log "trusting $(subject "$c") (sudo)"
      sudo security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$c"
      ok "trusted: $(subject "$c")"
    done < <(collect)
    ok "restart the browser; https://doors.apps-crc.testing and https://vault.apps-crc.testing load without warnings"
    ;;
  untrust)
    while read -r c; do
      if ! present "$c"; then ok "not in keychain: $(subject "$c")"; continue; fi
      sudo security delete-certificate -Z "$(sha1 "$c")" "$KEYCHAIN" >/dev/null
      ok "removed: $(subject "$c")"
    done < <(collect)
    ;;
  status)
    while read -r c; do
      if trusted "$c"; then ok "trusted: $(subject "$c")"
      elif present "$c"; then warn "in keychain but NOT trusted: $(subject "$c") — make trust"
      else warn "not trusted: $(subject "$c") — make trust"; fi
    done < <(collect)
    ;;
  *) die "usage: trust.sh trust|untrust|status" ;;
esac
