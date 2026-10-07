#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 03 — cold start: both Vaults down, seal Vault comes back sealed.
# The main cluster waits (init container), then auto-unseals once an operator
# unseals the seal Vault — no main-cluster keys are used.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
"$ROOT/scripts/vault.sh" down
oc -n rd-vault wait --for=delete pod/vault-0 pod/vault-1 pod/vault-2 --timeout=120s >/dev/null 2>&1
oc -n rd-vault-seal wait --for=delete pod/vault-seal-0 --timeout=120s >/dev/null 2>&1
oc -n rd-vault-seal scale statefulset/vault-seal --replicas=1 >/dev/null
oc -n rd-vault scale statefulset/vault --replicas=3 >/dev/null
sleep 45
init=$(oc -n rd-vault get pods -l app.kubernetes.io/name=vault -o jsonpath='{range .items[*]}{.status.phase}{" "}{end}')
restarts=$(oc -n rd-vault get pods -l app.kubernetes.io/name=vault -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{" "}{end}')
check "main pods wait in Init while the seal Vault is sealed (phases: $init)" '[[ "$init" != *Running* ]]'
check "no crash loop (restarts: ${restarts:-0 0 0})" '[[ ! "$restarts" =~ [1-9] ]]'
t0=$(date +%s)
"$ROOT/scripts/vault.sh" unseal
for _ in $(seq 1 60); do [ "$(unsealed)" = 3 ] && break; sleep 2; done
check "main cluster auto-unsealed $(($(date +%s) - t0)) s after the seal Vault — no operator keys" '[ "$(unsealed)" = 3 ]'
for _ in $(seq 1 30); do [ "$(knock 1)" = opened ] && break; sleep 3; done
check "doors open again" '[ "$(knock 1)" = opened ]'
finish
