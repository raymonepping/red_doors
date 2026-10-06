#!/usr/bin/env bash
# scripts/tf.sh <module> [extra terraform apply args…]
#
# Applies terraform/<module> against https://vault.apps-crc.testing with the
# project CA. Token: VAULT_TOKEN if the caller set one (only vault-admin.sh
# does, for bootstrap with root), otherwise .secrets/vault/admin-token.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

module=${1:?usage: tf.sh <module>}
shift
dir="$ROOT/terraform/$module"
[ -d "$dir" ] || die "no such module: terraform/$module"

if [ -z "${VAULT_TOKEN:-}" ]; then
  [ -s "$ROOT/.secrets/vault/admin-token" ] || die "no admin token — run: make tf-bootstrap"
  VAULT_TOKEN=$(cat "$ROOT/.secrets/vault/admin-token")
fi
export VAULT_TOKEN
# Each module sets its Vault namespace explicitly. A VAULT_NAMESPACE exported
# by the caller would be prefixed on top (found live: red-doors/red-doors → 403).
unset VAULT_NAMESPACE
mkdir -p "$ROOT/.secrets/terraform"

log "terraform apply: $module"
terraform -chdir="$dir" init -input=false -upgrade=false >/dev/null
terraform -chdir="$dir" apply -input=false -auto-approve \
  -var="vault_cacert=$ROOT/vault-tls/ca.pem" "$@" |
  grep -E '^(Apply complete|No changes|Error|│|  # |Plan:)' || true
# grep hides terraform's exit status — re-check the outcome explicitly
terraform -chdir="$dir" plan -input=false -detailed-exitcode \
  -var="vault_cacert=$ROOT/vault-tls/ca.pem" "$@" >/dev/null 2>&1 ||
  die "terraform/$module is not converged after apply — rerun: (cd terraform/$module && terraform plan)"
ok "terraform/$module converged"
