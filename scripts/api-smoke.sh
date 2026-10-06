#!/usr/bin/env bash
# scripts/api-smoke.sh — live smoke test of the Red Doors API (make api-smoke).
# Nothing is mocked: real openers, real Vault decisions, real OIDC sign-ins.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
require_kubeconfig

pass=0 failn=0
expect() { # <label> <jq-expression that must be true> <json>
  if jq -e "$2" >/dev/null 2>&1 <<<"$3"; then
    ok "$1"
    pass=$((pass + 1))
  else
    fail "$1"
    printf '       got: %s\n' "$(tr '\n' ' ' <<<"$3" | cut -c1-220)"
    failn=$((failn + 1))
  fi
}
call() { "$ROOT/scripts/api.sh" call "$@"; }
# Sign people in once (real OIDC chain), reuse their tokens.
declare -A TOK
for u in ada ben cleo dirk eve finn; do TOK[$u]=$("$ROOT/scripts/oidc-login.sh" "$u"); done
ucall() { # <user> <method> <path> [json]
  local user=$1 method=$2 path=$3 body=${4:-}
  oc -n rd-app exec deploy/red-doors-api -- node -e '
    const [m, p, b, t, who] = process.argv.slice(1);
    fetch("http://127.0.0.1:3001" + p, { method: m, headers: { "content-type": "application/json", "x-vault-token": t, "x-triggered-by": who }, body: b || undefined })
      .then(async r => process.stdout.write(await r.text()));' "$method" "$path" "$body" "${TOK[$user]}" "$user"
}

echo "── meta"
h=$(call GET /api/v1/health)
expect "health ok, own Vault identity rd-api, Vault-minted DB login" '.status=="ok" and (.vault.policies|index("rd-api")) and (.database.username|startswith("v-red-door-api-rw"))' "$h"
expect "audit collector listening and receiving" '.audit_collector.listening and .audit_collector.received > 0' "$h"
expect "8 doors in story order" '(.doors|length)==8 and ([.doors[].story]==[1,2,3,4,5,6,7,8])' "$(call GET /api/v1/doors)"
expect "door 4 detail carries the policy text from Vault" '.policy_texts[0].text|test("database/creds/payroll-reader")' "$(call GET /api/v1/doors/4)"
expect "door 8 detail carries the Sentinel EGP" '.egp[0].text|test("controlgroup")' "$(call GET /api/v1/doors/8)"

echo "── machine doors: owner opens, impostor is refused by Vault"
last4=""
for d in 1 3 4 5 6 7; do
  r=$(call POST "/api/v1/doors/$d/knock" '{"as":"owner"}')
  expect "door $d owner → opened" '.outcome=="opened" and .released != null and .attempt_id' "$r"
  [ "$d" = 4 ] && last4=$(jq -r .attempt_id <<<"$r")
  w=$(call POST "/api/v1/doors/$d/knock" '{"as":"impostor"}')
  expect "door $d impostor → denied (${d/7/no Secret mounted})" '.outcome=="denied" and .released==null' "$w"
done
expect "door 3 orchestration: wrapped by the API, never unwrapped by it" '.orchestration.wrapped_by.creation_path=="auth/approle/role/door-3/secret-id"' "$(call POST /api/v1/doors/3/knock '{"as":"owner"}')"
sleep 2
expect "door 4 attempt joins Vault audit entries by request id" '(.audit|length) >= 2 and (.audit|map(.path)|index("database/creds/payroll-reader"))' "$(call GET "/api/v1/attempts/$last4")"
expect "attempts never store released values" 'has("released")|not' "$(call GET "/api/v1/attempts/$last4")"
expect "human door refused for machines" '.code=="not_a_machine_door"' "$(call POST /api/v1/doors/2/knock '{"as":"owner"}')"

echo "── door 2: people"
expect "ada (board) opens the board minutes" '.outcome=="opened" and (.identity.groups|index("board"))' "$(ucall ada POST /api/v1/doors/2/open)"
expect "ben (staff) refused by Vault" '.outcome=="denied" and .denial.status==403' "$(ucall ben POST /api/v1/doors/2/open)"

