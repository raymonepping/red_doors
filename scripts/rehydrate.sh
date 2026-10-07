#!/usr/bin/env bash
# scripts/rehydrate.sh — `make up`: bring the whole Red Doors estate to its
# desired state. Every step is idempotent; rerunning is safe and, when
# converged, amounts to checks plus renewals.
#
#   rehydrate.sh            run every step
#   rehydrate.sh --list     list the steps
#   rehydrate.sh --from N   resume at step N
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

FROM=1
LIST=false
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=true ;;
    --from) FROM=${2:?--from needs a step number}; shift ;;
    -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

STEP=0
STARTED=$(date +%s)
run() { # <description> <command…>
  STEP=$((STEP + 1))
  if $LIST; then printf '  %2d. %s\n' "$STEP" "$1"; return 0; fi
  [ "$STEP" -ge "$FROM" ] || return 0
  local desc=$1 t0
  shift
  t0=$(date +%s)
  printf '\n\033[1m── step %d: %s\033[0m\n' "$STEP" "$desc"
  if ! "$@"; then
    die "step $STEP failed: $desc — fix it, then resume with: make up FROM=$STEP"
  fi
  printf '\033[2m   (%ss)\033[0m\n' "$(($(date +%s) - t0))"
}

run "OpenShift Local running; kubeconfig refreshed" ./scripts/crc.sh up
run "namespaces" bash -c 'source scripts/lib.sh && oc apply -f deploy/base/namespaces.yaml >/dev/null && ok "6 namespaces"'
run "TLS: CA + Vault server certs (renew if < 30 days)" ./scripts/tls.sh
run "Vault: seal Vault unsealed, seal token valid, 3-node cluster auto-unsealed" ./scripts/vault.sh up
run "Vault: admin token (periodic) + Terraform bootstrap" ./scripts/vault-admin.sh bootstrap
run "Vault: audit devices" ./scripts/audit.sh
run "Vault: door identities + engines/auth/policies (terraform/vault-doors)" bash -c 'source scripts/lib.sh && oc apply -f deploy/doors/serviceaccounts.yaml >/dev/null && ./scripts/tf.sh vault-doors'
run "Vault: door values (only if absent)" ./scripts/seed-doors.sh
run "identity: OpenLDAP + Keycloak + Vault OIDC (doors 2, 8)" ./scripts/identity.sh up
run "data: PostgreSQL + database engine (door 4) + merger ciphertext (door 6)" ./scripts/data.sh up
run "Vault Secrets Operator (door 7)" ./scripts/vso.sh up
run "door openers (build only on source change)" ./scripts/doors.sh up
run "API + socket audit device (build only on source change)" ./scripts/api.sh up
run "UI + BFF (build only on source change)" ./scripts/ui.sh up
run "verify" ./scripts/verify-stack.sh

$LIST && exit 0
printf '\n\033[1m== make up complete in %ss — https://doors.apps-crc.testing ==\033[0m\n' "$(($(date +%s) - STARTED))"
