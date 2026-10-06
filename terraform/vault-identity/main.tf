# terraform/vault-identity — humans (prompt 04), namespace red-doors.
#
# Vault is the OIDC client of Keycloak (realm red-doors, client `vault`).
# Keycloak federates OpenLDAP; LDAP groups arrive as the `groups` claim and
# map to Vault EXTERNAL identity groups, which carry the policies. Door 2 and
# door 8 are decided here.
#
# Note: oidc_client_secret is stored (sensitive) in this module's state, which
# lives in .secrets/terraform/ (0600). Business values behind doors never are.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/vault-identity.tfstate"
  }
}

variable "vault_addr" {
  type    = string
  default = "https://vault.apps-crc.testing"
}

variable "vault_cacert" {
  type = string
}

variable "namespace" {
  type    = string
  default = "red-doors"
}

variable "ingress_ca_file" {
  description = "CRC ingress CA (Keycloak's edge Route certificate)"
  type        = string
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
}

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
  namespace    = var.namespace
}

locals {
  redirect_uris = [
    "https://doors.apps-crc.testing/auth/callback",                    # Red Doors UI (BFF)
    "https://vault.apps-crc.testing/ui/vault/auth/oidc/oidc/callback", # Vault UI
    "http://localhost:8250/oidc/callback",                             # vault login -method=oidc
  ]
  # external group (= Keycloak/LDAP group name) → policies
  groups = {
    board      = ["door-2"]
    requesters = ["door-8-request"]
    approvers  = ["door-8-approve"]
    auditors   = ["auditor"]
  }
}

resource "vault_policy" "human" {
  for_each = { for f in fileset("${path.module}/policies", "*.hcl") : trimsuffix(f, ".hcl") => f }
  name     = each.key
  policy   = file("${path.module}/policies/${each.value}")
}

resource "vault_jwt_auth_backend" "oidc" {
  path                  = "oidc"
  type                  = "oidc"
  description           = "People — Keycloak realm red-doors (LDAP-federated)"
  oidc_discovery_url    = "https://keycloak.apps-crc.testing/realms/red-doors"
  oidc_discovery_ca_pem = file(var.ingress_ca_file)
  oidc_client_id        = "vault"
  oidc_client_secret    = var.oidc_client_secret
  default_role          = "visitor"
  tune {
    listing_visibility = "unauth" # shows "OIDC" on the Vault UI login page
    default_lease_ttl  = "30m"
    max_lease_ttl      = "2h"
    token_type         = "default-service"
  }
}

resource "vault_jwt_auth_backend_role" "visitor" {
  backend               = vault_jwt_auth_backend.oidc.path
  role_name             = "visitor"
  role_type             = "oidc"
  user_claim            = "preferred_username"
  groups_claim          = "groups"
  oidc_scopes           = ["openid", "profile", "email"]
  allowed_redirect_uris = local.redirect_uris
  claim_mappings = {
    preferred_username = "username"
    name               = "name"
    email              = "email"
  }
  token_policies = ["door-visitor"]
  token_ttl      = 1800
  token_max_ttl  = 7200
  depends_on     = [vault_policy.human]
}

resource "vault_identity_group" "external" {
  for_each = local.groups
  name     = each.key
  type     = "external"
  policies = each.value
  metadata = { source = "keycloak/ldap" }
}

resource "vault_identity_group_alias" "external" {
  for_each       = local.groups
  name           = each.key
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.external[each.key].id
}

# ── Door 8: two different people (Sentinel EGP) ──────────────────────────────
resource "vault_egp_policy" "door_8_two_different_people" {
  name              = "door-8-two-different-people"
  paths             = ["doors/data/8-launch-codes"]
  enforcement_level = "hard-mandatory"
  policy            = file("${path.module}/sentinel/door-8-two-different-people.sentinel")
}
