#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass … || bad …` is safe: pass/ok never fail
# scripts/verify-stack.sh — `make verify`: ✓/✗/⚠ for the whole estate.
# Exits non-zero on any ✗. Credentials that went bad are ✗, never "starting"
# (lesson: Arcanium's kmip-client restart-looped 17,008 times unnoticed).
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
require_kubeconfig

P=0 F=0 W=0
pass() { ok "$1"; P=$((P + 1)); }
bad() { fail "$1"; F=$((F + 1)); }
soft() { warn "$1"; W=$((W + 1)); }
section() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
export VAULT_ADDR=https://vault.apps-crc.testing VAULT_CACERT="$ROOT/vault-tls/ca.pem"
ADMIN=$(cat "$ROOT/.secrets/vault/admin-token" 2>/dev/null || true)

section "OpenShift Local"
crc_json=$(crc status -o json 2>/dev/null || echo '{}')
[ "$(jq -r '.crcStatus' <<<"$crc_json")" = Running ] && pass "CRC running (OpenShift $(jq -r .openshiftVersion <<<"$crc_json"))" || bad "CRC not running"
co=$(oc get clusteroperators --no-headers 2>/dev/null)
deg=$(awk '$5=="True"' <<<"$co" | wc -l | tr -d ' ')
unav=$(awk '$3!="True"' <<<"$co" | wc -l | tr -d ' ')
[ "$deg" = 0 ] && [ "$unav" = 0 ] && pass "cluster operators: all available, none degraded" || bad "cluster operators: $unav unavailable, $deg degraded"

