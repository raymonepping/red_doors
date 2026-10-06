#!/usr/bin/env bash
# scripts/api.sh — the Red Doors API (prompt 07).
#
#   api.sh up          terraform/vault-api → manifests → in-cluster build (on change) → rollout → socket audit device
#   api.sh call M P [JSON] [USER]
#                      call the API from inside its pod (it has no Route). USER signs a demo user in
#                      through the real OIDC chain first and passes their Vault token like the UI's BFF.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NS=rd-app
source_hash() { (cd "$ROOT/api" && cat package.json package-lock.json Dockerfile src/*.js) | shasum -a 256 | cut -c1-16; }

build() {
  local hash current
  hash=$(source_hash)
  current=$(oc -n "$NS" get imagestream red-doors-api -o jsonpath='{.metadata.annotations.red-doors/source-hash}' 2>/dev/null || true)
  if [ "$hash" = "$current" ] && oc -n "$NS" get istag red-doors-api:latest >/dev/null 2>&1; then
    ok "red-doors-api image up to date ($hash)"
    return
  fi
  log "building red-doors-api in-cluster"
  xattr -rc "$ROOT/api" 2>/dev/null || true
  COPYFILE_DISABLE=1 oc -n "$NS" start-build red-doors-api --from-dir="$ROOT/api" --wait >/dev/null
  oc -n "$NS" annotate imagestream red-doors-api "red-doors/source-hash=$hash" --overwrite >/dev/null
  ok "red-doors-api image built ($hash)"
}

cmd_up() {
  require_kubeconfig
  "$ROOT/scripts/tf.sh" vault-api
  oc apply -f "$ROOT/deploy/app/api.yaml" >/dev/null
  build
  oc -n "$NS" rollout status deploy/red-doors-api --timeout=240s >/dev/null
  ok "red-doors-api ready ($(oc -n "$NS" exec deploy/red-doors-api -- node -e "fetch('http://127.0.0.1:3001/api/v1/health').then(r=>r.json()).then(j=>console.log(j.status+', vault policies '+j.vault.policies.join(',')+', db '+j.database.username))"))"
  # Only now can Vault connect its socket audit device to the collector.
  "$ROOT/scripts/audit.sh"
}

cmd_call() {
  require_kubeconfig
  local method=${1:?method} path=${2:?path} body=${3:-} user=${4:-} token=""
  [ -n "$user" ] && token=$("$ROOT/scripts/oidc-login.sh" "$user")
  oc -n "$NS" exec deploy/red-doors-api -- node -e '
    const [m, p, b, t, who] = process.argv.slice(1);
    const h = { "content-type": "application/json", "x-triggered-by": who || "make" };
    if (t) h["x-vault-token"] = t;
    fetch("http://127.0.0.1:3001" + p, { method: m, headers: h, body: b || undefined })
      .then(async r => process.stdout.write(await r.text()));' "$method" "$path" "$body" "$token" "$user"
}

case "${1:-}" in
  up) cmd_up ;;
  call) shift && cmd_call "$@" ;;
  *)
    echo "usage: $0 {up|call METHOD PATH [JSON] [USER]}" >&2
    exit 64
    ;;
esac
