# terraform/vault-doors — everything behind the machine doors (1, 3, 4, 5, 6, 7),
# in the Enterprise namespace `red-doors`.
#
# Desired state only: mounts, auth methods, roles, policies. The VALUES behind
# the doors are written by scripts/seed-doors.sh and never touch Terraform state.
# Doors 2 and 8 (humans) are added in prompt 04, the database engine in 05.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/vault-doors.tfstate"
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

variable "doors_k8s_namespace" {
  description = "OpenShift namespace holding the door openers"
  type        = string
  default     = "rd-doors"
}

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
  namespace    = var.namespace
  # VAULT_TOKEN = .secrets/vault/admin-token (scripts/tf.sh)
}

# ── Policies: one short file per door, shown verbatim in the UI ──────────────
locals {
  policy_files = fileset("${path.module}/policies", "*.hcl")
}

resource "vault_policy" "door" {
  for_each = { for f in local.policy_files : trimsuffix(f, ".hcl") => f }
  name     = each.key
  policy   = file("${path.module}/policies/${each.value}")
}

# ── KV v2: the business items behind doors 0 (lobby), 1, 3, 5, 7 (+2, 8 later) ─
resource "vault_mount" "doors" {
  path        = "doors"
  type        = "kv"
  options     = { version = "2" }
  description = "Red Doors — what lies behind each door"
}

# ── Transit: door 6 ─────────────────────────────────────────────────────────
resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Door 6 — merger documents are stored only as ciphertext"
}

resource "vault_transit_secret_backend_key" "merger_docs" {
  backend          = vault_mount.transit.path
  name             = "merger-docs"
  type             = "aes256-gcm96"
  exportable       = false
  deletion_allowed = false
}
