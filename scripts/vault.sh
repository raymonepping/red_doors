#!/usr/bin/env bash
# scripts/vault.sh — seal Vault + main Vault Enterprise cluster (prompt 02).
#
#   vault.sh up                 idempotent bootstrap of the whole unseal chain
#   vault.sh unseal             unseal the seal Vault (the main cluster unseals itself)
#   vault.sh status             both Vaults, Raft peers, seal token, licence
#   vault.sh seal-token-status  TTL/renewal of the transit seal token
#   vault.sh roll               rolling restart (standbys first, leader last) — applies config changes
#   vault.sh down               scale both StatefulSets to 0 (PVCs are kept)
#   vault.sh ui                 open the main Vault UI
#
# Trust chain:
#   .secrets/vault/seal-init.json (Shamir, 1 share — local POC like Arcanium's vault-s)
#     → vault-seal-0 (rd-vault-seal): transit key `autounseal`
#       → periodic orphan token (policy autounseal) in Secret rd-vault/vault-seal-token
#         → vault-0/1/2 (rd-vault): seal "transit", auto-unseal, Raft HA
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

CHART=hashicorp/vault
CHART_VERSION=0.34.1
SEAL_NS=rd-vault-seal
MAIN_NS=rd-vault
SEAL_ADDR=https://vault-seal.apps-crc.testing
MAIN_ADDR=https://vault.apps-crc.testing
CA="$ROOT/vault-tls/ca.pem"
STATE="$ROOT/.secrets/vault"
SEAL_INIT="$STATE/seal-init.json"
MAIN_INIT="$STATE/cluster-init.json"
LICENSE="$ROOT/lics/vault.hclic"
# 30 days. Vault renews the seal token while the cluster runs; a CRC left
# stopped longer than the period would come back unable to unseal. `up`
# re-issues the token whenever its TTL is under SEAL_TOKEN_MIN_TTL.
SEAL_TOKEN_PERIOD=720h
SEAL_TOKEN_MIN_TTL=3600

mkdir -p "$STATE"
chmod 700 "$STATE"

seal_vault() { VAULT_ADDR=$SEAL_ADDR VAULT_CACERT=$CA VAULT_TOKEN=${SEAL_ROOT:-} vault "$@"; }
main_vault() { VAULT_ADDR=$MAIN_ADDR VAULT_CACERT=$CA VAULT_TOKEN=${MAIN_ROOT:-} vault "$@"; }
# `vault status` exits 2 when sealed — that is information, not failure.
status_json() { "$@" status -format=json 2>/dev/null || true; }
pod_status_json() { oc -n "$1" exec "$2" -c vault -- vault status -format=json 2>/dev/null || true; }

wait_for() { # <description> <timeout-seconds> <command…>
  local what=$1 timeout=$2 i=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    i=$((i + 2))
    [ "$i" -lt "$timeout" ] || die "timed out after ${timeout}s waiting for: $what"
    sleep 2
  done
}

