# Door 1 — Production deploy key.
# Lets the door-1 opener (Kubernetes SA rd-doors/opener-1) read the deploy key. Nothing else.
path "doors/data/1-production-deploy-key" {
  capabilities = ["read"]
}
