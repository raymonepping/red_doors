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
|---|---|
| `GET /doors` | registry: id, title, business item, method, story order, policy names, status of last attempt |
| `GET /doors/:id` | detail incl. **policy text** read from Vault, owner/wrong-key identities, last N attempts |
| `POST /doors/:id/knock` | machine doors 1,3,4,5,6,7; body `{ "as": "owner" \| "impostor" }`; header `X-Triggered-By` (from BFF session). Door 3: mint wrapped secret-id → pass the wrapping token to opener-3 (or replay a consumed one to the impostor). Door 6: read ciphertext from `merger_docs` → pass to opener-6 |
| `POST /doors/2/open` | human door: the BFF forwards the **user's Vault token** in `X-Vault-Token`; the API reads `doors/data/2-board-minutes` with it and returns Vault's answer. The token is never stored or logged |
| `POST /doors/8/requests` | requester reads with their token → Vault returns `wrap_info` (control group). API stores **only** the accessor, requester entity, created/expiry; returns the wrapping token to the BFF, which keeps it in the requester's server-side session |
| `GET /doors/8/requests` | role-aware list; status per accessor via `sys/control-group/request` using the caller's token (approvers see approvals + remaining) |
| `POST /doors/8/requests/:accessor/approve` | `sys/control-group/authorize` with the **approver's** token; Vault enforces "not your own request" |
| `POST /doors/8/requests/:accessor/open` | requester's BFF supplies the wrapping token → `sys/wrapping/unwrap` → launch codes, once |
| `GET /attempts/:id` | one attempt: triggered-by, opened-by, outcome, Vault decision fields, joined **audit entries** (request + response) |
| `GET /audit?door=&limit=` | recent audit entries tagged to doors |
| `GET /cluster` | main Vault nodes (leader/standby, unsealed, version), Raft peers, seal type, seal Vault status, seal-token TTL, VSO sync status, licence expiry |
| `GET /health` | own health + Vault reachability + collector state |

Error contract: `{ "error": "…", "code": "…", "request_id": "…" }`; 400/401/403/404/409/502 used consistently; Vault's own denial passed
through as `outcome: denied` with Vault's status + errors (200 to the UI —
a denied door is a successful demo, not an API error).

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
