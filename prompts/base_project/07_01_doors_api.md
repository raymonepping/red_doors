# Prompt 07 — Red Doors API: knock orchestration, door 8 workflow, audit collector

## Context

Prompts 01–06 are done: openers knock successfully via `make knock`. Reuse
Arcanium's API conventions (`../arcanium/arcanium/api/`: Express 5 ESM,
contract-first OpenAPI in `openapi/`, migrations on startup, error
contract, `[req]` logging, OpenAPI → UI types) — not its business logic.

## Goal

One internal API (`red-doors-api` in `rd-app`) that the UI's server side
calls. It orchestrates knocks, runs the human doors with the **user's own**
Vault token, drives the door 8 two-person rule, collects Vault's audit
stream, and joins everything into attempts the UI can show.

Two distinctions the API must keep explicit in its data model:

- **Triggered by** (the signed-in person who pressed "knock") vs **opened
  by** (the identity Vault actually evaluated — e.g. `opener-4`).
- **Vault decided** (taken from Vault responses and audit entries) vs
  **API observed** (timings, which opener answered). The UI only shows the
  former as "how Vault decided".

## Deliverables

### Service shape

- Node 24, Express 5 ESM, `pg`; OpenAPI 3.1 at `openapi/red-doors.yaml`
  is the contract (UI types generated from it).
- Built in-cluster (`BuildConfig` + `ImageStream red-doors-api`,
  `make api-build`), Deployment + Service in `rd-app`, **no Route** (only
  the UI BFF reaches it; enforce with `NetworkPolicy`).
- Own Postgres schema `api` (role from prompt 05), migrations on startup,
  idempotent. DB credentials from Vault (`database/creds/api-rw` or a
  static role) — the API dogfoods Vault for its own DB access.

### Vault identity (`terraform/vault-api/`)

Kubernetes auth role `red-doors-api` (SA `red-doors-api`), policy `rd-api`:

- `update` on `auth/approle/role/door-3/secret-id` **with
  `min_wrapping_ttl = "30s"`, `max_wrapping_ttl = "2m"`** — it can only
  produce wrapped secret-ids; it never has the role-id.
- `read` on `sys/policies/acl/door-*` (show policy text), `sys/ha-status`,
  `sys/storage/raft/configuration`, `sys/health`.
- Nothing under `doors/`, `transit/`, `database/creds/payroll-reader`,
  `pki-int/issue/*`. Prove it in the validation.

### Kubernetes RBAC (SA `red-doors-api`)

- `get/list` pods in `rd-vault`, `rd-vault-seal`; `get` on
  `vaultstaticsecrets` and `secrets/door-7-customer-db` **metadata only**
  (use a `Role` limited to that resource name, and never read `.data` — the
  door 7 value comes from opener-7).

### Endpoints (`/api/v1`)

| Endpoint | Purpose |
| --- | --- |
| `GET /doors` | registry: id, title, business item, method, story order, policy names, status of last attempt |
| `GET /doors/:id` | detail incl. **policy text** read from Vault, owner/wrong-key identities, last N attempts |
| `POST /doors/:id/knock` | machine doors 1,3,4,5,6,7; body `{ "as": "owner" \| "impostor" }`; header `X-Triggered-By` (from BFF session). Door 3: mint wrapped secret-id → pass the wrapping token to opener-3 (or replay a consumed one to the impostor). Door 6: read ciphertext from `merger_docs` → pass to opener-6 |
| `POST /doors/2/open` | human door: the BFF forwards the **user's Vault token** in `X-Vault-Token`; the API reads `doors/data/2-board-minutes` with it and returns Vault's answer. The token is never stored or logged |
| `POST /doors/8/requests` | requester reads with their token → Vault returns `wrap_info` (control group). API stores **only** the accessor, requester entity, created/expiry; returns the wrapping token to the BFF, which keeps it in the requester's server-side session |
| `GET /doors/8/requests` | role-aware list; status per accessor via `sys/control-group/request` using the caller's token (approvers see approvals + remaining) |
| `POST /doors/8/requests/:accessor/approve` | `sys/control-group/authorize` with the **approver's** token. A requester's own authorization comes back `approved: false` (Sentinel EGP `door-8-two-different-people` ignores it) — surface it as "your own approval does not count", from Vault's response + the authorization list, not as an API error. Vault enforces "not your own request" |
| `POST /doors/8/requests/:accessor/open` | requester's BFF supplies the wrapping token → `sys/wrapping/unwrap` → launch codes, once |
| `GET /attempts/:id` | one attempt: triggered-by, opened-by, outcome, Vault decision fields, joined **audit entries** (request + response) |
| `GET /audit?door=&limit=` | recent audit entries tagged to doors |
| `GET /cluster` | main Vault nodes (leader/standby, unsealed, version), Raft peers, seal type, seal Vault status, seal-token TTL, VSO sync status, licence expiry |
| `GET /health` | own health + Vault reachability + collector state |

Error contract: `{ "error": "…", "code": "…", "request_id": "…" }`; 400/401/403/404/409/502 used consistently; Vault's own denial passed
through as `outcome: denied` with Vault's status + errors (200 to the UI —
a denied door is a successful demo, not an API error).

Found in prompt 03: Vault answers an **expired client certificate** at
`auth/cert/login` with **HTTP 500** (`x509: certificate has expired …`),
not 4xx. Classify by Vault's error text for known auth failures, not by
status code alone, so this shows as a denial with its real reason.

### Audit collector

- TCP listener on `:9090` (Service `red-doors-api-audit`), newline-delimited
  JSON from Vault's `socket` audit device; parse, keep raw JSON (HMAC'd
  fields stay HMAC'd), index `request.id`, `time`, `request.path`,
  `auth.display_name`, `auth.policies`, `error`, `type` (request/response).
