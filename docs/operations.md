# Operations

## Lifecycle

| Command | Does | Data |
| --- | --- | --- |
| `make up` | brings everything to the desired state in 15 idempotent steps; `make up FROM=N` resumes at step N | creates what is missing, changes nothing that is converged |
| `make verify` | 40 ✓/✗ checks, including every door owner-opens / wrong-key-refused; exits non-zero on any ✗ | read-only (knocks are real) |
| `make down` | scales apps/doors/data/identity to 0, scales both Vaults to 0, `crc stop` | **keeps** every PVC and `.secrets/` |
| `make reset` | **destructive**: deletes all `rd-*` namespaces (PVCs included), the VSO subscription, and generated state in `.secrets/` (keeps the pull secret); asks you to type `red-doors` | gone |
| `make scenarios` | runs scenarios 01–06; stops at the first FAIL | scenario 02 leaves the seal Vault unsealed again |

After `make down`, `make up` unseals the seal Vault from
`.secrets/vault/seal-init.json`; the main cluster then unseals itself.
After `make reset`, `make up` builds a fresh estate (new keys, new
passwords).

## Every make target

`make help` prints them. Grouped:

| Area | Targets |
| --- | --- |
| OpenShift Local | `crc-up`, `crc-down`, `crc-status` (alias `status`), `crc-console`, `oc-login`, `namespaces` |
| TLS | `tls`: project CA + Vault server certs, renewed when < 30 days remain |
| Vault | `vault-up`, `vault-unseal`, `vault-status`, `seal-token-status`, `vault-roll`, `vault-down`, `vault-ui` |
| Vault config (Terraform) | `tf-bootstrap`, `vault-admin-token`, `tf-audit`, `door-identities`, `tf-doors`, `seed`, `tf-all` |
| Identity | `identity-up`, `demo-users` |
| Data + VSO | `data-up`, `vso-up`, `door7-rotate`, `door7-status` |
| Doors | `openers-up`, `knock DOOR=n`, `knock-wrong DOOR=n` |
| API | `api-up`, `api-test` (unit, no cluster), `api-smoke` (39 live checks) |
| UI | `ui-up`, `ui-open`, `trust` / `untrust` / `trust-status` (macOS keychain), `ui-test` (25 Playwright journeys + axe), `ui-test-failover`, `ui-screens` |
| Estate | `up`, `down`, `verify`, `scenarios`, `reset` |

Builds happen inside the cluster and only when the source hash changes
(stored on the ImageStream as `red-doors/source-hash`).

## Where secrets live

All local state is under `.secrets/` (gitignored, never committed;
gitleaks runs on every commit):

| Path | Holds |
| --- | --- |
| `.secrets/crc/pull-secret.json` | Red Hat pull secret (you provide it) |
| `.secrets/kube/config` | CRC system:admin client-cert kubeconfig (copied by `make crc-up` / `oc-login`) |
| `.secrets/vault/seal-init.json` | seal Vault unseal key + root token. **Losing it means losing the estate** |
| `.secrets/vault/cluster-init.json` | main cluster recovery keys + root token |
| `.secrets/vault/admin-token` | periodic admin token (policy `rd-admin`) used by Terraform and scripts |
| `.secrets/tls/` | CA and server private keys (public certs are in `vault-tls/`) |
| `.secrets/identity/` | LDAP/Keycloak admin passwords, demo users, OIDC client secret |
| `.secrets/data/` | PostgreSQL owner/admin passwords and the vault_admin rotation marker |
| `.secrets/terraform/` | Terraform state per module (contains sensitive values) |
| `lics/vault.hclic` | Vault Enterprise licence (you provide it) |

Door values live only in Vault. The API stores attempts and audit
entries, never a released value.

## Renewals

| What | Lifetime | Renewed by |
| --- | --- | --- |
| seal token (Transit auto-unseal) | periodic, 720 h | the main cluster renews it while it runs; `make up` re-issues it below 1 h; `make seal-token-status` shows it |
| admin token | periodic, 720 h | `make vault-admin-token` (step 5 of `make up`) re-issues when missing or expiring |
| Vault TLS certs | project CA | `make tls` (step 3) renews when < 30 days remain, then roll with `make vault-roll` |
| door 5 client certs | 10 min, one per knock | issued per knock; nothing to renew |
| machine tokens | 2–5 min, revoked after each knock | — |
| API's PostgreSQL login | 1 h lease | re-minted at 2/3 of the lease (wall clock) and on any refused login |
| people's sessions | the Vault OIDC token TTL | sign in again |
| Vault licence | see `make vault-status` | replace `lics/vault.hclic`, then `make vault-up` |

## Adding a ninth door

1. **Business item:** add a value to `scripts/seed-doors.sh` (generated, not
   literal text; it is written only if absent).
2. **Vault:** a policy in `terraform/vault-doors/policies/door-9.hcl` and the
   auth method/role in `terraform/vault-doors/` (for a pod: a new entry in
   `local.k8s_roles`). `make tf-doors`.
3. **Identity:** a service account in `deploy/doors/serviceaccounts.yaml`
   (`make door-identities`).
4. **Opener:** a handler in `openers/src/doors.js` and a Deployment in
   `deploy/doors/openers.yaml` (copy opener-1: `restricted-v2`, projected
   token with audience `vault`). `make openers-up`.
5. **API:** register it in `api/src/registry.js` (title, method, owner,
   wrong key, story position). `rd-api` can already read any `door-*`
   policy for display. `make api-up`.
6. **UI:** add a line to `ui/app/utils/narrative.ts`. The corridor, door
   pages and decision panel are data-driven. `make ui-up`.
7. **Prove it:** add the door to `scripts/verify-stack.sh` and
   `ui/tests/doors.spec.ts`; `make verify && make ui-test`.

## Logs

- Vault audit (stdout device): `oc -n rd-vault logs vault-0 | grep '"type":"response"'`
- API: `oc -n rd-app logs deploy/red-doors-api`
- Openers: `oc -n rd-doors logs deploy/opener-4`
- Use `KUBECONFIG=.secrets/kube/config` and `eval "$(crc oc-env)"` in a
  plain shell.
