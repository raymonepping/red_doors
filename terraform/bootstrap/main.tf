# terraform/bootstrap — run ONCE with the root token (scripts/vault-admin.sh).
#
# Creates the Enterprise namespace `red-doors` (every door lives there) and
# the `rd-admin` policy. The periodic admin token itself is minted by
# scripts/vault-admin.sh — never by Terraform, so it never lands in state.
# After this module, root is not used for routine work.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/bootstrap.tfstate"
  }
}

variable "vault_addr" {
  type    = string
  default = "https://vault.apps-crc.testing"
}

variable "vault_cacert" {
  type = string
}

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
  # VAULT_TOKEN comes from the environment (root, bootstrap only)
}

resource "vault_namespace" "red_doors" {
  path = "red-doors"
}

# Routine administration for this demo: everything, everywhere (incl. child
# namespaces). Held by a periodic token in .secrets/vault/admin-token so the
# root token can stay in its envelope.
resource "vault_policy" "rd_admin" {
  name   = "rd-admin"
  policy = <<-EOT
    # Red Doors operator — full administration of the root and red-doors namespaces.
    path "*" {
      capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
    }
  EOT
}

output "namespace" {
  value = vault_namespace.red_doors.path_fq
}