- Tag entries to doors by path + request ID; join to attempts using the
  request IDs the openers/human calls return.
- Bounded retention (e.g. last 50 000 entries); backpressure-safe (never
  block Vault: read fast, queue, write in batches).
- **Then enable the socket audit device** (`terraform/vault-audit`,
  `address = red-doors-api-audit.rd-app.svc:9090`, `socket_type = tcp`)
  alongside the stdout `file` device. Prove: with the API scaled to 0,
  Vault still serves requests (the file device succeeds) and the gap is
  visible in the UI as "collector offline", not hidden.

### Tests

- Unit tests for the joiner/tagger with recorded fixtures (synthetic, never
  real tokens — gitleaks will flag real-looking ones).
- Live smoke script `scripts/api-smoke.sh` hitting every endpoint through
  `oc exec` / port-forward. Clearly separate fixture tests from live ones.

## Validation

```sh
make api-build && make api-up && make tf-audit
scripts/api-smoke.sh              # every door: owner opens, impostor denied; attempts carry joined audit entries
# rd-api policy cannot read any door secret (vault token capabilities … for each door path → deny)
# door 8: cleo requests, dirk approves, cleo opens; eve self-approval → Vault error surfaced; finn cannot approve
oc -n rd-app scale deploy/red-doors-api --replicas=0 && vault kv get … # still works (file device)
```

## Out of scope

UI and BFF (frontend prompts).

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 1 — 2026-10-06

#### Done

- `api/` (Node 24 ESM, Express 5.2, `pg`): `vault.js` (own identity via
  Kubernetes role `red-doors-api`, renew at 2/3 TTL, re-login on 403;
  `asUser` for people's tokens; response wrapping via `X-Vault-Wrap-TTL`),
  `db.js` (credentials from `database/creds/api-rw`, re-minted at 2/3 of the
  lease with a pool swap, pool `error` listener, `SET ROLE api_owner`,
  idempotent migrations), `registry.js` (8 doors, story order, audit
  paths), `audit.js` + `audit-parse.js` (TCP collector :9090, bounded queue,
  batch inserts, retention), `cluster.js`, `server.js` (all endpoints).
  Unit tests (`make api-test`, synthetic fixtures): 5/5.
- `terraform/vault-api`: policy `rd-api` (door-3 secret-id **wrapped only**,
  30s–2m; policy/EGP text; identity names; `database/creds/api-rw`),
  Kubernetes role `red-doors-api`, database role `api-rw`.
- `terraform/vault-audit`: socket device `red-doors-collector` (tcp,
  `write_timeout=2s`) next to stdout; `scripts/audit.sh` declares it only
  once the API is ready (a plain re-apply would otherwise remove it).
- `deploy/app/api.yaml`: SA + read-only RBAC (pods; the door-7
  VaultStaticSecret by name; no Secrets), BuildConfig/ImageStream,
  Deployment (Recreate, 1 replica), Services `red-doors-api:3001` and
  `red-doors-api-audit:9090`, NetworkPolicy (UI → 3001, rd-vault → 9090).
- `openapi/red-doors.yaml` (OpenAPI 3.1, 16 operations with operationIds;
  Redocly: valid). `scripts/api.sh` (`make api-up`, `api.sh call`),
  `scripts/api-smoke.sh` (`make api-smoke`).

#### Deviations

- **Cluster view without root-namespace endpoints**: the API's token lives in
  `red-doors`, so seal-token TTL and Raft configuration stay in
  `make vault-status`. Per node it uses unauthenticated `sys/health` +
  `sys/leader`, which also expose the licence expiry.
- **Released values are never persisted**: attempts store identity,
  decision, denial and request ids only.
- **Group names**: `rd-api` may read `identity/entity/id/*` and
  `identity/group/id/*` (names, no secrets) to show a person's groups.
- **Door 3 impostor**: the API replays the last wrapping token opener-3
  consumed (or mints one and lets opener-3 consume it first).
- **Classification**: openers already map every Vault refusal (including
  the HTTP 500 for an expired client cert) to `outcome: denied`; the API
  passes it through as HTTP 200.
- OpenAPI keeps 11 "add a 4xx" style warnings: refusals are 200 by design.

#### Validation output

```text
make api-test   → 5 passed (synthetic audit fixtures, door tagging, registry)
make api-up     → vault-api 3 added; image built in-cluster; ready (policies default,rd-api; db v-red-door-api-rw-…);
                  vault-audit 1 added → audit devices: stdout + red-doors-collector (socket → API)
make api-smoke  → 39 passed, 0 failed:
  health ok, own identity rd-api, Vault-minted DB login; collector listening and receiving
  8 doors in story order; policy text and the Sentinel EGP read live from Vault
  doors 1,3,4,5,6,7: owner opened, impostor denied (door 7: no Secret mounted)
  door 3 wrapped by the API (creation_path auth/approle/role/door-3/secret-id), never unwrapped by it
  door 4 attempt joined to its Vault audit entries by request id; attempts hold no released values
  door 2: ada opened, ben 403 · door 8: cleo → pending; open before approval refused; ben/finn
  approve refused; dirk approves; cleo opens; eve self-approval → not_counted; eve open refused;
  dirk approves; eve opens
  cluster: 3/3 unsealed, leader, seal Vault unsealed, licence expiry, VSO status; audit feed door-tagged
  rd-api capabilities on 7 door paths → all deny
collector offline: API scaled to 0 → Vault served a read in 0.7 s (stdout device);
                   API back → Vault reconnected the socket by itself, entries flowing again
```
