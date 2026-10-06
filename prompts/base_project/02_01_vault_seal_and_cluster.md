# Prompt 02 — Seal Vault + 3-node Vault Enterprise with Transit auto-unseal

## Context

Prompt 01 is done: CRC runs, `KUBECONFIG=.secrets/kube/config`, namespaces
`rd-vault-seal` and `rd-vault` exist. Reuse Arcanium's seal-Vault pattern
(`../arcanium/compose/vault/`, `scripts/vault-unseal.sh`, `vault-tls/`) but
on OpenShift with the official Helm chart.

## Goal

A trust chain that survives restarts:

```text
.secrets/vault/seal-init.json (Shamir keys)          ← root of trust, operator-held
        │ make unseals
rd-vault-seal: vault-seal-0 (1 node, Transit key `autounseal`)
        │ periodic orphan token, policy = encrypt/decrypt on transit/keys/autounseal only
rd-vault: vault-0, vault-1, vault-2 (Raft HA) — seal "transit" → auto-unseal
```

## Deliverables

### TLS (`scripts/tls.sh`, `vault-tls/`)

- A project CA (`vault-tls/ca.pem`, key in `.secrets/tls/`), and server
  certs for: the main cluster (`vault.rd-vault.svc`, `*.vault-internal`,
  `vault-active.rd-vault.svc`, `vault.apps-crc.testing`, 127.0.0.1) and the
  seal Vault (`vault-seal.rd-vault-seal.svc`, `vault-seal.apps-crc.testing`).
- Loaded as `Secret`s (`vault-tls`, `vault-seal-tls`) plus a `ca` ConfigMap
  in every namespace that talks to Vault. Script is idempotent and renews
  certs that expire within 30 days (lesson: certificates expire — give them
  an owner).
- Raft `retry_join` uses TLS with `leader_ca_cert_file`; never
  `tls_disable`, never `-tls-skip-verify` anywhere.

### Images

- `docker.io/hashicorp/vault-enterprise` at the same version Arcanium runs
  (`2.1.0-ent`) unless a newer one is needed — **verify the tag has an
  arm64 manifest** (`skopeo inspect --raw` / `podman manifest inspect`)
  before using it. Record the digest.
- Licence: `lics/vault.hclic` (copied from
  `../arcanium/lics/vault_v21_ENT.hclic`) → `Secret vault-license` in both
  namespaces, mounted and referenced via `VAULT_LICENSE_PATH`.

### Seal Vault (`deploy/vault-seal/values.yaml`, Helm release `vault-seal`)

- Standalone, Raft storage on a PVC, 1 replica, injector off, UI off,
  Route `vault-seal.apps-crc.testing` (passthrough) for operator access.
- `global.openshift: true`. Small requests (e.g. 100m / 256Mi).
- Init with Shamir (match Arcanium's vault-s share/threshold choice and
  explain it in a comment); keys + root token to
  `.secrets/vault/seal-init.json` (0600).
- Configure: `transit` engine, key `autounseal`, policy `autounseal`
  (`update` on `transit/encrypt/autounseal` and `transit/decrypt/autounseal`
  only), and a **periodic orphan token** (`period=24h`) with that policy,
  stored as `Secret vault-seal-token` in `rd-vault`.
- Lesson (Arcanium/vault_reference): an expiring seal token crash-loops
  the main nodes days later and looks like a health-check flake. The token
  must be periodic and renewed by Vault; `make seal-token-status` prints
  its TTL and last renewal, and `verify-stack` fails if TTL < 1h.

### Main cluster (`deploy/vault/values.yaml`, Helm release `vault`)

- `server.ha.enabled: true`, `replicas: 3`, Raft integrated storage on
  PVCs, `injector.enabled: false` (Red Doors uses VSO and direct auth),
  `ui: true`, `global.openshift: true`.
- **Single-node CRC gotcha**: the chart's default pod anti-affinity
  (`requiredDuringScheduling…` on hostname) leaves pods 2 and 3 Pending
  on a one-node cluster. Override `server.affinity` to empty (or a soft
  preference) and document why.
- `seal "transit"` stanza: `address = https://vault-seal.rd-vault-seal.svc:8200`,
  `key_name = autounseal`, `mount_path = transit/`, CA from the `ca`
  ConfigMap, token from `vault-seal-token` via `extraSecretEnvironmentVars`
  (`VAULT_TOKEN`), `tls_server_name` set.
- Listener TLS from `Secret vault-tls`; `api_addr`/`cluster_addr` per pod.
- Route `vault.apps-crc.testing` → `vault-active` service, **passthrough**
  TLS (so the CA from `vault-tls/ca.pem` validates end to end from the Mac).
- Telemetry: `unauthenticated_metrics_access` on `/v1/sys/metrics` for
  later observability (optional).
- Audit devices are configured in prompt 03 — but enable a `file` device to
  stdout immediately after init so nothing between init and Terraform goes
  unaudited.

### Bootstrap (`scripts/vault-up.sh`, `make vault-up`) — idempotent

1. Apply TLS + licence secrets.
2. `helm upgrade --install vault-seal` → wait Running → init if needed →
   unseal if sealed → configure transit/key/policy/token if missing.
3. `helm upgrade --install vault` → wait for `vault-0` → `operator init`
   with recovery keys if needed (auto-unseal → recovery shares, not unseal
   keys) → save `.secrets/vault/cluster-init.json` (0600) → wait for
   `vault-1`/`vault-2` to join via `retry_join` → verify 3 voters.
4. Print a summary: seal type, HA mode, leader, versions, licence expiry.

`make vault-unseal` (seal Vault only — the main cluster unseals itself),
`make vault-status`, `make seal-token-status`, `make vault-ui` (opens the
Route), `make vault-down` (scales to 0, **never** deletes PVCs).