echo "── door 8: two different people"
r=$(ucall cleo POST /api/v1/doors/8/requests)
expect "cleo requests → pending, wrapping token returned to her session only" '.outcome=="pending" and (.wrapping_token|startswith("hvs.")) and .accessor' "$r"
acc=$(jq -r .accessor <<<"$r") wrap=$(jq -r .wrapping_token <<<"$r")
expect "cleo opens before approval → refused" '.outcome=="denied"' "$(ucall cleo POST "/api/v1/doors/8/requests/$acc/open" "{\"wrapping_token\":\"$wrap\"}")"
expect "dirk (approver) sees cleo's pending request" "[.requests[] | select(.accessor==\"$acc\")][0].vault.approved==false" "$(ucall dirk GET /api/v1/doors/8/requests)"
expect "ben (staff) cannot approve" '.outcome=="denied"' "$(ucall ben POST "/api/v1/doors/8/requests/$acc/approve")"
expect "finn (auditor) cannot approve" '.outcome=="denied"' "$(ucall finn POST "/api/v1/doors/8/requests/$acc/approve")"
expect "dirk approves" '.approved==true and .self_approval==false' "$(ucall dirk POST "/api/v1/doors/8/requests/$acc/approve")"
expect "cleo opens → launch codes" '.outcome=="opened" and .released.codes' "$(ucall cleo POST "/api/v1/doors/8/requests/$acc/open" "{\"wrapping_token\":\"$wrap\"}")"
r=$(ucall eve POST /api/v1/doors/8/requests)
acc=$(jq -r .accessor <<<"$r") wrap=$(jq -r .wrapping_token <<<"$r")
expect "eve approves her own request → recorded, NOT counted (Sentinel EGP)" '.outcome=="not_counted" and .approved==false and .self_approval==true' "$(ucall eve POST "/api/v1/doors/8/requests/$acc/approve")"
expect "eve opens after self-approval → refused" '.outcome=="denied"' "$(ucall eve POST "/api/v1/doors/8/requests/$acc/open" "{\"wrapping_token\":\"$wrap\"}")"
expect "dirk approves eve's request" '.approved==true' "$(ucall dirk POST "/api/v1/doors/8/requests/$acc/approve")"
expect "eve opens after a DIFFERENT person approved → launch codes" '.outcome=="opened"' "$(ucall eve POST "/api/v1/doors/8/requests/$acc/open" "{\"wrapping_token\":\"$wrap\"}")"

echo "── platform"
c=$(call GET /api/v1/cluster)
expect "cluster: 3/3 unsealed, one leader, seal Vault unsealed" '.vault.unsealed==3 and .vault.leader != null and .seal_chain.seal_vault.sealed==false' "$c"
expect "cluster: licence expiry visible (unauthenticated sys/health)" '.vault.license_expiry != null' "$c"
expect "cluster: VSO door-7 sync status" '.vso_door_7.path=="doors/7-customer-db-password"' "$c"
expect "audit feed has door-tagged entries" '[.entries[] | select(.door != null)] | length > 0' "$(call GET '/api/v1/audit?limit=100')"

echo "── rd-api cannot read anything behind a door"
export VAULT_ADDR=https://vault.apps-crc.testing VAULT_CACERT="$ROOT/vault-tls/ca.pem" VAULT_NAMESPACE=red-doors
t=$(VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token") vault token create -policy=rd-api -ttl=2m -orphan -field=token)
caps=$(for p in doors/data/1-production-deploy-key doors/data/3-partner-api-key doors/data/5-treasury-wire-room doors/data/8-launch-codes database/creds/payroll-reader transit/decrypt/merger-docs pki-int/issue/treasury-client; do printf '%s=%s ' "$p" "$(VAULT_TOKEN=$t vault token capabilities "$p")"; done)
VAULT_TOKEN=$t vault token revoke -self >/dev/null
denies=$(tr ' ' '\n' <<<"$caps" | grep -c '=deny$')
expect "rd-api capabilities on all 7 door paths = deny" '. == 7' "$denies"
printf '       %s\n' "$caps"

echo
echo "RESULT: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
