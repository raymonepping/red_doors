#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 01 — kill the active Vault pod mid-demo; doors keep opening.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
before=$(leader)
log "leader before: $before — watch the Cluster page; knocking on door 1 every second"
log_file=$(mktemp)
( for _ in $(seq 1 40); do echo "$(date +%s) $(knock 1)" >>"$log_file"; sleep 1; done ) &
knocker=$!
sleep 4
oc -n rd-vault delete pod "$before" --wait=false >/dev/null
log "deleted $before"
wait "$knocker"
after=$(leader)
opened=$(grep -c ' opened$' "$log_file"); other=$(grep -vc ' opened$' "$log_file")
check "leadership moved ($before → $after)" '[ "$after" != "$before" ] && [ "$after" != none ]'
check "door 1 kept opening: $opened opened, $other not opened during failover" '[ "$opened" -ge 30 ]'
for _ in $(seq 1 60); do [ "$(unsealed)" = 3 ] && break; sleep 3; done
check "$before rejoined unsealed (3/3)" '[ "$(unsealed)" = 3 ]'
rm -f "$log_file"
finish