## Validation

```sh
make vault-up && make vault-up             # second run: no changes
make vault-status                          # 3/3 unsealed, Seal Type transit, HA leader + 2 standbys
vault operator raft list-peers             # 3 voters (via Route + CA)
oc -n rd-vault delete pod <active>         # a standby becomes active within seconds; deleted pod rejoins unsealed
oc -n rd-vault-seal delete pod vault-seal-0 # comes back SEALED; main cluster keeps serving
make vault-unseal                          # seal Vault unsealed; main unaffected
make seal-token-status                     # periodic token, TTL ~24h, renewing
```

Also prove the chain end-to-end once: scale the main cluster to 0 and back
while the seal Vault is sealed (main stays sealed, waiting) → unseal the
seal Vault → main auto-unseals without operator input.

## Out of scope

Secrets engines, auth methods, policies (prompt 03). Identity (prompt 04).

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 1 — 2026-10-06

#### Done

- `scripts/tls.sh` (`make tls`): project CA (10y, key in `.secrets/tls/`),
  server certs for `vault` and `vault-seal` (365d, all service/pod/Route
  SANs), renewed when < 30 days left, missing a SAN, or not signed by the
  current CA. Secrets `vault-tls` / `vault-seal-tls`, ConfigMap
  `red-doors-ca` in all six namespaces.
- `deploy/vault-seal/values.yaml`, `deploy/vault/values.yaml` (chart
  `hashicorp/vault` 0.34.1), image `docker.io/hashicorp/vault-enterprise`
  `2.1.0-ent@sha256:12c3ac14…` (multi-arch manifest list; arm64 digest
  `sha256:0d596086…` confirmed with `oc image info --show-multiarch`).
- `scripts/vault.sh` + `make vault-up | vault-unseal | vault-status |
  seal-token-status | vault-roll | vault-down | vault-ui`.
- Licence `lics/vault.hclic` (from Arcanium, gitignored) → Secret
  `vault-license` in both namespaces; expires 2027-01-31.
- Seal Vault: 1 Shamir share (same POC choice as Arcanium's vault-s),
  stdout audit, transit key `autounseal`, policy `autounseal`
  (encrypt/decrypt only), orphan periodic token → Secret
  `rd-vault/vault-seal-token`.
- Main cluster: 3 Raft voters over TLS `retry_join`, transit auto-unseal,
  recovery key (1 share) in `.secrets/vault/cluster-init.json`, stdout audit,
  Routes `vault.apps-crc.testing` → `vault-active` and
  `vault-seal.apps-crc.testing` (passthrough, validated with the project CA).

#### Deviations

- **Seal token period 720h, not 24h.** Vault renews the token only while
  the main cluster runs; a CRC stopped for a weekend would come back with
  an expired 24h token and an unusable unseal chain. 720h matches
  Arcanium; `vault-up` re-issues the token whenever TTL < 1h and rolls the
  main cluster onto it. Renewal observed live (`last_renewal` updates).
- **`api_addr` uses the chart default (`https://$(POD_IP):8200`).** The
  first run set `apiAddr: https://$(HOSTNAME).vault-internal:8200`;
  Kubernetes only expands `$(VAR)` for variables defined *earlier* in the
  env list and the chart defines `HOSTNAME` after `VAULT_API_ADDR`, so the
  leader advertised the literal string `https://$(HOSTNAME)…`. Found via
  `sys/leader`; fixed and rolled.
- **Init container `wait-for-seal-vault` added (not in the prompt).**
  Cold-start test found that Vault checks its transit seal at startup and
  *exits* (`error parsing Seal configuration … Vault is sealed`) when the
  seal Vault is sealed: 6 restarts → CrashLoopBackOff with up to 5 min of
  backoff. The init container (same image, `vault status` against the seal
  Vault, exit 0 only when unsealed) holds the pods in `Init` with a clear
  log line until `make vault-unseal`; then they start in seconds.
- **Readiness = HTTPS `/v1/sys/health?standbyok&perfstandbyok&sealedcode=204&uninitcode=204`**
  instead of the chart default `vault status -tls-skip-verify`; liveness off.
- **`make vault-roll` added.** The chart's StatefulSet is `OnDelete`; config
  changes need a controlled roll (standbys first, leader last, each back
  unsealed + 3 voters before the next).
- `vault-tls/` (public certs, per machine) gitignored except its README.

#### Validation output

```text
make vault-up (first)      → seal init+unseal, transit/key/policy/token, main init, vault-0/1/2 unsealed, Raft 3 voters, exit 0
make vault-up (rerun)      → nothing re-created, no restarts, 7.7 s
failover (make vault-roll) → leader vault-0 → vault-1; Route probe every 0.5 s: 44/51 OK,
                             7 refused over ~3.5 s while vault-active moved; all back unsealed, 3 voters
seal Vault pod deleted     → comes back {"initialized":true,"sealed":true}; main cluster keeps serving
                             (sys/health sealed=false, secrets list OK); make vault-unseal → unsealed
cold start                 → main scaled 0 → seal Vault restarted (sealed) → main scaled 3:
                             60 s later all Pending/Init, 0 restarts, log "waiting: seal Vault … sealed";
                             make vault-unseal → all 3 unsealed after 3 s, no main-cluster keys used — PASS
                             (first leader election after the cold start takes a few seconds; status during
                             that window shows 3 standbys)
make seal-token-status     → TTL 719h 59m, period 2592000s, orphan, policies autounseal, renewing
make vault-status          → seal Vault unsealed; vault-2 LEADER, vault-0/1 standby; licence 2027-01-31
CRC RAM                    → 8.1 GB of 25.1 GB with both Vaults running
```
