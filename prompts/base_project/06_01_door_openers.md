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
| --- | --- |
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

### Run 1 — 2026-10-06

#### Done

- `openers/` (Node 24 ESM, no framework; `pg` only): `src/vault.js` (HTTPS
  with the project CA, optional client cert, namespace header, Vault
  `request_id` captured), `src/doors.js` (doors 1, 3, 4, 5, 6, 7 + impostor;
  result: outcome, identity, Vault decision fields, released value, denial
  with step/status/errors, timings; token revoked after every knock),
  `src/server.js` (`POST /knock`, `GET /health`). Dockerfile `node:24-slim`,
  `npm ci` from a committed lockfile, `USER 1001`, read-only root FS.
- `deploy/doors/openers.yaml`: BuildConfig + ImageStream `opener`, seven
  Deployments (each mounts only its own credential source), Services,
  NetworkPolicies (ingress only from `rd-app`/`app=red-doors-api`; egress DNS
  and Vault, PostgreSQL for opener-4/impostor, nothing Vault-side for opener-7).
- `scripts/doors.sh` (`make openers-up | knock DOOR=N | knock-wrong DOOR=N`):
  role-id ConfigMap from Vault, `impostor-forged-cert` (self-signed, CN
  `opener-5.rd-doors`), in-cluster build only when the source hash changes.
- VSO `rolloutRestartTargets` → opener-7 (deferred from prompt 05).

#### Deviations

- `make knock` runs *inside* the opener pod (`oc exec` → `127.0.0.1:8080`),
  so it works before the API exists without loosening the NetworkPolicy.
- Health reports the credential model instead of cert expiry: opener-3 holds
  only a role-id, opener-5 holds no cert at rest (fresh 10-minute cert per
  knock), opener-7 reports its synced Secret's mtime and `secret_missing` →
  503 if VSO hasn't synced.
- The impostor's door-5 forgery is a Secret generated with openssl at deploy
  time (visible, honest) rather than baked into the image.
- Your shell's `ls` alias (`eza --icons`) stalls without a TTY; scripts and
  automation avoid bare `ls`.

#### Validation output

```text
make openers-up (first) → image built in-cluster (1e1bc1d7…), 7 Deployments ready
make openers-up (rerun) → "opener image up to date", no rebuild
owner knocks:
  1 opened  kubernetes/opener-1   [default, door-1]  ttl 300  revoked  → deploy key
  3 opened  approle/door-3        [default, door-3]  ttl 300  revoked  → partner key (wrap lookup → unwrap → login)
  4 opened  kubernetes/opener-4   [default, door-4]  ttl 300  revoked  → v-red-door-payroll-…, 20 rows, lease 300 s
  5 opened  cert/treasury         [default, door-5]  ttl 120  revoked  → wire room; cert serial 75:bf:…, not_after +10 min
  6 opened  kubernetes/opener-6   [default, door-6]  ttl 300  revoked  → plaintext memo; encrypt attempt 403
  7 opened  vault-secrets-operator, no Vault token        → customer DB password from the synced Secret
impostor knocks (all denied by Vault, door 7 by absence):
  1 read 403 · 3 wrap_lookup 400 "not valid or does not exist" (tampered) · 4 mint_db_login 403
  5 login 400 "failed to match all constraints" · 6 decrypt 403 · 7 no Secret mounted in this pod
NetworkPolicy: pod in rd-doors (not the API) → opener-1:8080 … TimeoutError (blocked)
leftover door-4 DB users after knocks: 0
make door7-rotate → VSO synced (v3) and rolled opener-7 (new pod) → knock returns the new value
```
