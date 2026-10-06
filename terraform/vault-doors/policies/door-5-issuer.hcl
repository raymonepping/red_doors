# Door 5 — the key cutter.
# Lets SA rd-doors/opener-5 issue a 10-minute client certificate. It cannot open the door:
# only the certificate can (see policy door-5, granted by the cert auth method).
path "pki-int/issue/treasury-client" {
  capabilities = ["update"]
}
