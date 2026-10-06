# Prompt 05 — PostgreSQL + dynamic credentials (door 4), Vault Secrets Operator (door 7)

## Context

Prompts 01–04 are done. Reuse Editors Factory's Postgres dynamic-creds work
(`../editors_factory/prompts/base_project/03_01_postgres_dynamic_creds.md`)
and Arcanium's database engine setup.

## Goal

Door 4 mints a PostgreSQL login per knock and proves it by querying the
payroll table with it. Door 7 shows the "app never talks to Vault" pattern
with the certified Vault Secrets Operator from OperatorHub.

## Deliverables

### PostgreSQL (`deploy/data/postgres.yaml`, namespace `rd-data`)

- An arm64, OpenShift-friendly Postgres image (e.g. Red Hat's
  `registry.redhat.io/rhel9/postgresql-16` if the pull secret covers it, or
  an upstream multi-arch image that tolerates a random UID) — record the
  choice + digest. PVC-backed. Service `postgres.rd-data.svc`.
- Database `reddoors`, schema:
  - `payroll(employee_id, name, department, monthly_salary_eur, iban_masked)`
    seeded with ~20 realistic rows (generated, not real people).
  - `merger_docs(id, title, ciphertext, key_version, created_at)` — the door 6
    ciphertext moves here from the ConfigMap; plaintext is never stored.
  - `door_attempts` / `audit_entries` are owned by the API's own schema
    (prompt 07) — create an empty `api` schema + login role for it.
- A `vault_admin` role Vault uses to create users (`CREATEROLE`, grants on
  `payroll` only — not superuser). Password generated into `.secrets/` and
  **rotated by Vault** right after configuration (`rotate-root`), so no
  human knows it afterwards.
- Lesson: test credentials via `postgres.rd-data.svc`, never `127.0.0.1`
  inside the pod (loopback is `trust` in the image and proves nothing).

### Door 4 — Payroll database (`terraform/vault-database/`)

- `database/` engine, connection `reddoors` (verify connection on apply).
- Role `payroll-reader`: `CREATE ROLE "{{name}}" WITH LOGIN PASSWORD
  '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON payroll TO
  "{{name}}";`, `default_ttl=5m`, `max_ttl=10m`, revocation statement that
  terminates sessions and drops the role.
- The opener (prompt 06) revokes its lease right after the query; the UI
  shows the generated username, lease ID (truncated), TTL and "revoked at".
- Wrong key: the `impostor` SA → 403 from Vault on `database/creds/payroll-reader`.

### Vault Secrets Operator (door 7)

- Install **from OperatorHub** (certified "Vault Secrets Operator",
  channel stable) via a `Subscription` in `openshift-operators` — scripted
  with `oc apply`, waiting for the CSV to be `Succeeded`. Show it in the web
  console for the demo.
- `VaultConnection` (address `https://vault-active.rd-vault.svc:8200`, CA
  from a Secret) and `VaultAuth` (kubernetes method, role `vso-door-7`,
  namespace `red-doors`, its own SA in `rd-doors`).
- `VaultStaticSecret` → `Secret door-7-customer-db` in `rd-doors`,
  `refreshAfter: 30s`, `rolloutRestartTargets` pointing at the opener-7
  Deployment.
- Demo moment: change the value in Vault (`make door7-rotate`) → within
  ~30s the OpenShift `Secret` changes → opener-7 rolls → the door shows the
  new value and the sync timestamp. The opener-7 pod has **no** Vault
  address, token or role.
- Wrong key: an opener in a namespace without a `VaultStaticSecret` (or the
  impostor SA) has no way to read it — show that the `Secret` simply
  doesn't exist there.

## Validation

```sh
make data-up && make data-up
# door 4: login as opener-4 (throwaway pod) → database/creds/payroll-reader → psql via the service host → SELECT count(*) FROM payroll → revoke lease → login with same creds fails
make vso-up
oc -n rd-doors get vaultstaticsecret,secret door-7-customer-db -o wide
make door7-rotate     # Secret data changes within ~30s; opener-7 restarted
```

