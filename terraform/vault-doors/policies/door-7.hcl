# Door 7 — Customer database password.
# Lets the Vault Secrets Operator (for door 7) read the password and sync it into OpenShift.
path "doors/data/7-customer-db-password" {
  capabilities = ["read"]
}
