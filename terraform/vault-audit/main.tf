# terraform/vault-audit — audit devices (root namespace).
#
# `stdout` (file device → container stdout) was enabled by scripts/vault.sh
# right after init so nothing went unaudited before Terraform; it is adopted
# into state here, never recreated.
#
# The `socket` device to the API's collector is added in prompt 07: Vault
# refuses to enable a socket device it cannot connect to. Vault only blocks a
# request if EVERY audit device fails, so stdout keeps Vault serving while the
# collector restarts.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "../../.secrets/terraform/vault-audit.tfstate"
  }
}

variable "vault_addr" {
  type    = string
  default = "https://vault.apps-crc.testing"
}

variable "vault_cacert" {
  type = string
}

# Prompt 07 sets this to "red-doors-api-audit.rd-app.svc:9090".
variable "audit_socket_address" {
  type    = string
  default = ""
}

provider "vault" {
  address      = var.vault_addr
  ca_cert_file = var.vault_cacert
}

import {
  to = vault_audit.stdout
  id = "stdout"
}

resource "vault_audit" "stdout" {
  path = "stdout"
  type = "file"
  options = {
    file_path = "stdout"
  }
}

# Streams every audit record to the Red Doors API's collector (prompt 07).
# Two devices on purpose: Vault blocks a request only if EVERY device fails,
# so stdout keeps Vault serving while the collector restarts.
resource "vault_audit" "collector" {
  count = var.audit_socket_address == "" ? 0 : 1
  path  = "red-doors-collector"
  type  = "socket"
  options = {
    address       = var.audit_socket_address
    socket_type   = "tcp"
    format        = "json"
    write_timeout = "2s"
  }
}