pod_running() { [ "$(oc -n "$1" get pod "$2" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }
route_up() { curl -s -o /dev/null --cacert "$CA" -m 3 "$1/v1/sys/seal-status"; }

apply_license() {
  [ -s "$LICENSE" ] || die "licence missing: $LICENSE (copy ../arcanium/lics/vault_v21_ENT.hclic there)"
  local ns
  for ns in "$SEAL_NS" "$MAIN_NS"; do
    oc -n "$ns" create secret generic vault-license --from-file=license="$LICENSE" \
      --dry-run=client -o yaml | oc apply -f - >/dev/null
  done
  ok "Secret vault-license in $SEAL_NS, $MAIN_NS"
}

helm_install() { # <release> <namespace>
  helm upgrade --install "$1" "$CHART" --version "$CHART_VERSION" -n "$2" \
    -f "$ROOT/deploy/$1/values.yaml" --wait --timeout 5m >/dev/null 2>&1 ||
    die "helm upgrade $1 failed — run: helm -n $2 status $1"
  ok "helm release $1: revision $(helm -n "$2" history "$1" --max 1 -o json 2>/dev/null | jq -r '.[0].revision')"
}

# ── seal Vault ──────────────────────────────────────────────────────────────
seal_up() {
  log "seal Vault (release vault-seal, $SEAL_NS)"
  helm_install vault-seal "$SEAL_NS"
  wait_for "vault-seal-0 Running" 180 pod_running "$SEAL_NS" vault-seal-0
  wait_for "Route $SEAL_ADDR" 120 route_up "$SEAL_ADDR"

  local st
  st=$(status_json seal_vault)
  if [ "$(jq -r '.initialized' <<<"$st")" != true ]; then
    log "initialising seal Vault (1 Shamir share — local POC)"
    umask 077
    seal_vault operator init -key-shares=1 -key-threshold=1 -format=json >"$SEAL_INIT.tmp"
    mv "$SEAL_INIT.tmp" "$SEAL_INIT"
    ok "seal Vault initialised → .secrets/vault/seal-init.json"
  fi
  seal_unseal
  SEAL_ROOT=$(jq -r '.root_token' "$SEAL_INIT")

  # stdout audit first, so nothing below goes unaudited
  if ! seal_vault audit list -format=json 2>/dev/null | jq -e 'has("stdout/")' >/dev/null; then
    seal_vault audit enable -path=stdout file file_path=stdout >/dev/null
    ok "seal Vault: file audit device → stdout"
  fi
  if ! seal_vault secrets list -format=json | jq -e 'has("transit/")' >/dev/null; then
    seal_vault secrets enable transit >/dev/null
  fi
  if ! seal_vault read -format=json transit/keys/autounseal >/dev/null 2>&1; then
    seal_vault write -f transit/keys/autounseal >/dev/null
    ok "seal Vault: transit key autounseal created"
  fi
  seal_vault policy write autounseal - >/dev/null <<'EOF'
# Lets the main Vault cluster wrap/unwrap its root key with transit/autounseal — nothing else.
path "transit/encrypt/autounseal" {
  capabilities = ["update"]
}
path "transit/decrypt/autounseal" {
  capabilities = ["update"]
}
EOF
  ok "seal Vault: transit/autounseal + policy autounseal"
  ensure_seal_token
}

seal_unseal() {
  [ -s "$SEAL_INIT" ] || die "no $SEAL_INIT — the seal Vault was initialised elsewhere; restore that file"
  if [ "$(status_json seal_vault | jq -r '.sealed')" = true ]; then
    seal_vault operator unseal "$(jq -r '.unseal_keys_b64[0]' "$SEAL_INIT")" >/dev/null
    ok "seal Vault unsealed"
  else
    ok "seal Vault already unsealed"
  fi
}

# Lesson (Arcanium / vault_reference): an expiring transit seal token makes
# main nodes fail to unseal days later and looks like a health-check flake.
ensure_seal_token() {
  local current ttl
  current=$(oc -n "$MAIN_NS" get secret vault-seal-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [ -n "$current" ]; then
    ttl=$(seal_vault token lookup -format=json "$current" 2>/dev/null | jq -r '.data.ttl // 0' || echo 0)
    if [ "${ttl:-0}" -ge "$SEAL_TOKEN_MIN_TTL" ]; then
      ok "seal token valid (TTL $((ttl / 3600))h, periodic — Vault renews it)"
      return
    fi
    warn "seal token missing/expiring (TTL ${ttl:-0}s) — issuing a new one"
  fi
  local token
  token=$(seal_vault token create -orphan -policy=autounseal -period="$SEAL_TOKEN_PERIOD" \
    -display-name=rd-vault-autounseal -format=json | jq -r '.auth.client_token')
  oc -n "$MAIN_NS" create secret generic vault-seal-token --from-literal=token="$token" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "seal token issued (orphan, periodic $SEAL_TOKEN_PERIOD) → Secret $MAIN_NS/vault-seal-token"
  # Running main pods read VAULT_TOKEN at start; restart them onto the new token.
  if oc -n "$MAIN_NS" get statefulset vault >/dev/null 2>&1; then
    oc -n "$MAIN_NS" rollout restart statefulset/vault >/dev/null
    warn "restarted the main cluster onto the new seal token"
  fi
}

# ── main cluster ────────────────────────────────────────────────────────────
main_up() {
  log "main cluster (release vault, $MAIN_NS)"
  # Helm --wait would block on unready pods before init; readiness accepts
  # sealed/uninit (204), so pods are Ready once the process is up.
  helm_install vault "$MAIN_NS"
  wait_for "vault-0 Running" 300 pod_running "$MAIN_NS" vault-0

  local st
  st=$(pod_status_json "$MAIN_NS" vault-0)
  if [ "$(jq -r '.initialized' <<<"$st")" != true ]; then
    log "initialising main cluster (auto-unseal → recovery key, 1 share — local POC)"
    umask 077
    oc -n "$MAIN_NS" exec vault-0 -c vault -- vault operator init \
      -recovery-shares=1 -recovery-threshold=1 -format=json >"$MAIN_INIT.tmp"
    mv "$MAIN_INIT.tmp" "$MAIN_INIT"
    ok "main cluster initialised → .secrets/vault/cluster-init.json"
  fi
  MAIN_ROOT=$(jq -r '.root_token' "$MAIN_INIT")

  local p
  for p in vault-0 vault-1 vault-2; do
    wait_for "$p Running" 300 pod_running "$MAIN_NS" "$p"
    wait_for "$p unsealed (transit)" 300 bash -c \
      "oc -n $MAIN_NS exec $p -c vault -- vault status -format=json 2>/dev/null | jq -e '.sealed == false and .initialized == true'"
    ok "$p unsealed"
  done
  wait_for "Route $MAIN_ADDR (active node)" 180 route_up "$MAIN_ADDR"

  if ! main_vault audit list -format=json 2>/dev/null | jq -e 'has("stdout/")' >/dev/null; then
    main_vault audit enable -path=stdout file file_path=stdout >/dev/null
    ok "main cluster: file audit device → stdout"
  fi
  wait_for "3 Raft voters" 180 bash -c \
    "VAULT_ADDR=$MAIN_ADDR VAULT_CACERT=$CA VAULT_TOKEN=$MAIN_ROOT vault operator raft list-peers -format=json | jq -e '[.data.config.servers[] | select(.voter)] | length == 3'"
  ok "Raft: 3 voters"
}

cmd_up() {
  require_kubeconfig
  command -v vault >/dev/null || die "vault CLI not found (brew install hashicorp/tap/vault)"
  "$ROOT/scripts/tls.sh"
  apply_license
  seal_up
  main_up
  cmd_status
}

cmd_unseal() {
  require_kubeconfig
  wait_for "Route $SEAL_ADDR" 120 route_up "$SEAL_ADDR"
  seal_unseal
}

cmd_seal_token_status() {
  require_kubeconfig
  [ -s "$SEAL_INIT" ] || die "no $SEAL_INIT"
  SEAL_ROOT=$(jq -r '.root_token' "$SEAL_INIT")
  local token info
  token=$(oc -n "$MAIN_NS" get secret vault-seal-token -o jsonpath='{.data.token}' | base64 -d)
  info=$(seal_vault token lookup -format=json "$token" 2>/dev/null) || {
    fail "seal token invalid — run: make vault-up"
    return 1
  }
  local ttl
  ttl=$(jq -r '.data.ttl' <<<"$info")
  if [ "$ttl" -ge "$SEAL_TOKEN_MIN_TTL" ]; then ok "seal token TTL $((ttl / 3600))h $(((ttl % 3600) / 60))m"; else fail "seal token TTL ${ttl}s (< ${SEAL_TOKEN_MIN_TTL}s)"; fi
  jq -r '"     period=\(.data.period)s  orphan=\(.data.orphan)  policies=\(.data.policies|join(","))  last_renewal=\(.data.last_renewal // "never (issued \(.data.issue_time))")"' <<<"$info"
}

cmd_status() {
  require_kubeconfig
  local st
  st=$(status_json seal_vault)
  if [ -z "$st" ]; then
    fail "seal Vault: unreachable at $SEAL_ADDR"
  elif [ "$(jq -r '.sealed' <<<"$st")" = true ]; then
    fail "seal Vault: SEALED — run: make vault-unseal"
  else
    ok "seal Vault: unsealed, $(jq -r '.version' <<<"$st"), seal type $(jq -r '.type' <<<"$st")"
  fi
  [ -s "$SEAL_INIT" ] && cmd_seal_token_status || true

  local p sealed=0 ps
  for p in vault-0 vault-1 vault-2; do
    ps=$(pod_status_json "$MAIN_NS" "$p")
    if [ -z "$ps" ]; then
      fail "$p: not running"
      sealed=$((sealed + 1))
    elif [ "$(jq -r '.sealed' <<<"$ps")" = true ]; then
      fail "$p: sealed"
      sealed=$((sealed + 1))
    else
      ok "$p: unsealed, $(jq -r 'if .is_self then "LEADER" else "standby" end' <<<"$ps"), seal $(jq -r '.type' <<<"$ps"), $(jq -r '.version' <<<"$ps")"
    fi
  done
  if [ -s "$MAIN_INIT" ] && [ "$sealed" -lt 3 ]; then
    MAIN_ROOT=$(jq -r '.root_token' "$MAIN_INIT")
    main_vault operator raft list-peers 2>/dev/null | sed 's/^/     /' || warn "raft peers: unavailable"
    local lic
    lic=$(main_vault read -format=json sys/license/status 2>/dev/null | jq -r '.data.autoloaded.expiration_time // empty' || true)
    [ -n "$lic" ] && ok "licence expires $lic"
  fi
  [ "$sealed" -eq 0 ]
}

# The chart's StatefulSet uses updateStrategy OnDelete: pods only pick up a
# new config/image when deleted. Roll standbys first, the leader last (that
# forces one leadership change — the HA demo), each back unsealed + voting
# before the next goes.
cmd_roll() {
  require_kubeconfig
  MAIN_ROOT=$(jq -r '.root_token' "$MAIN_INIT")
  local p leader="" order=()
  for p in vault-0 vault-1 vault-2; do
    if [ "$(pod_status_json "$MAIN_NS" "$p" | jq -r '.is_self')" = true ]; then leader=$p; else order+=("$p"); fi
  done
  [ -n "$leader" ] && order+=("$leader")
  for p in "${order[@]}"; do
    log "rolling $p$([ "$p" = "$leader" ] && echo ' (leader — leadership will move)')"
    oc -n "$MAIN_NS" delete pod "$p" --wait=true >/dev/null
    wait_for "$p Running" 300 pod_running "$MAIN_NS" "$p"
    wait_for "$p unsealed" 300 bash -c \
      "oc -n $MAIN_NS exec $p -c vault -- vault status -format=json 2>/dev/null | jq -e '.sealed == false'"
    wait_for "3 Raft voters" 180 bash -c \
      "VAULT_ADDR=$MAIN_ADDR VAULT_CACERT=$CA VAULT_TOKEN=$MAIN_ROOT vault operator raft list-peers -format=json 2>/dev/null | jq -e '[.data.config.servers[] | select(.voter)] | length == 3'"
    ok "$p back: unsealed, Raft 3 voters"
  done
}

cmd_down() {
  require_kubeconfig
  oc -n "$MAIN_NS" scale statefulset/vault --replicas=0 2>/dev/null && ok "main cluster scaled to 0 (PVCs kept)" || true
  oc -n "$SEAL_NS" scale statefulset/vault-seal --replicas=0 2>/dev/null && ok "seal Vault scaled to 0 (PVC kept) — it will come back SEALED" || true
}

cmd_ui() { open "$MAIN_ADDR/ui/"; }

case "${1:-}" in
  up) cmd_up ;;
  unseal) cmd_unseal ;;
  status) cmd_status ;;
  seal-token-status) cmd_seal_token_status ;;
  roll) cmd_roll ;;
  down) cmd_down ;;
  ui) cmd_ui ;;
  *)
    echo "usage: $0 {up|unseal|status|seal-token-status|roll|down|ui}" >&2
    exit 64
    ;;
esac
