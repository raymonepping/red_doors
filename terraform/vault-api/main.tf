# terraform/vault-api — the Red Doors API's identity (prompt 07), namespace red-doors.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/vault-api.tfstate"
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

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
  namespace    = var.namespace
}

resource "vault_policy" "rd_api" {
  name   = "rd-api"
  policy = file("${path.module}/rd-api.hcl")
}

resource "vault_kubernetes_auth_backend_role" "api" {
  backend                          = "kubernetes"
  role_name                        = "red-doors-api"
  bound_service_account_names      = ["red-doors-api"]
  bound_service_account_namespaces = ["rd-app"]
  audience                         = "vault"
  token_ttl                        = 3600
  token_max_ttl                    = 14400
  token_policies                   = [vault_policy.rd_api.name]
}

# The API's own database logins: member of api_owner (owns schema api, may
# SELECT merger_docs ciphertext). Re-minted by the API at 2/3 of the lease.
resource "vault_database_secret_backend_role" "api_rw" {
  backend = "database"
  name    = "api-rw"
  db_name = "reddoors"
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT;",
    "GRANT api_owner TO \"{{name}}\";",
  ]
  revocation_statements = [
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}';",
    "REVOKE api_owner FROM \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]
  default_ttl = 3600
  max_ttl     = 86400
}
