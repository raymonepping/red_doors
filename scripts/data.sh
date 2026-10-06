#!/usr/bin/env bash
# scripts/data.sh — PostgreSQL + Vault database engine (door 4) + door-6 ciphertext (prompt 05).
#
#   data.sh up   deploy Postgres → schema (idempotent) → vault_admin password (first run only)
#                → terraform/vault-database → rotate-root (once) → merger_docs ciphertext
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NS=rd-data
SEC="$ROOT/.secrets/data"
ROTATED="$SEC/vault-admin.rotated" # present once Vault owns vault_admin's password
mkdir -p "$SEC"
chmod 700 "$SEC"
umask 077

export VAULT_ADDR=https://vault.apps-crc.testing
export VAULT_CACERT="$ROOT/vault-tls/ca.pem"
export VAULT_NAMESPACE=red-doors

genpw() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"; }
psql_admin() { oc -n "$NS" exec -i deploy/postgres -- env PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 -d reddoors "$@"; }

cmd_up() {
  require_kubeconfig
  [ -s "$ROOT/.secrets/vault/admin-token" ] || die "no admin token — run: make tf-bootstrap"
  VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token")
  export VAULT_TOKEN

  [ -s "$SEC/admin-password" ] || genpw >"$SEC/admin-password"
  [ -s "$SEC/owner-password" ] || genpw >"$SEC/owner-password"
  oc -n "$NS" create secret generic postgres \
    --from-file=admin-password="$SEC/admin-password" --from-file=owner-password="$SEC/owner-password" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc apply -f "$ROOT/deploy/data/postgres.yaml" >/dev/null
  oc -n "$NS" rollout status deploy/postgres --timeout=300s >/dev/null
  ok "postgres ready (postgres.rd-data.svc:5432, db reddoors)"

  psql_admin <"$ROOT/deploy/data/schema.sql"
  ok "schema: payroll ($(psql_admin -tAc 'SELECT count(*) FROM payroll') rows), merger_docs, schema api, role vault_admin"

  local pw="" version=1
  if [ ! -e "$ROTATED" ]; then
    # First run (or recovery after the DB was recreated): a fresh initial
    # password Vault will rotate away immediately. Bump the write-only version
    # so Terraform actually sends it.
    pw=$(genpw 32)
    psql_admin -c "ALTER ROLE vault_admin PASSWORD '$pw';" >/dev/null
    version=$(($(cat "$SEC/vault-admin.version" 2>/dev/null || echo 0) + 1))
    echo "$version" >"$SEC/vault-admin.version"
  else
    version=$(cat "$SEC/vault-admin.version")
  fi
  "$ROOT/scripts/tf.sh" vault-database \
    -var="vault_admin_password=$pw" -var="vault_admin_password_version=$version"
  if [ ! -e "$ROTATED" ]; then
    vault write -f database/rotate-root/reddoors >/dev/null
    date -u +%FT%TZ >"$ROTATED"
    ok "vault_admin password rotated by Vault — no human knows it any more"
  else
    ok "vault_admin password owned by Vault since $(cat "$ROTATED")"
  fi

  # Door 6: ciphertext only, in PostgreSQL. Migrates the prompt-03 ConfigMap
  # (same plaintext) or, on a fresh install, encrypts a newly generated memo.
  if [ "$(psql_admin -tAc 'SELECT count(*) FROM merger_docs')" = 0 ]; then
    local title ct
    if oc -n rd-doors get configmap merger-docs >/dev/null 2>&1; then
      title=$(oc -n rd-doors get configmap merger-docs -o jsonpath='{.data.title}')
      ct=$(oc -n rd-doors get configmap merger-docs -o jsonpath='{.data.ciphertext}')
    else
      # Target, price and codename are generated: the plaintext exists only
      # inside Vault's ciphertext — not in this script, git or the cluster.
      local targets=("Halvard Systems" "Brightwater Labs" "Kestrel Analytics" "Ostrava Grid" "Marlowe Freight")
      local codenames=(Lantern Bastion Meridian Tidewater Foxglove Halcyon)
      local codename=${codenames[RANDOM % ${#codenames[@]}]}
      local memo="Project $codename — acquisition of ${targets[RANDOM % ${#targets[@]}]} at EUR $((300 + RANDOM % 600))m; announce on day one of next quarter; codename stays internal."
      title="Project $codename — merger memo"
      ct=$(vault write -field=ciphertext transit/encrypt/merger-docs plaintext="$(printf '%s' "$memo" | base64)")
    fi
    # psql only interpolates -v variables in stdin/files, not in -c commands
    printf '%s\n' "INSERT INTO merger_docs (title, ciphertext) VALUES (:'title', :'ct');" |
      psql_admin -v title="$title" -v ct="$ct" >/dev/null
    ok "merger_docs: ciphertext stored in PostgreSQL (${ct:0:12}…)"
  else
    ok "merger_docs: $(psql_admin -tAc 'SELECT count(*) FROM merger_docs') ciphertext row(s) present"
  fi
  if oc -n rd-doors get configmap merger-docs >/dev/null 2>&1; then
    oc -n rd-doors delete configmap merger-docs >/dev/null
    ok "merger-docs ConfigMap removed — PostgreSQL is now the only place the ciphertext lives"
  fi
}

case "${1:-}" in
  up) cmd_up ;;
  *)
    echo "usage: $0 up" >&2
    exit 64
    ;;
esac
