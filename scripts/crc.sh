#!/usr/bin/env bash
# scripts/crc.sh — OpenShift Local (CRC) lifecycle for Red Doors.
#
#   crc.sh up       configure, set up and start CRC; refresh .secrets/kube/config
#   crc.sh down     stop the VM (keeps it and all cluster data)
#   crc.sh status   CRC + cluster health + Red Doors pods
#   crc.sh console  print console URL + credentials, open the web console
#   crc.sh login    refresh .secrets/kube/config from a running CRC
#
# Every subcommand is idempotent.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

PULL_SECRET="$ROOT/.secrets/crc/pull-secret.json"

# Sizing (prompt 01). OpenShift itself idles at ~8 GB and needs ~10–11 GB
# under load. Red Doors adds Vault ×4 (seal + 3 Raft nodes), Keycloak,
# OpenLDAP, PostgreSQL, the Vault Secrets Operator, API, UI and seven
# openers ≈ 6–7 GB, plus headroom for in-cluster builds. 24 GB / 8 vCPU on a
# 48 GB / 12-core M4 Pro leaves the Mac responsive — provided the Podman
# machine is stopped (see require_podman_stopped).
CRC_CPUS=8
CRC_MEMORY_MB=24576
CRC_DISK_GB=80

crc_state() { crc status -o json 2>/dev/null | jq -r '.crcStatus // "Missing"' 2>/dev/null || echo Missing; }

# Two VMs competing for RAM caused real damage before (Podman VM CPU
# starvation → guest clock drift of 16 min → JWT/TOTP failures).
require_podman_stopped() {
  command -v podman >/dev/null 2>&1 || return 0
  if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
    if [ "${ALLOW_PODMAN:-0}" = 1 ]; then
      warn "Podman machine is running (ALLOW_PODMAN=1) — both VMs will compete for RAM/CPU"
    else
      die "the Podman machine is running. OpenShift Local needs ${CRC_MEMORY_MB} MB and the two VMs
       would compete for memory (past incident: CPU starvation → clock drift → JWT failures).
       Stop it with 'podman machine stop', or rerun with ALLOW_PODMAN=1 to override."
    fi
  fi
}

