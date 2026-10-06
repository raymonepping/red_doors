# Door 8 — Approvers may look at and authorize pending launch-code requests. They cannot read the codes.
path "sys/control-group/authorize" {
  capabilities = ["update"]
}
path "sys/control-group/request" {
  capabilities = ["update"]
}
