# The impostor — a real, authenticated identity with no business behind any door.
# It may read the lobby notice. Every door refusal it gets is Vault policy, not UI logic.
path "doors/data/0-lobby" {
  capabilities = ["read"]
}
