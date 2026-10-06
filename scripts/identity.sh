#!/usr/bin/env bash
# scripts/identity.sh — OpenLDAP + Keycloak for Red Doors (prompt 04).
#
#   identity.sh up      secrets → LDAP image build → deploy → seed LDAP → reconcile Keycloak → Vault OIDC (terraform)
#   identity.sh users   print the demo users and their passwords (presenter aid)
#
# Reconcile, never recreate: reruns converge LDAP entries, the realm, the
# federation, the client and the Vault side to the same desired state.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NS=rd-identity
SEC="$ROOT/.secrets/identity"
USERS="$SEC/users.json"
BASE_DN="dc=reddoors,dc=local"
mkdir -p "$SEC"
chmod 700 "$SEC"
umask 077

# user → groups (prompt 04 table). Order = corridor story.
DEMO_USERS=(ada ben cleo dirk eve finn)
declare -A GROUPS_OF=(
  [ada]="board staff"
  [ben]="staff"
  [cleo]="requesters staff"
  [dirk]="approvers staff"
  [eve]="approvers requesters staff"
  [finn]="auditors"
)
declare -A FULLNAME=(
  [ada]="Ada Lindqvist" [ben]="Ben Okafor" [cleo]="Cleo Marchetti"
  [dirk]="Dirk van Houten" [eve]="Eve Castellanos" [finn]="Finn Aaltonen"
)
ALL_GROUPS=(board staff requesters approvers auditors)

genpw() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c "${1:-20}"; }

ensure_secrets() {
  [ -s "$SEC/ldap-admin" ] || genpw 24 >"$SEC/ldap-admin"
  [ -s "$SEC/keycloak-admin" ] || genpw 24 >"$SEC/keycloak-admin"
  [ -s "$SEC/vault-oidc-client-secret" ] || genpw 32 >"$SEC/vault-oidc-client-secret"
  if [ ! -s "$USERS" ]; then
    local json='{}' u
    for u in "${DEMO_USERS[@]}"; do json=$(jq --arg u "$u" --arg p "$(genpw 14)" '. + {($u): $p}' <<<"$json"); done
    printf '%s\n' "$json" >"$USERS"
  fi
  oc -n "$NS" create secret generic ldap-admin --from-file=password="$SEC/ldap-admin" --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc -n "$NS" create secret generic keycloak-admin --from-file=password="$SEC/keycloak-admin" --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "secrets: ldap-admin, keycloak-admin, vault OIDC client secret, ${#DEMO_USERS[@]} user passwords (.secrets/identity/)"
}

