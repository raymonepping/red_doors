# Prompt 06 — Door openers: one codebase, seven identities

## Context

Prompts 01–05 are done: every door's Vault side exists and has been proven
with throwaway pods. Now make the knocking real, repeatable and observable.

## Goal

Seven small workloads in `rd-doors`, one per machine-facing door
(1, 3, 4, 5, 6, 7) plus `opener-impostor` for wrong-key demos. Each holds
exactly one identity. The API (prompt 07) asks them to knock; they never
share credentials and the API never holds theirs.

## Deliverables

### Codebase (`openers/`)

- Node 24 + TypeScript (or plain ESM JS — match Arcanium's API style),
  minimal dependencies (`pg` for door 4). Vault over HTTPS with the project
  CA; no `-tls-skip-verify`, no Vault SDK needed.
- One image, behaviour selected by `DOOR_ID` (`1|3|4|5|6|7|impostor`).
- Endpoints (ClusterIP only):
  - `POST /knock` → performs the door's method end to end and returns

    ```json
    {
      "door": 4,
      "outcome": "opened | denied | error",
      "identity": { "method": "kubernetes", "subject": "system:serviceaccount:rd-doors:opener-4", "role": "opener-4" },
      "vault": { "request_ids": ["…"], "token_accessor": "…", "policies": ["default","door-4"], "token_ttl": 300, "entity_id": "…" },
      "released": { … door-specific, real values … },
      "denial": { "status": 403, "errors": ["permission denied"] },
      "timings_ms": { … }
    }
    ```

  - `GET /health` (and for door 5, cert fields — see below).
- After every knock: **revoke its own token** (`auth/token/revoke-self`) —
  for door 4 this also revokes the DB lease; the response records it.
- Every Vault call's `request_id` is returned so the API can join it to the
  audit stream. Never log secret values.

### Per-door behaviour

| Door | Knock |
|---|---|
| 1 | Projected SA token (`audience: vault`, `expirationSeconds: 600`) → `auth/kubernetes/login` role `opener-1` → read `doors/data/1-production-deploy-key` |
| 3 | Role-id from a ConfigMap (not secret on its own). The API passes a **wrapping token**; the opener first `sys/wrapping/lookup`s it and checks `creation_path = auth/approle/role/door-3/secret-id` (tamper evidence: if anyone unwrapped it first, unwrap fails and the opener reports `tampered`), then unwraps, logs in, reads |
| 4 | Kubernetes login → `database/creds/payroll-reader` → connect to `postgres.rd-data.svc` with those creds → `SELECT … FROM payroll LIMIT 5` + `count(*)` → return rows, generated username, lease TTL → revoke-self |
| 5 | Kubernetes login as `opener-5-issuer` → `pki-int/issue/treasury-client` (TTL 10m) → **new TLS connection to Vault presenting that client cert** → `auth/cert/login` role `treasury` → read `doors/data/5-treasury-wire-room`. Return cert serial, not_after, issuer. A fresh cert per knock: no long-lived cert exists to expire (lesson from Arcanium's KMIP client) |
| 6 | The API sends the ciphertext (`vault:v1:…`) from `merger_docs` — ciphertext is safe to move around. Kubernetes login → `transit/decrypt/merger-docs` → return plaintext + key version. Also attempt `transit/encrypt` and report the 403, to show decrypt-only |
| 7 | Read the mounted `Secret door-7-customer-db` (files). **No Vault address, token or role in this pod.** Return the value + the file's mtime |
| impostor | Given `{ "door": N }`, attempts door N's method with its own identity (SA `impostor`) and returns Vault's denial verbatim. For door 5 it presents a self-signed cert; for door 3 it replays an already-consumed wrapping token; for door 7 it reports that no such `Secret` is mounted in its pod |

### OpenShift (`deploy/doors/`)

- One `ServiceAccount` per opener (`opener-1`…, `impostor`), automount off;
  door identities come from a **projected** token volume with audience
  `vault`.
- `BuildConfig` (Docker strategy, binary source) + `ImageStream opener`;
  `make openers-build` runs `oc start-build opener --from-dir=openers
  --follow` (with `COPYFILE_DISABLE=1`, `xattr -rc openers`, `._*` in
  `.dockerignore` — lesson from Arcanium/Nitro builds).
- Deployments reference `opener:latest` via image-change triggers; one
  replica each, small requests (25m / 64Mi), `restricted-v2` compatible.
- `NetworkPolicy`: only pods labelled `app=red-doors-api` in `rd-app` may
  reach `:8080/knock`; openers may egress only to Vault (and Postgres for
  opener-4).
- Readiness on `/health`.

### Make

`make openers-build`, `make openers-up`, `make knock DOOR=4` (calls the
opener through `oc exec` into a debug pod or the API once it exists —
prints the JSON), `make knock-wrong DOOR=4`.

## Validation

```sh
make openers-build && make openers-up
for d in 1 3 4 5 6 7; do make knock DOOR=$d; done        # all "opened", real values
for d in 1 3 4 5 6 7; do make knock-wrong DOOR=$d; done  # all "denied" with Vault's own error (door 7: no Secret)
# door 4: the generated DB user no longer exists after the knock (\du via vault_admin)
# door 3: replaying the same wrapping token → tampered/denied
```

## Out of scope

The API's orchestration, door 2/8 (human doors), UI.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
