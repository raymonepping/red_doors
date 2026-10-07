#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 06 — rotate door 7's password in Vault; VSO carries it into OpenShift.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
v1=$("$ROOT/scripts/api.sh" call POST /api/v1/doors/7/knock '{"as":"owner"}' | jq -r .released.password | shasum | cut -c1-10)
pod1=$(oc -n rd-doors get pods -l red-doors/opener=7 -o jsonpath='{.items[0].metadata.name}')
"$ROOT/scripts/vso.sh" rotate
t0=$(date +%s) v2=$v1
for _ in $(seq 1 40); do
  sleep 3
  v2=$("$ROOT/scripts/api.sh" call POST /api/v1/doors/7/knock '{"as":"owner"}' 2>/dev/null | jq -r '.released.password // empty' | shasum | cut -c1-10)
  [ -n "$v2" ] && [ "$v2" != "$v1" ] && break
done
pod2=$(oc -n rd-doors get pods -l red-doors/opener=7 --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
check "door 7 serves the new value after $(($(date +%s) - t0)) s (sha $v1 → $v2)" '[ "$v2" != "$v1" ]'
check "VSO rolled opener-7 ($pod1 → $pod2)" '[ "$pod2" != "$pod1" ]'
finish