build_ldap() {
  local src="$ROOT/deploy/identity/openldap" hash current
  hash=$(cat "$src"/* | shasum -a 256 | cut -c1-16)
  current=$(oc -n "$NS" get imagestream rd-openldap -o jsonpath='{.metadata.annotations.red-doors/source-hash}' 2>/dev/null || true)
  if [ "$hash" = "$current" ] && oc -n "$NS" get istag rd-openldap:latest >/dev/null 2>&1; then
    ok "rd-openldap image up to date ($hash)"
    return
  fi
  log "building rd-openldap in-cluster (Alpine OpenLDAP)"
  xattr -rc "$src" 2>/dev/null || true
  COPYFILE_DISABLE=1 oc -n "$NS" start-build rd-openldap --from-dir="$src" --wait >/dev/null
  oc -n "$NS" annotate imagestream rd-openldap "red-doors/source-hash=$hash" --overwrite >/dev/null
  ok "rd-openldap built ($hash)"
}

ldap() { # run an LDAP client command in the openldap pod as the directory admin
  oc -n "$NS" exec -i deploy/openldap -- "$@"
}

seed_ldap() {
  local admin dn u g
  admin=$(cat "$SEC/ldap-admin")
  {
    printf 'dn: %s\nobjectClass: top\nobjectClass: dcObject\nobjectClass: organization\no: Red Doors\ndc: reddoors\n\n' "$BASE_DN"
    printf 'dn: ou=people,%s\nobjectClass: organizationalUnit\nou: people\n\n' "$BASE_DN"
    printf 'dn: ou=groups,%s\nobjectClass: organizationalUnit\nou: groups\n\n' "$BASE_DN"
    for u in "${DEMO_USERS[@]}"; do
      printf 'dn: uid=%s,ou=people,%s\nobjectClass: inetOrgPerson\nuid: %s\ncn: %s\nsn: %s\ngivenName: %s\nmail: %s@reddoors.local\n\n' \
        "$u" "$BASE_DN" "$u" "${FULLNAME[$u]}" "${FULLNAME[$u]#* }" "${FULLNAME[$u]%% *}" "$u"
    done
    for g in "${ALL_GROUPS[@]}"; do
      printf 'dn: cn=%s,ou=groups,%s\nobjectClass: groupOfNames\ncn: %s\nmember: cn=admin,%s\n\n' "$g" "$BASE_DN" "$g" "$BASE_DN"
    done
  } | ldap ldapadd -c -x -H ldap://localhost:1389 -D "cn=admin,$BASE_DN" -w "$admin" >/dev/null 2>&1 || true

  # Group membership = desired state (replace), so reruns converge.
  for g in "${ALL_GROUPS[@]}"; do
    {
      printf 'dn: cn=%s,ou=groups,%s\nchangetype: modify\nreplace: member\n' "$g" "$BASE_DN"
      for u in "${DEMO_USERS[@]}"; do
        [[ " ${GROUPS_OF[$u]} " == *" $g "* ]] && printf 'member: uid=%s,ou=people,%s\n' "$u" "$BASE_DN"
      done
      printf '\n'
    } | ldap ldapmodify -x -H ldap://localhost:1389 -D "cn=admin,$BASE_DN" -w "$admin" >/dev/null
  done
  # Passwords via the password-modify extended op → stored as {SSHA}.
  for u in "${DEMO_USERS[@]}"; do
    dn="uid=$u,ou=people,$BASE_DN"
    ldap ldappasswd -x -H ldap://localhost:1389 -D "cn=admin,$BASE_DN" -w "$admin" -s "$(jq -r --arg u "$u" '.[$u]' "$USERS")" "$dn" >/dev/null
  done
  local n
  n=$(ldap ldapsearch -x -LLL -H ldap://localhost:1389 -D "cn=admin,$BASE_DN" -w "$admin" -b "ou=people,$BASE_DN" '(objectClass=inetOrgPerson)' dn | grep -c '^dn:')
  ok "LDAP: $n users, ${#ALL_GROUPS[@]} groups (memberships + passwords reconciled)"
}

# kcadm inside the Keycloak pod (its env carries the bootstrap admin password)
# Drops only the JVM's harmless "Unable to get SVE vector length" line (Apple Silicon); other stderr passes through.
kc() { oc -n "$NS" exec deploy/keycloak -- /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config 2> >(grep -v 'SVE vector length' >&2); }
kc_login() {
  oc -n "$NS" exec deploy/keycloak -- sh -c '/opt/keycloak/bin/kcadm.sh config credentials --config /tmp/kcadm.config \
    --server http://localhost:8080 --realm master --user admin --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"' >/dev/null 2>&1
}

reconcile_keycloak() {
  local realm_id ldap_id mapper_id client_id mapper
  kc_login || die "kcadm login failed"
  if ! kc get realms/red-doors >/dev/null 2>&1; then
    kc create realms -s realm=red-doors -s enabled=true -s 'displayName=Red Doors' >/dev/null
    ok "Keycloak: realm red-doors created"
  fi
  realm_id=$(kc get realms/red-doors --fields id --format csv --noquotes)

  ldap_id=$(kc get components -r red-doors -q name=ldap --fields id --format csv --noquotes 2>/dev/null | head -1)
  local ldap_cfg=(
    -s name=ldap -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider -s "parentId=$realm_id"
    -s 'config.vendor=["other"]' -s 'config.connectionUrl=["ldap://openldap.rd-identity.svc:389"]'
    -s "config.bindDn=[\"cn=admin,$BASE_DN\"]" -s "config.bindCredential=[\"$(cat "$SEC/ldap-admin")\"]"
    -s "config.usersDn=[\"ou=people,$BASE_DN\"]" -s 'config.usernameLDAPAttribute=["uid"]' -s 'config.rdnLDAPAttribute=["uid"]'
    -s 'config.uuidLDAPAttribute=["entryUUID"]' -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]'
    -s 'config.editMode=["READ_ONLY"]' -s 'config.importEnabled=["true"]' -s 'config.syncRegistrations=["false"]'
    -s 'config.authType=["simple"]' -s 'config.searchScope=["1"]' -s 'config.pagination=["false"]' -s 'config.enabled=["true"]'
    -s 'config.trustEmail=["true"]'
  )
  if [ -z "$ldap_id" ]; then
    kc create components -r red-doors "${ldap_cfg[@]}" >/dev/null
    ldap_id=$(kc get components -r red-doors -q name=ldap --fields id --format csv --noquotes | head -1)
    ok "Keycloak: LDAP federation created (read-only)"
  else
    kc update "components/$ldap_id" -r red-doors "${ldap_cfg[@]}" >/dev/null
  fi

  mapper_id=$(kc get components -r red-doors -q name=ldap-groups --fields id --format csv --noquotes 2>/dev/null | head -1)
  local mapper_cfg=(
    -s name=ldap-groups -s providerId=group-ldap-mapper -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper -s "parentId=$ldap_id"
    -s "config.\"groups.dn\"=[\"ou=groups,$BASE_DN\"]" -s 'config."group.name.ldap.attribute"=["cn"]'
    -s 'config."group.object.classes"=["groupOfNames"]' -s 'config."membership.ldap.attribute"=["member"]'
    -s 'config."membership.attribute.type"=["DN"]' -s 'config."membership.user.ldap.attribute"=["uid"]' -s 'config.mode=["READ_ONLY"]'
    -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' -s 'config."preserve.group.inheritance"=["false"]'
    -s 'config."ignore.missing.groups"=["false"]' -s 'config."drop.non.existing.groups.during.sync"=["true"]'
  )
  if [ -z "$mapper_id" ]; then
    kc create components -r red-doors "${mapper_cfg[@]}" >/dev/null
    mapper_id=$(kc get components -r red-doors -q name=ldap-groups --fields id --format csv --noquotes | head -1)
    ok "Keycloak: LDAP group mapper created"
  else
    kc update "components/$mapper_id" -r red-doors "${mapper_cfg[@]}" >/dev/null
  fi
  kc create "user-storage/$ldap_id/sync?action=triggerFullSync" -r red-doors >/dev/null
  kc create "user-storage/$ldap_id/mappers/$mapper_id/sync?direction=fedToKeycloak" -r red-doors >/dev/null
  ok "Keycloak: LDAP users + groups synced ($(kc get groups -r red-doors --fields name --format csv --noquotes | paste -sd ',' -))"

  # The `vault` client — Vault is the OIDC client; the UI's login IS a Vault login.
  local secret
  secret=$(cat "$SEC/vault-oidc-client-secret")
  local client_cfg=(
    -s clientId=vault -s 'name=HashiCorp Vault (Red Doors)' -s enabled=true -s publicClient=false -s "secret=$secret"
    -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s implicitFlowEnabled=false
    -s 'redirectUris=["https://doors.apps-crc.testing/auth/callback","https://vault.apps-crc.testing/ui/vault/auth/oidc/oidc/callback","http://localhost:8250/oidc/callback"]'
  )
  client_id=$(kc get clients -r red-doors -q clientId=vault --fields id --format csv --noquotes | head -1)
  if [ -z "$client_id" ]; then
    kc create clients -r red-doors "${client_cfg[@]}" >/dev/null
    client_id=$(kc get clients -r red-doors -q clientId=vault --fields id --format csv --noquotes | head -1)
    ok "Keycloak: client vault created"
  else
    kc update "clients/$client_id" -r red-doors "${client_cfg[@]}" >/dev/null
  fi
  mapper=$(kc get "clients/$client_id/protocol-mappers/models" -r red-doors --fields name --format csv --noquotes | grep -x groups || true)
  if [ -z "$mapper" ]; then
    kc create "clients/$client_id/protocol-mappers/models" -r red-doors -s name=groups -s protocol=openid-connect \
      -s protocolMapper=oidc-group-membership-mapper -s 'config."full.path"=false' -s 'config."claim.name"=groups' \
      -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' -s 'config."userinfo.token.claim"=true' >/dev/null
    ok "Keycloak: groups claim mapper on client vault"
  fi
  ok "Keycloak: realm red-doors, client vault, redirect URIs (UI, Vault UI, vault CLI) reconciled"
}

vault_oidc() {
  # Keycloak's Route is edge-terminated with the CRC ingress certificate;
  # Vault must trust that CA for OIDC discovery (never an http URL).
  oc -n openshift-config-managed get configmap default-ingress-cert -o jsonpath='{.data.ca-bundle\.crt}' >"$ROOT/vault-tls/ingress-ca.pem"
  "$ROOT/scripts/tf.sh" vault-identity \
    -var="ingress_ca_file=$ROOT/vault-tls/ingress-ca.pem" \
    -var="oidc_client_secret=$(cat "$SEC/vault-oidc-client-secret")"
}

cmd_up() {
  require_kubeconfig
  ensure_secrets
  oc apply -f "$ROOT/deploy/identity/identity.yaml" >/dev/null
  build_ldap
  oc -n "$NS" rollout status deploy/openldap --timeout=180s >/dev/null
  ok "openldap ready"
  seed_ldap
  oc -n "$NS" rollout status deploy/keycloak --timeout=600s >/dev/null
  ok "keycloak ready (https://keycloak.apps-crc.testing)"
  reconcile_keycloak
  vault_oidc
}

cmd_users() {
  [ -s "$USERS" ] || die "no users yet — run make identity-up"
  printf '%-6s %-18s %-30s %s\n' USER NAME GROUPS PASSWORD
  local u
  for u in "${DEMO_USERS[@]}"; do
    printf '%-6s %-18s %-30s %s\n' "$u" "${FULLNAME[$u]}" "${GROUPS_OF[$u]}" "$(jq -r --arg u "$u" '.[$u]' "$USERS")"
  done
}

case "${1:-}" in
  up) cmd_up ;;
  users) cmd_users ;;
  *)
    echo "usage: $0 {up|users}" >&2
    exit 64
    ;;
esac
