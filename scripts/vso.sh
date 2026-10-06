#!/usr/bin/env bash
# scripts/vso.sh — Vault Secrets Operator for door 7 (prompt 05).
#
#   vso.sh up       subscribe (OperatorHub, certified) → wait for the CSV → VaultConnection/VaultAuth/VaultStaticSecret
#   vso.sh rotate   write a new customer-DB password in Vault; VSO syncs it within ~30s
#   vso.sh status   VaultStaticSecret status + the synced Secret's metadata (never its data)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

cmd_up() {
  require_kubeconfig
  oc apply -f "$ROOT/deploy/base/vso-subscription.yaml" >/dev/null
  local csv="" phase=""
  for _ in $(seq 1 90); do
    csv=$(oc -n openshift-operators get subscription vault-secrets-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
    [ -n "$csv" ] && phase=$(oc -n openshift-operators get csv "$csv" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "$phase" = Succeeded ] && break
    sleep 4
  done
  [ "$phase" = Succeeded ] || die "VSO CSV not Succeeded (csv=${csv:-none}, phase=${phase:-none}) — check: oc -n openshift-operators get csv"
  ok "Vault Secrets Operator: $csv Succeeded (OperatorHub, certified)"

  # VSO wants the CA as a Secret (not a ConfigMap)
  oc -n rd-doors create secret generic red-doors-ca --from-file=ca.crt="$ROOT/vault-tls/ca.pem" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc apply -f "$ROOT/deploy/doors/vso.yaml" >/dev/null
  for _ in $(seq 1 60); do
    oc -n rd-doors get secret door-7-customer-db >/dev/null 2>&1 && break
    sleep 2
  done
  oc -n rd-doors get secret door-7-customer-db >/dev/null 2>&1 || die "VSO did not create Secret door-7-customer-db — see: oc -n rd-doors describe vaultstaticsecret door-7-customer-db"
  ok "VSO synced doors/7-customer-db-password → Secret rd-doors/door-7-customer-db"
}

cmd_rotate() {
  export VAULT_ADDR=https://vault.apps-crc.testing VAULT_CACERT="$ROOT/vault-tls/ca.pem" VAULT_NAMESPACE=red-doors
  VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token")
  export VAULT_TOKEN
  vault kv patch -mount=doors 7-customer-db-password \
    password="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 28)" rotated="$(date -u +%FT%TZ)" >/dev/null
  ok "door 7: new customer-DB password written in Vault (v$(vault kv metadata get -mount=doors -format=json 7-customer-db-password | jq -r .data.current_version)); VSO syncs within ~30s"
}

cmd_status() {
  require_kubeconfig
  oc -n rd-doors get vaultstaticsecret door-7-customer-db -o json |
    jq -r '"VaultStaticSecret: lastGeneration=\(.status.lastGeneration // "-"), secretMAC=\((.status.secretMAC // "-")[0:12])…"'
  oc -n rd-doors get secret door-7-customer-db -o json |
    jq -r '"Secret door-7-customer-db: keys=\(.data | keys | join(",")), resourceVersion=\(.metadata.resourceVersion)"'
}

case "${1:-}" in
  up) cmd_up ;;
  rotate) cmd_rotate ;;
  status) cmd_status ;;
  *)
    echo "usage: $0 {up|rotate|status}" >&2
    exit 64
    ;;
esac
