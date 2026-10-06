# Prompt 03 — Vault baseline (Terraform): engines, auth, per-door policies

## Context

Prompt 02 is done: 3-node Vault Enterprise reachable at
`https://vault.apps-crc.testing` (CA `vault-tls/ca.pem`), auto-unsealed by
the seal Vault. Root token in `.secrets/vault/cluster-init.json`.

Design rule (from Arcanium):

```text
Terraform  → foundational desired state (mounts, auth methods, roles, policies)
scripts    → bootstrap + secret VALUES (never in Terraform state)
API/openers → runtime (logins, reads, requests)
```

## Goal

Everything Vault needs for doors 1, 3, 5 and 6, plus the shared plumbing
for the rest, configured idempotently, with least-privilege policies that
are short enough to show on screen.

## Deliverables

### Admin access (`terraform/bootstrap/`)

- Root is for bootstrap only. Create policy `rd-admin` and a **periodic**
  admin token (`period=24h`) stored in `.secrets/vault/admin-token`; all
  later Terraform and scripts use it. `make vault-admin-token` re-issues it.
  (Lesson from Editors Factory: root as a routine credential widens blast
  radius; and when the admin token is stale, ask the operator rather than
  silently escalating to root.)

### Vault namespace

- Enterprise namespace **`red-doors`** holds every door's config (keeps the
  root namespace for platform/admin; demonstrates an Enterprise feature).
  Every module below targets it.

### Audit (`terraform/vault-audit/`)

- `file` device to stdout (`file_path=stdout`) — already enabled in prompt 02;
  adopt it into state, don't recreate.
- The `socket` device to the API's collector is added in **prompt 07**
  (Vault refuses to enable a socket device it cannot connect to). Leave a
  variable + comment here so it's obvious where it goes.

### Engines and auth methods (`terraform/vault-doors/`)

| Mount | Type | For |
|---|---|---|
| `doors/` | KV v2 | items behind doors 1, 2, 3, 5, 7, 8 |
| `transit/` | Transit | key `merger-docs` (door 6), `exportable=false`, `deletion_allowed=false` |
| `pki/`, `pki-int/` | PKI | root + intermediate CA "Red Doors Treasury CA"; role `treasury-client` (client certs only, `ttl=10m`, `max_ttl=30m`, CN pattern `opener-5.rd-doors`) |
| `kubernetes/` | Kubernetes auth | configured against the cluster API with the in-cluster CA + a token-reviewer SA in `rd-vault` |
| `approle/` | AppRole | door 3 |
| `cert/` | TLS cert auth | door 5; trusts `pki-int`'s chain only |

Kubernetes auth roles (each bound to **one** service account in `rd-doors`,
`token_ttl=5m`, `token_max_ttl=15m`, audience set):

| Role | SA | Policy |
|---|---|---|
| `opener-1` | `opener-1` | `door-1`: `read` on `doors/data/1-production-deploy-key` |
| `opener-4` | `opener-4` | `door-4`: `read` on `database/creds/payroll-reader` (engine in prompt 05) |
| `opener-5-issuer` | `opener-5` | `door-5-issuer`: `update` on `pki-int/issue/treasury-client` **only** — the SA can cut a key but cannot open the door |
| `opener-6` | `opener-6` | `door-6`: `update` on `transit/decrypt/merger-docs` only |
| `vso-door-7` | VSO's SA (prompt 05) | `door-7`: `read` on `doors/data/7-customer-db-password` |

AppRole `door-3`: `secret_id_num_uses=1`, `secret_id_ttl=5m`,
`token_ttl=5m`, policy `door-3` (`read` on `doors/data/3-partner-api-key`).
**Bound the user lockout** (e.g. threshold 3, duration 30s) — the default
15-minute lockout outlasts any demo retry (lesson: AppRole user lockout).

Cert auth role `treasury`: `allowed_common_names=opener-5.rd-doors`,
`token_ttl=2m`, policy `door-5` (`read` on `doors/data/5-treasury-wire-room`).

Door 2 (OIDC) and door 8 (control group) are configured in prompt 04
because they depend on identity groups.

### Wrong-key identities (needed for the denial demos)

- Kubernetes role `impostor` bound to SA `impostor` in `rd-doors` with a
  policy that grants nothing behind any door — so its denials are real
  Vault 403s, not UI logic.
- Document per door which identity is the "wrong key" (the master prompt's
  table) and make sure Vault, not the API, produces the denial.

### Policy hygiene

- One policy file per door under `terraform/vault-doors/policies/*.hcl`,
  ≤ 10 lines each, with a header comment in plain English ("lets the
  door-4 opener mint a 5-minute payroll login, nothing else"). The UI shows
  these verbatim.
- Never round-trip `token_policies` through `vault read -field` (lesson);
  always declare the full list in Terraform.

### Secret values (`scripts/seed-doors.sh`, `make seed`)

Writes the business items with **generated** values (random, realistic
shape) only if absent, so reruns never change them:

- `1-production-deploy-key` (an SSH-style deploy key fingerprint + key id)
- `2-board-minutes` (a short minutes text + meeting id)
- `3-partner-api-key` (`pk_live_…`-style token)
- `5-treasury-wire-room` (wire approval code)
- `7-customer-db-password` (password + rotation date)
- `8-launch-codes` (code block)
- Door 6: encrypt a short "merger memo" with `transit/encrypt/merger-docs`
  and store **only the ciphertext** (in Postgres in prompt 05; until then in
  a ConfigMap `merger-docs` in `rd-doors`). The plaintext is not stored
  anywhere else.

Values never land in Terraform state, git or logs.

### Make

`make tf-bootstrap`, `make tf-audit`, `make tf-doors`, `make seed`;
`make tf-all` runs them in order. Provider: Route address + `vault-tls/ca.pem`.

## Validation

```sh
make tf-all && make tf-all        # second run: "No changes"
vault policy read -namespace=red-doors door-6     # short, readable, decrypt-only
# door 1 end-to-end with a throwaway pod using SA opener-1:
#   kubernetes login → read doors/data/1-production-deploy-key → OK
# same with SA impostor → 403 permission denied (from Vault)
# door 3: wrapped secret-id → unwrap once → login → read → OK; second unwrap → fails
# door 5: issue cert via opener-5-issuer → cert login → read → OK; cert after TTL → denied
# door 6: decrypt with opener-6 → plaintext; encrypt with opener-6 → 403
```

Record every validation output in the execution log.

## Out of scope

OIDC, control groups, database engine, VSO (prompts 04–05).

## Execution log

Appended by each run: what was done, deviations and why, validation output.
