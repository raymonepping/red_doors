# rd-api — the Red Doors API's own identity (SA rd-app/red-doors-api).
# It orchestrates; it never opens a door itself.

# Door 3: it may MINT a secret-id, but Vault forces the response to be wrapped
# (30s–2m) — the API never sees the secret-id and never holds the role-id.
path "auth/approle/role/door-3/secret-id" {
  capabilities     = ["update"]
  min_wrapping_ttl = "30s"
  max_wrapping_ttl = "2m"
}

# Show the policies and the Sentinel EGP verbatim in the UI.
path "sys/policies/acl/door-*" {
  capabilities = ["read"]
}
path "sys/policies/acl/impostor" {
  capabilities = ["read"]
}
path "sys/policies/acl/auditor" {
  capabilities = ["read"]
}
path "sys/policies/egp/door-8-*" {
  capabilities = ["read"]
}

# Turn a signed-in person's entity into group NAMES for the UI (no secrets).
path "identity/entity/id/*" {
  capabilities = ["read"]
}
path "identity/group/id/*" {
  capabilities = ["read"]
}

# Its own PostgreSQL logins (schema api) — minted by Vault, like door 4.
path "database/creds/api-rw" {
  capabilities = ["read"]
}
