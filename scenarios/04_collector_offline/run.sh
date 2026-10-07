#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 04 — the audit collector (API) goes offline; Vault keeps serving.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
oc -n rd-app scale deploy/red-doors-api --replicas=0 >/dev/null
oc -n rd-app wait --for=delete pod -l app=red-doors-api --timeout=90s >/dev/null 2>&1
t0=$(python3 -c 'import time;print(time.time())')
check "Vault served a read with the collector down (stdout audit device)" 'VAULT_NAMESPACE=red-doors VAULT_TOKEN=$ADMIN vault kv get -mount=doors -field=posted_by 0-lobby >/dev/null'
log "read took $(python3 -c "import time;print(round(time.time()-$t0,2))") s — the UI's Audit page shows the gap"
oc -n rd-app scale deploy/red-doors-api --replicas=1 >/dev/null
oc -n rd-app rollout status deploy/red-doors-api --timeout=180s >/dev/null
sleep 6
VAULT_NAMESPACE=red-doors VAULT_TOKEN=$ADMIN vault kv get -mount=doors 0-lobby >/dev/null 2>&1
sleep 3
h=$("$ROOT/scripts/api.sh" call GET /api/v1/health)
check "collector back: Vault reconnected by itself ($(jq -r .audit_collector.received <<<"$h") records)" '[ "$(jq -r .audit_collector.connections <<<"$h")" -ge 1 ] && [ "$(jq -r .audit_collector.received <<<"$h")" -ge 1 ]'
finish
