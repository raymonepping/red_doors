#!/usr/bin/env bash
# scripts/tls.sh — project CA + Vault server certificates, loaded into the cluster.
#
# Idempotent:
#   - creates the CA once (10 years), key in .secrets/tls/ca.key
#   - (re)issues a server cert when it is missing, expires within 30 days,
#     isn't signed by the current CA, or lacks a required SAN
#   - applies Secrets vault-tls (rd-vault) / vault-seal-tls (rd-vault-seal)
#     and ConfigMap red-doors-ca (every rd-* namespace)
#
# Lesson (Arcanium kmip-client): certificates expire. This script is their
# owner; `make up` runs it every time.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

KEYS="$ROOT/.secrets/tls"
PUB="$ROOT/vault-tls"
RENEW_WITHIN=$((30 * 86400))
mkdir -p "$KEYS" "$PUB"
chmod 700 "$KEYS"
umask 077

ensure_ca() {
  if [ -s "$KEYS/ca.key" ] && [ -s "$PUB/ca.pem" ] && openssl x509 -checkend "$RENEW_WITHIN" -noout -in "$PUB/ca.pem" >/dev/null; then
    ok "CA valid until $(openssl x509 -enddate -noout -in "$PUB/ca.pem" | cut -d= -f2)"
    return
  fi
  log "creating project CA"
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
    -subj "/O=Red Doors/CN=Red Doors Project CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$KEYS/ca.key" -out "$PUB/ca.pem" 2>/dev/null
  chmod 644 "$PUB/ca.pem"
  ok "CA created"
}

# issue <name> <CN> <SAN,…>
issue() {
  local name=$1 cn=$2 sans=$3 crt="$PUB/$1.crt" key="$KEYS/$1.key" missing=""
  if [ -s "$crt" ] && [ -s "$key" ]; then
    local text
    text=$(openssl x509 -noout -text -in "$crt")
    for san in ${sans//,/ }; do
      grep -qF "${san/IP:/IP Address:}" <<<"$text" || missing="$missing $san"
    done
    if [ -z "$missing" ] &&
      openssl x509 -checkend "$RENEW_WITHIN" -noout -in "$crt" >/dev/null &&
      openssl verify -CAfile "$PUB/ca.pem" "$crt" >/dev/null 2>&1; then
      ok "$name cert valid until $(openssl x509 -enddate -noout -in "$crt" | cut -d= -f2)"
      return
    fi
  fi
  log "issuing $name certificate${missing:+ (missing SANs:$missing)}"
  local ext
  ext=$(mktemp)
  cat >"$ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=$sans
EOF
  openssl req -new -newkey rsa:3072 -nodes -sha256 -subj "/O=Red Doors/CN=$cn" \
    -keyout "$key" -out "$KEYS/$name.csr" 2>/dev/null
  openssl x509 -req -sha256 -days 365 -in "$KEYS/$name.csr" \
    -CA "$PUB/ca.pem" -CAkey "$KEYS/ca.key" -CAcreateserial -CAserial "$KEYS/ca.srl" \
    -extfile "$ext" -out "$crt" 2>/dev/null
  rm -f "$ext" "$KEYS/$name.csr"
  chmod 644 "$crt"
  ok "$name cert issued (365 days)"
}

apply_secret() { # <namespace> <secret> <cert-name>
  oc -n "$1" create secret generic "$2" \
    --from-file=tls.crt="$PUB/$3.crt" --from-file=tls.key="$KEYS/$3.key" --from-file=ca.crt="$PUB/ca.pem" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "Secret $1/$2"
}

require_kubeconfig
ensure_ca

# Main cluster: release `vault` in rd-vault → services vault, vault-active,
# vault-standby, headless vault-internal (pods vault-N.vault-internal).
issue vault "vault.rd-vault.svc" \
  "DNS:vault,DNS:vault.rd-vault,DNS:vault.rd-vault.svc,DNS:vault.rd-vault.svc.cluster.local,DNS:vault-active,DNS:vault-active.rd-vault.svc,DNS:vault-active.rd-vault.svc.cluster.local,DNS:vault-standby.rd-vault.svc,DNS:vault-internal,DNS:*.vault-internal,DNS:*.vault-internal.rd-vault.svc,DNS:*.vault-internal.rd-vault.svc.cluster.local,DNS:vault.apps-crc.testing,DNS:localhost,IP:127.0.0.1"

# Seal Vault: release `vault-seal` in rd-vault-seal.
issue vault-seal "vault-seal.rd-vault-seal.svc" \
  "DNS:vault-seal,DNS:vault-seal.rd-vault-seal,DNS:vault-seal.rd-vault-seal.svc,DNS:vault-seal.rd-vault-seal.svc.cluster.local,DNS:vault-seal-internal,DNS:*.vault-seal-internal,DNS:*.vault-seal-internal.rd-vault-seal.svc,DNS:*.vault-seal-internal.rd-vault-seal.svc.cluster.local,DNS:vault-seal.apps-crc.testing,DNS:localhost,IP:127.0.0.1"

apply_secret rd-vault vault-tls vault
apply_secret rd-vault-seal vault-seal-tls vault-seal

for ns in "${RD_NAMESPACES[@]}"; do
  oc -n "$ns" create configmap red-doors-ca --from-file=ca.crt="$PUB/ca.pem" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
done
ok "ConfigMap red-doors-ca in ${#RD_NAMESPACES[@]} namespaces"