ensure_config() {
  local key want have
  for kv in "preset=openshift" "cpus=$CRC_CPUS" "memory=$CRC_MEMORY_MB" "disk-size=$CRC_DISK_GB" "consent-telemetry=no"; do
    key=${kv%%=*} want=${kv#*=}
    have=$(crc config get "$key" 2>&1 || true)
    # Unset keys report "… is not set. Default value 'X' is used" — and CRC
    # doesn't persist a value equal to its default, so treat that as X.
    if [[ $have =~ Default\ value\ \'([^\']*)\' ]]; then
      have=${BASH_REMATCH[1]}
    else
      have=$(awk -F': ' '{print $NF}' <<<"$have" | tr -d ' ')
    fi
    if [ "$have" != "$want" ]; then
      crc config set "$key" "$want" >/dev/null
      log "crc config: $key=$want (was: ${have:-unset})"
    fi
  done
}

refresh_kubeconfig() {
  # CRC's own admin kubeconfig authenticates system:admin with a client
  # certificate valid for ~10 years. `oc login -u kubeadmin` would yield a
  # token that expires after 24h and break every script daily. Copied on
  # every run because a recreated VM gets a new CA and certificate.
  local src="$HOME/.crc/machines/crc/kubeconfig"
  [ -s "$src" ] || die "CRC admin kubeconfig not found at $src — is the VM created? (make crc-up)"
  mkdir -p "$(dirname "$KUBECONFIG")"
  chmod 700 "$ROOT/.secrets" "$(dirname "$KUBECONFIG")"
  install -m 600 "$src" "$KUBECONFIG"
  oc whoami >/dev/null || die "kubeconfig copied but 'oc whoami' failed"
  ok "kubeconfig → .secrets/kube/config ($(oc whoami), $(oc whoami --show-server))"
}

cmd_up() {
  command -v crc >/dev/null 2>&1 || die "crc not found — install OpenShift Local first"
  [ -s "$PULL_SECRET" ] || die "pull secret missing: $PULL_SECRET
       Download it from https://console.redhat.com/openshift/create/local and save it there (it is gitignored)."
  jq -e '.auths' "$PULL_SECRET" >/dev/null 2>&1 || die "$PULL_SECRET is not a valid pull secret (expected JSON with .auths)"

  local state
  state=$(crc_state)
  if [ "$state" = Running ]; then
    ok "CRC already running"
    ensure_config # keeps desired sizing recorded; takes effect on next start
  else
    require_podman_stopped
    ensure_config
    if ! crc setup --check-only >/dev/null 2>&1; then
      log "running crc setup"
      crc setup
    fi
    log "starting CRC (first start ≈ 10 min; later starts ≈ 3–5 min)"
    crc start -p "$PULL_SECRET"
  fi
  refresh_kubeconfig
}

cmd_down() {
  if [ "$(crc_state)" = Running ]; then
    log "stopping CRC (VM and cluster data are kept)"
    crc stop
  else
    ok "CRC not running"
  fi
}

cmd_login() {
  [ "$(crc_state)" = Running ] || die "CRC is not running — make crc-up"
  refresh_kubeconfig
}

cmd_console() {
  [ "$(crc_state)" = Running ] || die "CRC is not running — make crc-up"
  crc console --credentials
  crc console >/dev/null 2>&1 || true
}

cmd_status() {
  local json
  json=$(crc status -o json 2>/dev/null || true)
  if [ -z "$json" ] || [ "$(jq -r '.crcStatus // empty' <<<"$json")" != Running ]; then
    fail "CRC: ${json:+$(jq -r '.crcStatus' <<<"$json")}${json:-not created}"
    return 1
  fi
  ok "CRC running — OpenShift $(jq -r '.openshiftVersion' <<<"$json"), RAM $(jq -r '(.ramUsage/1e9*10|floor/10|tostring) + " / " + (.ramSize/1e9*10|floor/10|tostring) + " GB"' <<<"$json"), disk $(jq -r '(.diskUsage/1e9|floor|tostring) + " / " + (.diskSize/1e9|floor|tostring) + " GB"' <<<"$json")"
  require_kubeconfig

  local nodes
  nodes=$(oc get nodes --no-headers 2>/dev/null)
  if grep -q ' Ready ' <<<"$nodes"; then ok "node: $(awk '{print $1" "$2" "$5}' <<<"$nodes")"; else fail "node not Ready: $nodes"; fi

  local co total avail degraded
  co=$(oc get clusteroperators --no-headers 2>/dev/null)
  total=$(wc -l <<<"$co" | tr -d ' ')
  avail=$(awk '$3=="True"' <<<"$co" | wc -l | tr -d ' ')
  degraded=$(awk '$5=="True"' <<<"$co" | wc -l | tr -d ' ')
  if [ "$avail" = "$total" ] && [ "$degraded" = 0 ]; then
    ok "cluster operators: $avail/$total available, 0 degraded"
  else
    fail "cluster operators: $avail/$total available, $degraded degraded"
    awk '$3!="True" || $5=="True" {print "       - " $1 " (available=" $3 ", degraded=" $5 ")"}' <<<"$co"
  fi

  local reg
  reg=$(oc get configs.imageregistry.operator.openshift.io cluster -o jsonpath='{.spec.managementState}' 2>/dev/null || true)
  if [ "$reg" = Managed ]; then ok "internal image registry: Managed (in-cluster builds can push)"; else warn "internal image registry: ${reg:-unknown}"; fi

  local ns pods
  for ns in "${RD_NAMESPACES[@]}"; do
    if ! oc get namespace "$ns" >/dev/null 2>&1; then
      warn "namespace $ns missing — make namespaces"
      continue
    fi
    pods=$(oc -n "$ns" get pods --no-headers 2>/dev/null | awk '{print $1" "$3}' | paste -sd ',' - | sed 's/,/, /g')
    ok "$ns: ${pods:-no pods}"
  done
}

case "${1:-}" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  console) cmd_console ;;
  login) cmd_login ;;
  *)
    echo "usage: $0 {up|down|status|console|login}" >&2
    exit 64
    ;;
esac
