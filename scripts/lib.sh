#!/usr/bin/env bash
# scripts/lib.sh — shared helpers, sourced by every Red Doors script.
#
# Every script talks to the cluster through the project's own kubeconfig
# (.secrets/kube/config) — never ~/.kube/config, whose current context may
# point at some other local cluster.

# macOS ships bash 3.2; these scripts use bash 4+ features (associative arrays).
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "[red-doors] ERROR: bash >= 4 required (found $BASH_VERSION) — brew install bash" >&2
  exit 1
fi

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT
export KUBECONFIG="$ROOT/.secrets/kube/config"

# `oc` ships inside CRC and is only on PATH via `crc oc-env`.
if ! command -v oc >/dev/null 2>&1 && command -v crc >/dev/null 2>&1; then
  eval "$(crc oc-env 2>/dev/null)"
fi

# Namespaces owned by Red Doors (deploy/base/namespaces.yaml).
RD_NAMESPACES=(rd-vault-seal rd-vault rd-identity rd-data rd-doors rd-app)
export RD_NAMESPACES

if [ -t 1 ]; then
  C_OK=$'\033[0;32m' C_WARN=$'\033[0;33m' C_ERR=$'\033[0;31m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  C_OK='' C_WARN='' C_ERR='' C_DIM='' C_OFF=''
fi

log() { printf '%s[red-doors]%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
ok() { printf '  %s✓%s  %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s⚠%s  %s\n' "$C_WARN" "$C_OFF" "$*"; }
fail() { printf '  %s✗%s  %s\n' "$C_ERR" "$C_OFF" "$*"; }
die() {
  printf '%s[red-doors] ERROR:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2
  exit 1
}

require_kubeconfig() {
  [ -s "$KUBECONFIG" ] || die "no kubeconfig at $KUBECONFIG — run: make crc-up (or make oc-login if CRC is already running)"
  command -v oc >/dev/null 2>&1 || die "oc not found — is OpenShift Local installed? (crc oc-env)"
}
