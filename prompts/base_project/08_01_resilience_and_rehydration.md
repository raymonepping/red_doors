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
|---|---|---|
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