## Out of scope

The opener code itself (prompt 06).

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 1 — 2026-10-06

#### Done

- PostgreSQL `registry.redhat.io/rhel9/postgresql-16` (arm64 in the
  manifest list; pulled with the cluster pull secret), `restricted-v2`,
  PVC, Service `postgres.rd-data.svc`. `deploy/data/schema.sql`
  (idempotent): `payroll` (20 generated rows), `merger_docs` (CHECK
  `ciphertext LIKE 'vault:v%'`), schema `api` owned by NOLOGIN `api_owner`,
  role `vault_admin` (LOGIN CREATEROLE, SELECT on payroll WITH GRANT OPTION,
  `pg_signal_backend`, `api_owner` WITH ADMIN OPTION — not superuser).
- `terraform/vault-database`: `database/` mount, connection `reddoors`
  (`verify_connection`), role `payroll-reader` (5 min / max 10 min,
  revocation terminates sessions and drops the role).
- `scripts/data.sh` (`make data-up`): secrets, deploy, schema, first-run
  vault_admin password → Terraform → `database/rotate-root` once (marker
  `.secrets/data/vault-admin.rotated`), door-6 ciphertext into
  `merger_docs` (migrated from the prompt-03 ConfigMap, which is then
  deleted; a fresh install encrypts a newly generated memo here).
- VSO: `deploy/base/vso-subscription.yaml` (certified, `stable`,
  v1.6.0), `deploy/doors/vso.yaml` (VaultConnection with CA Secret,
  VaultAuth kubernetes/`vso-door-7`, VaultStaticSecret → Secret
  `door-7-customer-db`, refresh 30s); `scripts/vso.sh`
  (`make vso-up | door7-rotate | door7-status`).

#### Deviations

- **vault_admin's initial password is write-only** (`password_wo` +
  `password_wo_version`, ephemeral variable, Terraform ≥ 1.11): never in
  state, and a later apply can't push a stale password over the one Vault
  rotated. Recovery after recreating the DB: delete the marker, rerun
  `make data-up` (bumps the version).
- **`scripts/tf.sh` unsets `VAULT_NAMESPACE`**: a caller exporting it made
  the provider prefix it on top of the module's own namespace
  (`red-doors/red-doors` → 403). Found live.
- Door-6 seeding moved from `seed-doors.sh` to `data.sh` so a later
  `make seed` can't recreate the ConfigMap with a different memo.
- `rolloutRestartTargets` for opener-7 deferred to prompt 06 (the
  Deployment doesn't exist yet).
- Postgres connection inside the cluster is `sslmode=disable` (demo-grade;
  in-cluster network only) — noted for the security-model doc.

#### Validation output

```text
make data-up (first)  → postgres ready, schema, vault-database 3 added, rotate-root, ciphertext moved, ConfigMap removed
make data-up (rerun)  → 0 changes, "owned by Vault since …", no NOTICE noise, no second rotation
make vso-up           → vault-secrets-operator.v1.6.0 Succeeded; Secret door-7-customer-db synced
door 4  opener-4 mints login v-red-door-payroll-…, ttl 300s ......... OK
        role in pg_roles, VALID UNTIL = lease expiry .................. OK
        SELECT from payroll over postgres.rd-data.svc ................. OK (20 rows)
        same login SELECT merger_docs ................................. permission denied
        revoke-self → role dropped from PostgreSQL .................... OK
        reuse of the login ............................................ FATAL password authentication failed
        impostor database/creds/payroll-reader ........................ 403
door 7  Secret labelled managed-by hashicorp-vso ..................... OK
        impostor reads doors/7 in Vault ............................... 403
        make door7-rotate → Secret value changed after 22 s ........... OK
RESULT: 11 passed, 0 failed
```
