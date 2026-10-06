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
