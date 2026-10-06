#!/usr/bin/env bash
# scripts/vault-admin.sh — bootstrap with root ONCE, then hand over to a
# periodic admin token. After this, root stays in .secrets/vault/cluster-init.json.
#
#   vault-admin.sh bootstrap   terraform/bootstrap (namespace red-doors, policy rd-admin) + ensure admin token
#   vault-admin.sh token       ensure .secrets/vault/admin-token is valid (re-issue if missing/expiring)
#
# Lesson (Editors Factory / vault_reference): root as a routine credential
# widens blast radius. And when the admin token is stale, re-issue it here
# deliberately — never silently fall back to root in other scripts.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

export VAULT_ADDR=https://vault.apps-crc.testing
export VAULT_CACERT="$ROOT/vault-tls/ca.pem"
INIT="$ROOT/.secrets/vault/cluster-init.json"
ADMIN="$ROOT/.secrets/vault/admin-token"
# 30 days, like the seal token: a CRC stopped over a weekend must not come
# back with an expired admin token. Re-issued when TTL < 1h.
PERIOD=720h
MIN_TTL=3600

root_token() {
  [ -s "$INIT" ] || die "no $INIT — run make vault-up first"
  jq -r '.root_token' "$INIT"
}

ensure_token() {
  local ttl=0
  if [ -s "$ADMIN" ]; then
    ttl=$(VAULT_TOKEN=$(cat "$ADMIN") vault token lookup -format=json 2>/dev/null | jq -r '.data.ttl // 0' || echo 0)
  fi
  if [ "${ttl:-0}" -ge "$MIN_TTL" ]; then
    ok "admin token valid (TTL $((ttl / 3600))h, periodic)"
    return
  fi
  [ -s "$ADMIN" ] && warn "admin token missing/expiring (TTL ${ttl:-0}s) — re-issuing with root"
  umask 077
  VAULT_TOKEN=$(root_token) vault token create -orphan -policy=rd-admin -period="$PERIOD" \
    -display-name=rd-admin -field=token >"$ADMIN.tmp"
  mv "$ADMIN.tmp" "$ADMIN"
  ok "admin token issued (orphan, periodic $PERIOD, policy rd-admin) → .secrets/vault/admin-token"
}

admin_ttl() {
  [ -s "$ADMIN" ] || {
    echo 0
    return
  }
  VAULT_TOKEN=$(cat "$ADMIN") vault token lookup -format=json 2>/dev/null | jq -r '.data.ttl // 0' || echo 0
}

# Root only when there is no usable admin token yet (first run, or after the
# admin token expired); afterwards rd-admin converges terraform/bootstrap itself.
cmd_bootstrap() {
  if [ "$(admin_ttl)" -ge "$MIN_TTL" ]; then
    VAULT_TOKEN=$(cat "$ADMIN") "$ROOT/scripts/tf.sh" bootstrap
  else
    log "no usable admin token — bootstrapping with root (once)"
    VAULT_TOKEN=$(root_token) "$ROOT/scripts/tf.sh" bootstrap
  fi
  ensure_token
}

case "${1:-}" in
  bootstrap) cmd_bootstrap ;;
  token) ensure_token ;;
  *)
    echo "usage: $0 {bootstrap|token}" >&2
    exit 64
    ;;
esac
