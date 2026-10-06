# Door 5 — Treasury PKI: root CA → issuing CA → short-lived client certificates.
# The cert auth method (auth.tf) trusts this chain and nothing else.

resource "vault_mount" "pki" {
  path                  = "pki"
  type                  = "pki"
  description           = "Red Doors Treasury Root CA"
  max_lease_ttl_seconds = 10 * 365 * 86400
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Red Doors Treasury Root CA"
  ttl         = 10 * 365 * 86400
  key_type    = "ec"
  key_bits    = 256
  issuer_name = "treasury-root"
}

resource "vault_mount" "pki_int" {
  path                  = "pki-int"
  type                  = "pki"
  description           = "Red Doors Treasury Issuing CA — door 5 client certificates"
  max_lease_ttl_seconds = 5 * 365 * 86400
}

resource "vault_pki_secret_backend_intermediate_cert_request" "int" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Red Doors Treasury Issuing CA"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "int" {
  backend     = vault_mount.pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.int.csr
  common_name = "Red Doors Treasury Issuing CA"
  ttl         = 5 * 365 * 86400
  issuer_ref  = vault_pki_secret_backend_root_cert.root.issuer_id
}

resource "vault_pki_secret_backend_intermediate_set_signed" "int" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.int.certificate_bundle
}

# Client certs only, for exactly one name, 10 minutes by default. A fresh
# cert per knock (prompt 06) means no long-lived cert exists to expire.
resource "vault_pki_secret_backend_role" "treasury_client" {
  backend            = vault_mount.pki_int.path
  name               = "treasury-client"
  allowed_domains    = ["opener-5.rd-doors"]
  allow_bare_domains = true
  allow_subdomains   = false
  allow_any_name     = false
  enforce_hostnames  = false
  server_flag        = false
  client_flag        = true
  key_type           = "ec"
  key_bits           = 256
  ttl                = 600
  max_ttl            = 1800
  require_cn         = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.int]
}
