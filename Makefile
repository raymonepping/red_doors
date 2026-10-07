# Red Doors — Vault Enterprise on OpenShift Local.
# Every target is idempotent. `make help` lists them.
SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help crc-up crc-down crc-status crc-console oc-login namespaces status

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "; printf "Red Doors (OpenShift Local)\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── OpenShift Local (prompt 01) ─────────────────────────────────────────────
crc-up: ## Configure + start OpenShift Local (8 vCPU / 24 GB / 80 GB), refresh .secrets/kube/config
	@./scripts/crc.sh up

crc-down: ## Stop OpenShift Local (keeps the VM and all cluster data)
	@./scripts/crc.sh down

crc-status: ## Show CRC, node, cluster-operator and Red Doors pod health
	@./scripts/crc.sh status

crc-console: ## Print console URL + credentials and open the web console
	@./scripts/crc.sh console

oc-login: ## Refresh .secrets/kube/config from a running CRC (system:admin client cert)
	@./scripts/crc.sh login

namespaces: ## Create/update the six rd-* namespaces
	@source scripts/lib.sh && require_kubeconfig && oc apply -f deploy/base/namespaces.yaml

status: crc-status ## Alias for crc-status

# ── Vault: seal chain + main cluster (prompt 02) ────────────────────────────
.PHONY: tls vault-up vault-unseal vault-status seal-token-status vault-roll vault-down vault-ui

tls: ## Create/renew the project CA + Vault server certs and load them into the cluster
	@./scripts/tls.sh

vault-up: ## Seal Vault → transit key + periodic token → 3-node Vault Enterprise (idempotent)
	@./scripts/vault.sh up

vault-unseal: ## Unseal the seal Vault (the main cluster then unseals itself)
	@./scripts/vault.sh unseal

vault-status: ## Seal Vault, seal token, main nodes (leader/standby), Raft peers, licence
	@./scripts/vault.sh status

seal-token-status: ## TTL and renewal of the transit seal token
	@./scripts/vault.sh seal-token-status

vault-roll: ## Rolling restart of the main cluster (standbys first, leader last) — applies config changes
	@./scripts/vault.sh roll

vault-down: ## Scale both Vaults to 0 — PVCs are never deleted
	@./scripts/vault.sh down

vault-ui: ## Open the main Vault UI (https://vault.apps-crc.testing)
	@./scripts/vault.sh ui

# ── Vault configuration: Terraform baseline (prompt 03) ─────────────────────
.PHONY: tf-bootstrap vault-admin-token tf-audit tf-doors door-identities seed tf-all

tf-bootstrap: ## Root, once: namespace red-doors + policy rd-admin, then a periodic admin token
	@./scripts/vault-admin.sh bootstrap

vault-admin-token: ## Ensure .secrets/vault/admin-token is valid (re-issue if missing/expiring)
	@./scripts/vault-admin.sh token

tf-audit: ## Audit devices: stdout always; socket → API collector once the API runs (prompt 07)
	@./scripts/audit.sh

door-identities: ## Service accounts in rd-doors that Vault's Kubernetes auth roles bind to
	@source scripts/lib.sh && require_kubeconfig && oc apply -f deploy/doors/serviceaccounts.yaml

tf-doors: door-identities ## Engines, auth methods, roles and per-door policies in namespace red-doors
	@./scripts/tf.sh vault-doors

seed: ## Write the business items behind the doors (only if absent — never changes them)
	@./scripts/seed-doors.sh

tf-all: tf-bootstrap tf-audit tf-doors seed ## All of the above, in order

# ── Identity: OpenLDAP + Keycloak + Vault OIDC (prompt 04) ──────────────────
.PHONY: identity-up demo-users

identity-up: ## OpenLDAP (built in-cluster) + Keycloak + realm/federation/client + Vault OIDC & groups (idempotent)
	@./scripts/identity.sh up

demo-users: ## Print the demo users, their groups and passwords (presenter aid)
	@./scripts/identity.sh users

# ── Data + Vault Secrets Operator (prompt 05) ───────────────────────────────
.PHONY: data-up vso-up door7-rotate door7-status

data-up: ## PostgreSQL + schema + Vault database engine (door 4) + merger ciphertext (door 6)
	@./scripts/data.sh up

vso-up: ## Vault Secrets Operator from OperatorHub + door-7 VaultStaticSecret
	@./scripts/vso.sh up

door7-rotate: ## Write a new customer-DB password in Vault — watch VSO sync it into OpenShift
	@./scripts/vso.sh rotate

door7-status: ## VaultStaticSecret + synced Secret metadata (never the value)
	@./scripts/vso.sh status

# ── Door openers (prompt 06) ────────────────────────────────────────────────
.PHONY: openers-up knock knock-wrong

openers-up: ## Build (in-cluster, on change) and deploy the seven door openers
	@./scripts/doors.sh up

knock: ## Knock on a machine door as its owner: make knock DOOR=4
	@./scripts/doors.sh knock $(DOOR)

knock-wrong: ## Same door, the impostor's identity: make knock-wrong DOOR=4
	@./scripts/doors.sh knock-wrong $(DOOR)

# ── API (prompt 07) ─────────────────────────────────────────────────────────
.PHONY: api-up api-test api-smoke

api-up: ## Vault identity rd-api, build (in-cluster, on change), deploy, then the socket audit device
	@./scripts/api.sh up

api-test: ## Unit tests (synthetic audit fixtures) — no cluster needed
	@cd api && npm test

api-smoke: ## Live smoke test of every endpoint through the real cluster
	@./scripts/api-smoke.sh

# ── UI + BFF (frontend 01_01) ───────────────────────────────────────────────
.PHONY: ui-up ui-open ui-test ui-test-failover ui-screens

ui-up: ## Build (in-cluster, on change) and deploy the UI + BFF → https://doors.apps-crc.testing
	@./scripts/ui.sh up

ui-open: ## Open the Red Doors UI
	@open https://doors.apps-crc.testing

ui-test: ## Playwright journeys + axe gate against the live UI (real OIDC, real Vault)
	@cd ui && npx playwright test

ui-test-failover: ## Playwright @failover: delete the active Vault pod, expect a new leader
	@cd ui && RD_ALL=1 RD_FAILOVER=1 npx playwright test --grep @failover

ui-screens: ## Every screen at 1440×900 and 390×844 → docs/screenshots/ui/
	@cd ui && RD_ALL=1 npx playwright test --grep @screens

# ── Whole estate (prompt 08) ────────────────────────────────────────────────
.PHONY: up down verify scenarios reset

up: ## Bring EVERYTHING to the desired state (idempotent); resume with: make up FROM=N
	@./scripts/rehydrate.sh $(if $(FROM),--from $(FROM),)

down: ## Stop everything and CRC — no data is deleted
	@./scripts/down.sh

verify: ## ✓/✗ health of the whole estate, incl. every door owner-opens / wrong-key-refused
	@./scripts/verify-stack.sh

scenarios: ## Run resilience scenarios 01–06 (each prints PASS/FAIL)
	@for s in scenarios/0*/run.sh; do $$s || exit 1; done

reset: ## DESTRUCTIVE: delete all Red Doors data (asks you to type red-doors)
	@./scripts/reset.sh
