#!/usr/bin/env bash
# scripts/oidc-login.sh <user> — sign a demo user in through the REAL chain
# and print the resulting Vault token on stdout (test aid; prompts 04–08).
#
#   Vault auth/oidc/oidc/auth_url → Keycloak login form (LDAP-federated user)
#   → Keycloak redirects with ?code&state → Vault auth/oidc/oidc/callback → token
#
# Nothing is mocked: Keycloak checks the LDAP password, Vault validates the ID
# token and maps the `groups` claim to its external groups.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

user=${1:?usage: oidc-login.sh <user>}
pw=$(jq -er --arg u "$user" '.[$u]' "$ROOT/.secrets/identity/users.json") || die "unknown demo user: $user"
VAULT=https://vault.apps-crc.testing
REDIRECT=http://localhost:8250/oidc/callback
NONCE=$(openssl rand -hex 12)
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT
vcurl() { curl -fsS --cacert "$ROOT/vault-tls/ca.pem" -H 'X-Vault-Namespace: red-doors' "$@"; }
kcurl() { curl -sS --cacert "$ROOT/vault-tls/ingress-ca.pem" -b "$jar" -c "$jar" "$@"; }

auth_url=$(vcurl -X POST "$VAULT/v1/auth/oidc/oidc/auth_url" \
  -d "{\"role\":\"visitor\",\"redirect_uri\":\"$REDIRECT\",\"client_nonce\":\"$NONCE\"}" | jq -er '.data.auth_url')

# Keycloak login page → its form action (HTML-escaped &amp;)
action=$(kcurl -L "$auth_url" | sed -n 's/.*id="kc-form-login"[^>]*action="\([^"]*\)".*/\1/p' | head -1 | sed 's/&amp;/\&/g')
[ -n "$action" ] || die "Keycloak login form not found"

location=$(kcurl -o /dev/null -D - -X POST "$action" \
  --data-urlencode "username=$user" --data-urlencode "password=$pw" --data-urlencode "credentialId=" |
  awk 'tolower($1)=="location:" {print $2}' | tr -d '\r')
case "$location" in
  "$REDIRECT"*) ;;
  *) die "Keycloak did not redirect back (wrong password or account issue)" ;;
esac
query=${location#*\?}
state=$(tr '&' '\n' <<<"$query" | sed -n 's/^state=//p')
code=$(tr '&' '\n' <<<"$query" | sed -n 's/^code=//p')

vcurl -G "$VAULT/v1/auth/oidc/oidc/callback" \
  --data-urlencode "state=$state" --data-urlencode "code=$code" --data-urlencode "client_nonce=$NONCE" |
  jq -er '.auth.client_token'
