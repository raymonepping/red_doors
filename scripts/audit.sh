#!/usr/bin/env bash
# scripts/audit.sh — converge Vault's audit devices (terraform/vault-audit).
#
# The socket device to the API's collector is declared only once the API is
# ready: Vault refuses to enable a socket device it cannot connect to, and a
# plain re-apply without the address would otherwise REMOVE the device.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

require_kubeconfig
if [ "$(oc -n rd-app get deploy red-doors-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" -ge 1 ] 2>/dev/null; then
  "$ROOT/scripts/tf.sh" vault-audit -var="audit_socket_address=red-doors-api-audit.rd-app.svc:9090"
  ok "audit devices: stdout (file) + red-doors-collector (socket → API)"
else
  "$ROOT/scripts/tf.sh" vault-audit
  warn "audit devices: stdout only — the API collector isn't running yet (make api-up adds the socket device)"
fi
