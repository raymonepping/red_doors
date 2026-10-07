#!/usr/bin/env bash
# scripts/down.sh — `make down`: stop everything, keep all data (PVCs, .secrets/).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
if [ "$(crc status -o json 2>/dev/null | jq -r .crcStatus)" = Running ]; then
  require_kubeconfig
  for ns in rd-app rd-doors rd-data rd-identity; do
    oc -n "$ns" scale deploy --all --replicas=0 >/dev/null 2>&1 && ok "$ns scaled to 0" || true
  done
  "$ROOT/scripts/vault.sh" down
fi
"$ROOT/scripts/crc.sh" down
ok "down — nothing deleted; make up brings everything back (the seal Vault is unsealed from .secrets/)"
