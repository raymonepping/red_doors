# terraform/vault-database — door 4 (prompt 05), namespace red-doors.
#
# Vault holds the only PostgreSQL credential that can mint logins
# (vault_admin, not a superuser). Its initial password is passed WRITE-ONLY
# (password_wo: never stored in state, sent only when password_wo_version
# changes) and scripts/data.sh rotates it with database/rotate-root right
# after — from then on only Vault knows it, and a later apply never resends
# a stale value.
terraform {
  required_version = ">= 1.11" # write-only arguments
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/vault-database.tfstate"
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

variable "vault_admin_password" {
  description = "Initial vault_admin password (write-only; rotated by Vault immediately)"
  type        = string
  ephemeral   = true
}

variable "vault_admin_password_version" {
  description = "Bump to resend vault_admin_password (only after re-creating the DB role)"
  type        = number
  default     = 1
}

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
  namespace    = var.namespace
}

resource "vault_mount" "database" {
  path        = "database"
  type        = "database"
  description = "Door 4 — PostgreSQL logins minted per knock"
}

resource "vault_database_secret_backend_connection" "reddoors" {
  backend       = vault_mount.database.path
  name          = "reddoors"
  allowed_roles = ["payroll-reader", "api-rw"]
  # In-cluster service; demo-grade without TLS inside the cluster network.
  verify_connection = true

  postgresql {
    connection_url       = "postgresql://{{username}}:{{password}}@postgres.rd-data.svc:5432/reddoors?sslmode=disable"
    username             = "vault_admin"
    password_wo          = var.vault_admin_password
    password_wo_version  = var.vault_admin_password_version
    max_open_connections = 4
  }
}

# A login that can SELECT payroll and nothing else, valid for minutes.
# Revocation ends its sessions and drops it.
resource "vault_database_secret_backend_role" "payroll_reader" {
  backend = vault_mount.database.path
  name    = "payroll-reader"
  db_name = vault_database_secret_backend_connection.reddoors.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT CONNECT ON DATABASE reddoors TO \"{{name}}\";",
    "GRANT SELECT ON payroll TO \"{{name}}\";",
  ]
  revocation_statements = [
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}';",
    "REVOKE ALL ON payroll FROM \"{{name}}\";",
    "REVOKE CONNECT ON DATABASE reddoors FROM \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]
  default_ttl = 300
  max_ttl     = 600
}
