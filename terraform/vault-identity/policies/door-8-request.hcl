# Door 8 — Launch codes. Requesters may READ, but only after a second person approves:
# Vault answers with a wrapped, pending response until one member of "approvers" authorizes it.
path "doors/data/8-launch-codes" {
  capabilities = ["read"]
  control_group = {
    ttl = "10m"
    factor "two-person" {
      identity {
        group_names = ["approvers"]
        approvals   = 1
      }
    }
  }
}
