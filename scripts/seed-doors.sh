#!/usr/bin/env bash
# scripts/seed-doors.sh — write the business items behind the doors.
#
# Values are generated (realistic shape, random content) and written ONLY if
# absent, so reruns never change them. They never pass through Terraform
# state, git or logs. Door 2 and 8 items are seeded here too (their policies
# arrive in prompt 04).
#
# Door 6: a short merger memo is encrypted with transit/merger-docs and only
# the CIPHERTEXT is stored (ConfigMap rd-doors/merger-docs until prompt 05
# moves it to PostgreSQL). The plaintext is not stored anywhere.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

export VAULT_ADDR=https://vault.apps-crc.testing
export VAULT_CACERT="$ROOT/vault-tls/ca.pem"
export VAULT_NAMESPACE=red-doors
[ -s "$ROOT/.secrets/vault/admin-token" ] || die "no admin token — run: make tf-bootstrap"
VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token")
export VAULT_TOKEN

rand_hex() { openssl rand -hex "$1"; }
rand_b32() { openssl rand -base64 64 | tr -dc 'A-Z2-7' | head -c "$1"; }
CITIES=(Lisbon Gdansk Porto Tallinn Lyon)
rand_alnum() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

put_if_absent() { # <path> <key=value>…
  local path=$1
  shift
  if vault kv get -mount=doors "$path" >/dev/null 2>&1; then
    ok "doors/$path present (unchanged)"
  else
    vault kv put -mount=doors "$path" "$@" >/dev/null
    ok "doors/$path seeded"
  fi
}

put_if_absent 0-lobby \
  notice="Welcome to the corridor. Eight doors, eight ways in. Knock with the right identity." \
  posted_by="facilities"

put_if_absent 1-production-deploy-key \
  key_id="deploy-$(rand_hex 4)" \
  fingerprint="SHA256:$(openssl rand -base64 32 | tr -d '=')" \
  scope="git@git.internal:payments/platform.git (read-only)" \
  rotated="$(date -u +%F)"

put_if_absent 2-board-minutes \
  meeting_id="BRD-$(date -u +%Y)-$(rand_hex 2 | tr a-f A-F)" \
  minutes="Resolved: approve a EUR $((2 + RANDOM % 9)).$((RANDOM % 10))m budget for programme $(rand_b32 3)-$((10 + RANDOM % 90)); defer the ${CITIES[RANDOM % ${#CITIES[@]}]} office decision; next meeting in $((4 + RANDOM % 5)) weeks." \
  classification="board-only"

put_if_absent 3-partner-api-key \
  partner="Northwind Logistics" \
  api_key="pk_live_$(rand_alnum 32)" \
  rate_limit="500 req/min"

put_if_absent 5-treasury-wire-room \
  approval_code="WIRE-$(rand_b32 4)-$(rand_b32 4)-$(rand_b32 4)" \
  limit_eur="2500000" \
  valid_for="today's settlement window"

put_if_absent 7-customer-db-password \
  username="customers_app" \
  password="$(rand_alnum 28)" \
  rotated="$(date -u +%F)"

put_if_absent 8-launch-codes \
  codes="$(rand_b32 5) $(rand_b32 5) $(rand_b32 5) $(rand_b32 5)" \
  authority="two-person rule"

# ── Door 6: ciphertext only ─────────────────────────────────────────────────
require_kubeconfig
if oc -n rd-doors get configmap merger-docs >/dev/null 2>&1; then
  ok "merger-docs ciphertext present (unchanged)"
else
  # Target, price and codename are generated, so the plaintext exists only
  # inside Vault's ciphertext — not in this script, git or the cluster.
  targets=("Halvard Systems" "Brightwater Labs" "Kestrel Analytics" "Ostrava Grid" "Marlowe Freight")
  codenames=(Lantern Bastion Meridian Tidewater Foxglove Halcyon)
  target=${targets[RANDOM % ${#targets[@]}]}
  codename=${codenames[RANDOM % ${#codenames[@]}]}
  memo="Project $codename — acquisition of $target at EUR $((300 + RANDOM % 600))m; announce on day one of next quarter; codename stays internal."
  ct=$(vault write -field=ciphertext transit/encrypt/merger-docs plaintext="$(printf '%s' "$memo" | base64)")
  oc -n rd-doors create configmap merger-docs \
    --from-literal=title="Project $codename — merger memo" \
    --from-literal=ciphertext="$ct" >/dev/null
  ok "merger-docs: memo encrypted with transit/merger-docs; only ciphertext stored (${ct:0:12}…)"
fi
