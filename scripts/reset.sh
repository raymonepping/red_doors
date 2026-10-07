#!/usr/bin/env bash
# scripts/reset.sh — `make reset`: DESTRUCTIVE. Deletes every Red Doors namespace
# (all PVCs: Vault data, LDAP, Keycloak, PostgreSQL), the VSO subscription and
# the local state that belongs to it. CRC itself is kept.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
require_kubeconfig
printf 'This deletes ALL Red Doors data: both Vaults (keys included), LDAP, Keycloak, PostgreSQL,\nTerraform state and generated credentials under .secrets/ (the pull secret is kept).\n'
read -r -p "Type 'red-doors' to confirm: " answer
[ "$answer" = red-doors ] || die "aborted"
for ns in "${RD_NAMESPACES[@]}"; do oc delete namespace "$ns" --ignore-not-found --wait=false >/dev/null; done
oc -n openshift-operators delete subscription vault-secrets-operator --ignore-not-found >/dev/null
csv=$(oc -n openshift-operators get csv -o name 2>/dev/null | grep vault-secrets-operator || true)
[ -n "$csv" ] && oc -n openshift-operators delete "$csv" >/dev/null
rm -rf "$ROOT/.secrets/vault" "$ROOT/.secrets/terraform" "$ROOT/.secrets/identity" "$ROOT/.secrets/data" "$ROOT/.secrets/tls" "$ROOT/vault-tls"/*.pem "$ROOT/vault-tls"/*.crt
ok "reset done — make up rebuilds from zero"
