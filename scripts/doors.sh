#!/usr/bin/env bash
# scripts/doors.sh — the door openers (prompt 06).
#
#   doors.sh up            role-id ConfigMap, forged cert, manifests, in-cluster build (on change), rollout
#   doors.sh knock N       knock on door N as its owner   (runs inside opener-N: works before the API exists)
#   doors.sh knock-wrong N knock on door N as the impostor
#
# Door 3 needs a wrapped secret-id and door 6 the ciphertext; here the admin
# token plays the trusted orchestrator (in prompt 07 the API does, with a
# policy that can only WRAP door-3 secret-ids).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NS=rd-doors
export VAULT_ADDR=https://vault.apps-crc.testing VAULT_CACERT="$ROOT/vault-tls/ca.pem" VAULT_NAMESPACE=red-doors
admin() { VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token") vault "$@"; }

source_hash() { (cd "$ROOT/openers" && cat package.json package-lock.json Dockerfile src/*.js) | shasum -a 256 | cut -c1-16; }

build() {
  local hash current
  hash=$(source_hash)
  current=$(oc -n "$NS" get imagestream opener -o jsonpath='{.metadata.annotations.red-doors/source-hash}' 2>/dev/null || true)
  if [ "$hash" = "$current" ] && oc -n "$NS" get istag opener:latest >/dev/null 2>&1; then
    ok "opener image up to date ($hash)"
    return
  fi
  log "building opener in-cluster (node:24-slim)"
  xattr -rc "$ROOT/openers" 2>/dev/null || true
  COPYFILE_DISABLE=1 oc -n "$NS" start-build opener --from-dir="$ROOT/openers" --wait >/dev/null
  oc -n "$NS" annotate imagestream opener "red-doors/source-hash=$hash" --overwrite >/dev/null
  ok "opener image built ($hash)"
}

cmd_up() {
  require_kubeconfig
  oc apply -f "$ROOT/deploy/doors/serviceaccounts.yaml" >/dev/null
  # door 3: the role-id is not secret on its own — the secret-id arrives wrapped per knock
  oc -n "$NS" create configmap opener-3-role-id \
    --from-literal=role_id="$(admin read -field=role_id auth/approle/role/door-3/role-id)" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  # the impostor's forgery: a self-signed cert with exactly door 5's CN
  if ! oc -n "$NS" get secret impostor-forged-cert >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp -d)
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 365 \
      -subj "/CN=opener-5.rd-doors" -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null
    oc -n "$NS" create secret tls impostor-forged-cert --cert="$tmp/tls.crt" --key="$tmp/tls.key" >/dev/null
    rm -rf "$tmp"
    ok "impostor-forged-cert: self-signed CN=opener-5.rd-doors (not from the Treasury CA)"
  fi
  oc apply -f "$ROOT/deploy/doors/openers.yaml" >/dev/null
  oc apply -f "$ROOT/deploy/doors/vso.yaml" >/dev/null
  build
  local d
  for d in 1 3 4 5 6 7 impostor; do
    oc -n "$NS" rollout status "deploy/opener-$d" --timeout=180s >/dev/null
  done
  ok "openers ready: $(oc -n "$NS" get pods -l app=opener -o jsonpath='{range .items[*]}{.metadata.labels.red-doors/opener}{" "}{end}')"
}

knock_in() { # <deployment> <json>
  oc -n "$NS" exec "deploy/$1" -c opener -- node -e \
    "fetch('http://127.0.0.1:8080/knock',{method:'POST',headers:{'content-type':'application/json'},body:process.argv[1]}).then(r=>r.text()).then(t=>process.stdout.write(t))" "$2"
}

wrapped_secret_id() { admin write -wrap-ttl=60s -f -field=wrapping_token auth/approle/role/door-3/secret-id; }
ciphertext() { oc -n rd-data exec deploy/postgres -- psql -X -tA -d reddoors -c 'SELECT ciphertext FROM merger_docs ORDER BY id LIMIT 1'; }

cmd_knock() {
  require_kubeconfig
  local door=${1:?usage: doors.sh knock <1|3|4|5|6|7>} body='{}'
  case "$door" in
    3) body=$(jq -nc --arg t "$(wrapped_secret_id)" '{wrapping_token: $t}') ;;
    6) body=$(jq -nc --arg c "$(ciphertext)" '{ciphertext: $c}') ;;
    1 | 4 | 5 | 7) ;;
    *) die "door $door is not a machine door (2 and 8 are human doors)" ;;
  esac
  knock_in "opener-$door" "$body" | jq .
}

cmd_knock_wrong() {
  require_kubeconfig
  local door=${1:?usage: doors.sh knock-wrong <1|3|4|5|6|7>} body
  case "$door" in
    3)
      # a wrapping token the rightful opener already consumed — replayed
      local t
      t=$(wrapped_secret_id)
      knock_in opener-3 "$(jq -nc --arg t "$t" '{wrapping_token: $t}')" >/dev/null
      body=$(jq -nc --arg t "$t" '{door: 3, wrapping_token: $t}')
      ;;
    6) body=$(jq -nc --arg c "$(ciphertext)" '{door: 6, ciphertext: $c}') ;;
    1 | 4 | 5 | 7) body=$(jq -nc --argjson d "$door" '{door: $d}') ;;
    *) die "door $door is not a machine door" ;;
  esac
  knock_in opener-impostor "$body" | jq .
}

case "${1:-}" in
  up) cmd_up ;;
  knock) cmd_knock "${2:-}" ;;
  knock-wrong) cmd_knock_wrong "${2:-}" ;;
  *)
    echo "usage: $0 {up|knock N|knock-wrong N}" >&2
    exit 64
    ;;
esac
