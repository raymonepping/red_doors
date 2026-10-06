# Door 3 — Partner API key.
# Lets a door-3 AppRole login (single-use secret-id) read the partner API key. Nothing else.
path "doors/data/3-partner-api-key" {
  capabilities = ["read"]
}
