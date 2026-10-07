# Prompt 08 — Resilience scenarios, `make up` rehydration, `verify-stack`

## Context

Everything runs (prompts 01–07, frontend 01_00–01_01). This prompt makes it
survivable and repeatable: a Mac reboot, a CRC restart, a dead pod, a
sealed seal Vault, an expired credential — each has a known, scripted
recovery and a visible demo moment. Reuse Arcanium's
`scripts/rehydrate-stack.sh` structure (numbered `run`/`optional` steps,
`--from N`, `--list`) and `scripts/verify-stack.sh` style (✓/✗/⚠ summary).

## Deliverables

### `make up` (idempotent, `scripts/rehydrate.sh`)

Ordered steps, each safe to rerun, resumable with `--from`:

1. CRC running (start if stopped; refuse if Podman machine is running
   unless `ALLOW_PODMAN=1`), `oc` login, namespaces.
2. TLS: renew anything expiring within 30 days.
3. Seal Vault up + unsealed (`.secrets/vault/seal-init.json`); seal token
   valid (periodic, TTL ≥ 1h) — re-issue if not.
4. Main Vault up; wait 3/3 unsealed (auto) and Raft healthy.
5. Terraform `tf-all` (no-op when converged); `make seed` (no-op when present).
6. Identity up + reconciled; data up; VSO subscription healthy.
7. Builds only when sources changed (compare a content hash stored as an
   ImageStream annotation) — otherwise skip; rollouts.
8. Socket audit device enabled once the collector is ready.
9. `make verify`.

`make down` = scale apps → identity → Vault → seal Vault to 0, then
`crc stop`. **Never** deletes PVCs. `make reset` is the only destructive
target and requires typing `red-doors` to confirm.

### `make verify` (`scripts/verify-stack.sh`)

✓/✗/⚠ checks, exit non-zero on any ✗: CRC + cluster operators; seal Vault
unsealed; seal token TTL; main 3/3 unsealed, one leader; Raft 3 voters;
licence > 30 days; every Deployment available; every opener `/health`
(including **cert / credential expiry semantics**: an opener reporting
`cert_expired` or a stale mounted secret is ✗, never "starting" forever —
lesson from Arcanium's kmip-client); both audit devices enabled + collector
receiving; VSO last sync < 2 × refresh; **each door knocked once as owner
(opened) and once as impostor (denied)** via the API.

### Scenarios (`scenarios/NN_name/run.sh`, each prints what to watch in the UI)

| # | Scenario | Expected |
| --- | --- | --- |
| 01 | Kill the active Vault pod mid-demo | a standby takes over; a door knocked during failover succeeds within seconds; the Cluster page shows leadership move; the pod rejoins unsealed |
| 02 | Seal Vault pod restarts | it comes back **sealed**; the main cluster keeps serving (already unsealed); `make vault-unseal` restores it; Cluster page shows the seal chain state honestly |
| 03 | Cold start (`make down && make up`) | after unsealing the seal Vault, the main cluster auto-unseals with no operator keys |
| 04 | Collector offline | scale the API to 0: Vault still serves (file audit device); UI shows "collector offline"; on return, new entries flow again |
| 05 | Expiry | door 4 creds expire/revoked → reuse fails; door 3 wrapping token TTL passes → unwrap fails; door 5 cert past not-after → cert login fails; door 8 request not approved within TTL → expires. Each shown from Vault's real response |
| 06 | Rotate door 7 in Vault | VSO syncs within ~30s, opener-7 rolls, door shows the new value + sync time |

### Docs hooks

Each scenario has a 3-line "presenter script" in its README (what to say,
what to click, what the audience sees).

## Validation

```sh
make up && make up            # second run ≈ only checks
make verify                   # all ✓
for s in scenarios/0*/run.sh; do $s; done   # each prints PASS with evidence
crc stop && crc start && make up && make verify   # survives a cluster restart
```

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 2026-10-06/07

#### What was done

- `scripts/rehydrate.sh` (`make up`, `make up FROM=N`, `--list`): 15
  idempotent steps from CRC to verify; a failed step names its resume point.
- `scripts/verify-stack.sh` (`make verify`): CRC + cluster operators, seal
  chain + seal-token TTL, 3/3 unsealed + Raft voters, licence, admin-token
  TTL, both audit devices, every deployment, opener `/health`, API health +
  collector, VSO sync, UI, and every door owner-opens / wrong-key-refused.
  Bad credentials are ✗, never "starting".
- `scripts/down.sh` (`make down`: scale to 0, `vault.sh down`, `crc stop` —
  no PVC or `.secrets/` touched), `scripts/reset.sh` (`make reset`: typed
  `red-doors` confirmation, deletes the namespaces and generated state),
  `make scenarios`.
- `scenarios/lib.sh` + `01_kill_leader` … `06_rotate_door7`, each with a
  README holding the 3-line presenter script; `scenarios/README.md` index.

#### Deviations and why

- Scenario 03 runs the cold start itself (scales Vault + seal Vault to 0
  and back) instead of a full `make down && make up`, so it fits a live
  demo; the full cycle is the `crc stop && crc start` validation below.
- Scenario 04: Vault keeps a **stdout** audit device (not a file device) —
  OpenShift's restricted SCC and the log pipeline make stdout the
  always-available sink.
- Scenario 05 door 8 needs a 10-minute wait, so it runs only with `--long`.

#### Found during validation (fixed / documented)

- After the Mac slept, the CRC VM's clock jumped forward 32 min (chronyd
  "Forward time jump detected"): projected SA tokens looked expired for
  ~40 s (Vault Kubernetes login 403), the builder registry token went stale,
  and the API's DB lease was revoked while its `setTimeout` slept. The API
  now renews against the wall clock and re-mints on `28P01` (see frontend
  02_01's log). The stale-token window is documented for troubleshooting.

#### Validation output

```text
make up (1st)            → 15 steps, 50 s, verify 40/40
make up (2nd)            → 50 s; terraform 7× "0 added, 0 changed, 0 destroyed";
                           door values "present (unchanged)"; no image rebuilt; verify 40/40
make verify              → ✓ All checks passed (40 pass, 0 warn)
scenarios/01_kill_leader → PASS: leader vault-2 → vault-0; 39/40 knocks opened during failover; pod back unsealed
scenarios/02_seal_vault_restart → PASS: seal Vault SEALED, main cluster kept serving; unsealed again
scenarios/03_cold_start  → PASS: main pods waited (0 restarts); auto-unsealed 8 s after the seal Vault
scenarios/04_collector_offline → PASS: Vault served in 0.82 s with the API at 0; socket reconnected by itself
scenarios/05_expiry --long → PASS: door 3 unwrap refused, door 5 expired cert refused,
                           door 4 revoked login refused, door 8 unapproved request expired
scenarios/06_rotate_door7 → PASS: new value after 6 s, opener-7 rolled by VSO
crc stop && crc start && make up && make verify
                         → stop ≈15 s, start 185 s, make up 108 s (seal Vault unsealed from
                           .secrets/, 3/3 transit auto-unsealed, leader vault-1), verify 40/40; total 308 s
```