section "Vault — seal chain"
seal=$(curl -fsS --cacert "$VAULT_CACERT" https://vault-seal.apps-crc.testing/v1/sys/seal-status 2>/dev/null || echo '{}')
[ "$(jq -r .sealed <<<"$seal")" = false ] && pass "seal Vault unsealed" || bad "seal Vault sealed or unreachable — make vault-unseal"
if [ -s "$ROOT/.secrets/vault/seal-init.json" ]; then
  stok=$(oc -n rd-vault get secret vault-seal-token -o jsonpath='{.data.token}' | base64 -d)
  sttl=$(VAULT_ADDR=https://vault-seal.apps-crc.testing VAULT_TOKEN=$(jq -r .root_token "$ROOT/.secrets/vault/seal-init.json") vault token lookup -format=json "$stok" 2>/dev/null | jq -r '.data.ttl // 0')
  [ "${sttl:-0}" -ge 3600 ] && pass "seal token TTL $((sttl / 3600))h (periodic, renewing)" || bad "seal token TTL ${sttl:-0}s — make vault-up re-issues it"
fi

section "Vault — main cluster"
unsealed=0 leader=""
for n in vault-0 vault-1 vault-2; do
  st=$(oc -n rd-vault exec "$n" -c vault -- vault status -format=json 2>/dev/null || true)
  if [ "$(jq -r '.sealed' <<<"$st" 2>/dev/null)" = false ]; then
    unsealed=$((unsealed + 1))
    [ "$(jq -r '.is_self' <<<"$st")" = true ] && leader=$n
  fi
done
[ "$unsealed" = 3 ] && pass "3/3 unsealed (transit), leader $leader" || bad "$unsealed/3 unsealed"
voters=$(VAULT_TOKEN=$ADMIN vault operator raft list-peers -format=json 2>/dev/null | jq '[.data.config.servers[] | select(.voter)] | length' 2>/dev/null || echo 0)
[ "$voters" = 3 ] && pass "Raft: 3 voters" || bad "Raft: $voters voters"
lic=$(curl -fsS --cacert "$VAULT_CACERT" "$VAULT_ADDR/v1/sys/health?standbyok=true" 2>/dev/null | jq -r '.license.expiry_time // empty')
if [ -n "$lic" ]; then
  days=$(( ($(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$lic" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
  [ "$days" -gt 30 ] && pass "licence valid for $days more days ($lic)" || bad "licence expires in $days days"
fi
adm_ttl=$(VAULT_TOKEN=$ADMIN vault token lookup -format=json 2>/dev/null | jq -r '.data.ttl // 0')
[ "${adm_ttl:-0}" -ge 3600 ] && pass "admin token TTL $((adm_ttl / 3600))h" || bad "admin token expiring — make vault-admin-token"
audits=$(VAULT_TOKEN=$ADMIN vault audit list -format=json 2>/dev/null | jq -r 'keys | join(" ")')
[[ $audits == *stdout/* && $audits == *red-doors-collector/* ]] && pass "audit devices: stdout + red-doors-collector" || bad "audit devices: ${audits:-none}"

section "Workloads"
for ns in rd-identity rd-data rd-doors rd-app; do
  while read -r name ready want; do
    [ -z "$name" ] && continue
    [ "${ready:-0}" = "$want" ] && pass "$ns/$name $ready/$want" || bad "$ns/$name ${ready:-0}/$want available"
  done < <(oc -n "$ns" get deploy -o jsonpath='{range .items[*]}{.metadata.name} {.status.availableReplicas} {.spec.replicas}{"\n"}{end}')
done
for d in 1 3 4 5 6 7 impostor; do
  h=$(oc -n rd-doors exec "deploy/opener-$d" -- node -e "fetch('http://127.0.0.1:8080/health').then(async r=>{process.stdout.write(r.status+' '+await r.text())})" 2>/dev/null || echo "000 {}")
  code=${h%% *}
  [ "$code" = 200 ] && pass "opener-$d /health: $(jq -r '.credential // .vault // "ok"' <<<"${h#* }" | cut -c1-70)" || bad "opener-$d /health $code: ${h#* }"
done
api_h=$(./scripts/api.sh call GET /api/v1/health 2>/dev/null || echo '{}')
[ "$(jq -r .status <<<"$api_h")" = ok ] && pass "API ok — own identity $(jq -r '.vault.policies | join(",")' <<<"$api_h"), DB login from Vault" || bad "API health: $(jq -c . <<<"$api_h" | cut -c1-120)"
[ "$(jq -r '.audit_collector.connections' <<<"$api_h")" -ge 1 ] 2>/dev/null && pass "audit collector: Vault connected, $(jq -r .audit_collector.received <<<"$api_h") records" || bad "audit collector: no connection from Vault"
vss=$(oc -n rd-doors get vaultstaticsecret door-7-customer-db -o json 2>/dev/null)
[ "$(jq -r '[.status.conditions[]? | select(.type=="SecretSynced" and .status=="True")] | length' <<<"$vss" 2>/dev/null)" -ge 1 ] 2>/dev/null \
  && pass "VSO: door-7 secret synced (generation $(jq -r .status.lastGeneration <<<"$vss"))" \
  || { oc -n rd-doors get secret door-7-customer-db >/dev/null 2>&1 && soft "VSO: Secret present, no SecretSynced condition reported" || bad "VSO: Secret door-7-customer-db missing"; }
code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$ROOT/vault-tls/ingress-ca.pem" https://doors.apps-crc.testing/login)
[ "$code" = 200 ] && pass "UI https://doors.apps-crc.testing/login → 200" || bad "UI /login → $code"

section "Doors — owner opens, wrong key refused (decided by Vault)"
for d in 1 3 4 5 6 7; do
  # machine knocks need no person: the opener's identity is what Vault evaluates
  o=$(./scripts/api.sh call POST "/api/v1/doors/$d/knock" '{"as":"owner"}' 2>/dev/null | jq -r .outcome)
  w=$(./scripts/api.sh call POST "/api/v1/doors/$d/knock" '{"as":"impostor"}' 2>/dev/null | jq -r .outcome)
  [ "$o" = opened ] && [ "$w" = denied ] && pass "door $d: owner opened, impostor denied" || bad "door $d: owner=$o impostor=$w"
done
o=$(./scripts/api.sh call POST /api/v1/doors/2/open "" ada 2>/dev/null | jq -r .outcome)
w=$(./scripts/api.sh call POST /api/v1/doors/2/open "" ben 2>/dev/null | jq -r .outcome)
[ "$o" = opened ] && [ "$w" = denied ] && pass "door 2: ada opened, ben denied" || bad "door 2: ada=$o ben=$w"
o=$(./scripts/api.sh call POST /api/v1/doors/8/requests "" cleo 2>/dev/null | jq -r .outcome)
w=$(./scripts/api.sh call POST /api/v1/doors/8/requests "" ben 2>/dev/null | jq -r .outcome)
[ "$o" = pending ] && [ "$w" = denied ] && pass "door 8: cleo's request pending (control group), ben denied" || bad "door 8: cleo=$o ben=$w"

printf '\n'
if [ "$F" -eq 0 ]; then
  printf '\033[0;32m\033[1m  ✓ All checks passed\033[0m  (%d pass, %d warn)\n' "$P" "$W"
else
  printf '\033[0;31m\033[1m  ✗ %d check(s) failed\033[0m  (%d pass, %d warn, %d fail)\n' "$F" "$P" "$W" "$F"
fi
[ "$F" -eq 0 ]
