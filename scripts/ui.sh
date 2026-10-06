#!/usr/bin/env bash
# scripts/ui.sh — the Red Doors UI + BFF (frontend 01_01).
#   ui.sh up   manifests → in-cluster build (on source change) → rollout
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NS=rd-app
source_hash() {
  (cd "$ROOT/ui" && find app server public nuxt.config.ts package.json package-lock.json Dockerfile -type f ! -name '._*' -print0 |
    sort -z | xargs -0 cat) | shasum -a 256 | cut -c1-16
}

cmd_up() {
  require_kubeconfig
  oc apply -f "$ROOT/deploy/app/ui.yaml" >/dev/null
  local hash current
  hash=$(source_hash)
  current=$(oc -n "$NS" get imagestream red-doors-ui -o jsonpath='{.metadata.annotations.red-doors/source-hash}' 2>/dev/null || true)
  if [ "$hash" = "$current" ] && oc -n "$NS" get istag red-doors-ui:latest >/dev/null 2>&1; then
    ok "red-doors-ui image up to date ($hash)"
  else
    log "building red-doors-ui in-cluster (nuxt build inside the build pod)"
    xattr -rc "$ROOT/ui" 2>/dev/null || true
    # oc start-build --from-dir uploads everything, so stage a clean copy without build output.
    local tmp
    tmp=$(mktemp -d)
    (cd "$ROOT/ui" && COPYFILE_DISABLE=1 tar --exclude=node_modules --exclude=.nuxt --exclude=.output --exclude='._*' --exclude=tests --exclude=test-results -cf - .) | tar -xf - -C "$tmp"
    oc -n "$NS" start-build red-doors-ui --from-dir="$tmp" --wait >/dev/null
    rm -rf "$tmp"
    oc -n "$NS" annotate imagestream red-doors-ui "red-doors/source-hash=$hash" --overwrite >/dev/null
    ok "red-doors-ui image built ($hash)"
  fi
  oc -n "$NS" rollout status deploy/red-doors-ui --timeout=240s >/dev/null
  ok "red-doors-ui ready → https://doors.apps-crc.testing"
}

case "${1:-}" in
  up) cmd_up ;;
  *) echo "usage: $0 up" >&2; exit 64 ;;
esac
