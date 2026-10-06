# Auth methods and the identities that may knock.

# ── Kubernetes auth: doors 1, 4, 5 (issuer), 6, 7 (VSO), impostor ────────────
# Vault runs in-cluster: with no CA / reviewer JWT given it uses its own pod's
# service-account token and CA (the chart grants it system:auth-delegator).
resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = "kubernetes"
  description = "OpenShift service accounts — a pod's projected token is its only credential"
}

resource "vault_kubernetes_auth_backend_config" "k8s" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc:443"
}

locals {
  # role => { service account in rd-doors, policies }
  k8s_roles = {
    "opener-1"        = { sa = "opener-1", policies = ["door-1"] }
    "opener-4"        = { sa = "opener-4", policies = ["door-4"] }
    "opener-5-issuer" = { sa = "opener-5", policies = ["door-5-issuer"] }
    "opener-6"        = { sa = "opener-6", policies = ["door-6"] }
    "vso-door-7"      = { sa = "vso-door-7", policies = ["door-7"] }
    "impostor"        = { sa = "impostor", policies = ["impostor"] }
  }
}

resource "vault_kubernetes_auth_backend_role" "door" {
  for_each                         = local.k8s_roles
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = [each.value.sa]
  bound_service_account_namespaces = [var.doors_k8s_namespace]
  audience                         = "vault"
  token_ttl                        = 300
  token_max_ttl                    = 900
  token_policies                   = each.value.policies # full list, never round-tripped
  depends_on                       = [vault_policy.door]
}

# ── AppRole: door 3 ─────────────────────────────────────────────────────────
resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Door 3 — role-id in the opener, single-use secret-id delivered response-wrapped"
}

# Lesson (AppRole user lockout): the default 5 failures → 15-minute lockout
# outlasts any demo retry. Bound it.
resource "vault_generic_endpoint" "approle_lockout" {
  path                 = "sys/auth/${vault_auth_backend.approle.path}/tune"
  disable_read         = true
  disable_delete       = true
  ignore_absent_fields = true
  data_json = jsonencode({
    user_lockout_config = {
      lockout_threshold     = "3"
      lockout_duration      = "30s"
      lockout_counter_reset = "30s"
    }
  })
}

resource "vault_approle_auth_backend_role" "door_3" {
  backend            = vault_auth_backend.approle.path
  role_name          = "door-3"
  secret_id_num_uses = 1
  secret_id_ttl      = 300
  token_ttl          = 300
  token_max_ttl      = 600
  token_policies     = ["door-3"]
  depends_on         = [vault_policy.door]
}

# ── TLS certificate auth: door 5 ────────────────────────────────────────────
resource "vault_auth_backend" "cert" {
  type        = "cert"
  path        = "cert"
  description = "Door 5 — the client certificate is the key; only the Treasury Issuing CA is trusted"
}

resource "vault_cert_auth_backend_role" "treasury" {
  backend              = vault_auth_backend.cert.path
  name                 = "treasury"
  certificate          = vault_pki_secret_backend_root_sign_intermediate.int.certificate_bundle
  allowed_common_names = ["opener-5.rd-doors"]
  token_ttl            = 120
  token_max_ttl        = 300
  token_policies       = ["door-5"]
  depends_on           = [vault_policy.door]
}

output "policies" {
  value = sort(keys(vault_policy.door))
}
