#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # variables are read inside check expressions (eval)
# Scenario 05 — short-lived authority really ends (each shown from Vault's own answer).
#   --long  also wait out a door-8 control-group request (10 minutes)
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
export VAULT_NAMESPACE=red-doors
tmp=$(mktemp -d)

# door 3: a wrapped secret-id whose wrapping TTL has passed
w=$(VAULT_TOKEN=$ADMIN vault write -wrap-ttl=5s -f -field=wrapping_token auth/approle/role/door-3/secret-id)
sleep 7
check "door 3: unwrap after the wrapping TTL → refused" '! VAULT_TOKEN=$w vault unwrap >/dev/null 2>&1'

# door 5: a genuine Treasury certificate past its not-after (cert login through the passthrough Route)
VAULT_TOKEN=$ADMIN vault write -format=json pki-int/issue/treasury-client common_name=opener-5.rd-doors ttl=5s >"$tmp/c.json"
jq -r .data.certificate "$tmp/c.json" >"$tmp/c.pem"; jq -r .data.private_key "$tmp/c.json" >"$tmp/k.pem"
sleep 7
out=$(vault login -no-store -method=cert -client-cert="$tmp/c.pem" -client-key="$tmp/k.pem" name=treasury 2>&1)
check "door 5: expired client certificate → refused ($(grep -o 'certificate has expired' <<<"$out" | head -1))" 'grep -q "expired" <<<"$out"'

# door 4: a minted login is gone after its lease is revoked
creds=$(VAULT_TOKEN=$ADMIN vault read -format=json database/creds/payroll-reader)
u=$(jq -r .data.username <<<"$creds"); p=$(jq -r .data.password <<<"$creds")
VAULT_TOKEN=$ADMIN vault lease revoke "$(jq -r .lease_id <<<"$creds")" >/dev/null
check "door 4: revoked database login can no longer connect" '! oc -n rd-data exec deploy/postgres -- env PGPASSWORD="$p" psql -X -h postgres.rd-data.svc -U "$u" -d reddoors -tAc "SELECT 1" >/dev/null 2>&1'

if [ "${1:-}" = --long ]; then
  acc=$("$ROOT/scripts/api.sh" call POST /api/v1/doors/8/requests "" cleo | jq -r .accessor)
  log "door 8: waiting 10 minutes for request $acc to expire unapproved…"
  sleep 610
  check "door 8: unapproved request expired" '"$ROOT/scripts/api.sh" call GET /api/v1/doors/8/requests "" cleo | jq -e --arg a "$acc" ".requests[] | select(.accessor==\$a) | .expired" >/dev/null'
else
  log "door 8: skipped (control-group TTL is 10 minutes) — rerun with --long"
fi
rm -rf "$tmp"
finish
