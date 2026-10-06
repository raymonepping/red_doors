# Door 6 — Merger documents.
# Lets the door-6 opener DECRYPT with the merger-docs key. It cannot encrypt, read or export the key.
path "transit/decrypt/merger-docs" {
  capabilities = ["update"]
}
