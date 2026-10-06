# Door 4 — Payroll database.
# Lets the door-4 opener mint a short-lived PostgreSQL login for the payroll table. Nothing else.
path "database/creds/payroll-reader" {
  capabilities = ["read"]
}
