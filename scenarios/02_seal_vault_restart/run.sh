#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 02 — the seal Vault restarts and comes back SEALED; the main cluster keeps serving.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
oc -n rd-vault-seal delete pod vault-seal-0 --wait=true >/dev/null
for _ in $(seq 1 40); do st=$(curl -fsS --cacert "$VAULT_CACERT" https://vault-seal.apps-crc.testing/v1/sys/seal-status 2>/dev/null) && break; sleep 3; done
check "seal Vault came back sealed (Cluster page shows it)" '[ "$(jq -r .sealed <<<"$st")" = true ]'
check "main cluster still 3/3 unsealed" '[ "$(unsealed)" = 3 ]'
check "door 1 still opens while the seal Vault is sealed" '[ "$(knock 1)" = opened ]'
"$ROOT/scripts/vault.sh" unseal
check "seal Vault unsealed again (make vault-unseal)" '[ "$(curl -fsS --cacert "$VAULT_CACERT" https://vault-seal.apps-crc.testing/v1/sys/seal-status | jq -r .sealed)" = false ]'
finish
