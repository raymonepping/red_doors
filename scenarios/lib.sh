#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# scenarios/lib.sh — shared helpers for the resilience scenarios.
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/lib.sh"
require_kubeconfig
export VAULT_ADDR=https://vault.apps-crc.testing VAULT_CACERT="$ROOT/vault-tls/ca.pem"
ADMIN=$(cat "$ROOT/.secrets/vault/admin-token")
RESULT=PASS
check() { if eval "$2"; then ok "$1"; else fail "$1"; RESULT=FAIL; fi; }
knock() { "$ROOT/scripts/api.sh" call POST "/api/v1/doors/$1/knock" "{\"as\":\"${2:-owner}\"}" 2>/dev/null | jq -r '.outcome // "error"'; }
leader() { local n; for n in vault-0 vault-1 vault-2; do oc -n rd-vault exec "$n" -c vault -- vault status -format=json 2>/dev/null | jq -e '.is_self == true' >/dev/null && echo "$n" && return; done; echo none; }
unsealed() { local n c=0; for n in vault-0 vault-1 vault-2; do oc -n rd-vault exec "$n" -c vault -- vault status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null && c=$((c + 1)); done; echo "$c"; }
finish() { printf '\n\033[1m%s: %s\033[0m\n' "$(basename "$(dirname "$0")")" "$RESULT"; [ "$RESULT" = PASS ]; }
