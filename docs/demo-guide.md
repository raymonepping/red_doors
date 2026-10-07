# Demo guide

Two run sheets on the same estate. Before either: `make up && make verify`
(all ✓), `make demo-users` on a second screen, and the browser already
past the certificate warning.

## Before you start (5 minutes ahead)

- Plug the Mac in and disable sleep for the session. A sleeping Mac makes
  the VM's clock jump, and Kubernetes logins fail for ~40 s afterwards.
- Window A: <https://doors.apps-crc.testing>, signed in as **ada**.
- For door 8, two more browser profiles (or one private window each):
  **cleo** and **dirk** (plus **eve** for the self-approval).
- A terminal in the repo for the scenarios.

## Presenter keys (corridor)

| Key | Does |
| --- | --- |
| `←` `→` | previous / next door |
| `K` | knock as the owner (door 2: open as yourself; door 8: request) |
| `W` | try the wrong key |
| `D` | scroll to "How Vault decided" |
| `⌘K` | jump to any door or page |

The hero counter shows how many doors opened this session.

## The 15-minute run

| Min | Where | Do | Say |
| --- | --- | --- | --- |
| 0–1 | Sign-in | sign in as ada | "Signing in *is* a Vault login: Keycloak vouches for me, my LDAP groups become Vault policies." |
| 1–3 | Door 1 | `K`, then `W`, then `D` | "This pod has no password. Its OpenShift identity is the credential. The other pod is just as real, but Vault refuses it, and here is the policy that says why." |
| 3–4 | Door 3 | `K`, open the audit drawer | "The secret-id came in a sealed envelope. If anyone had opened it on the way, this door would stay shut. These are Vault's own audit records for this knock." |
| 4–5 | Door 5 | `K`, `W` | "Two identities: one may only cut a 10-minute key, the key itself opens the door. A self-signed copy with the same name gets nowhere." |
| 5–6 | Door 2 | open as ada | "A person this time. Same Vault, same door: the board group decides." (Optional: ben's window → refused.) |
| 6–7 | Door 4 | `K` | "Nobody has the payroll password. Vault minted this login for one knock and it is already gone from PostgreSQL." |
| 7–8 | Door 6 | `K` | "The database only holds ciphertext. This identity may decrypt, and its encrypt attempt was refused." |
| 8–9 | Door 7 | `K`, run `make door7-rotate`, `K` again | "This app never talks to Vault. I change the password in Vault, and the operator delivers it within seconds." |
| 9–12 | Approvals (door 8) | cleo requests → dirk approves → cleo opens; eve approves herself | "Two different people. Vault holds the answer sealed until a second person signs. Approving your own request is recorded, and it does not count." |
| 12–14 | Cluster + terminal | `./scenarios/01_kill_leader/run.sh` | "Three Vault nodes. I kill the one in charge, mid-demo." Leadership moves; door 1 keeps opening. |
| 14–15 | Cluster | point at the seal chain | "One operator key unseals the seal Vault, and that unseals everything else. No main-cluster keys, ever." |

## The 5-minute run

| Min | Do | Say |
| --- | --- | --- |
| 0–1 | sign in as ada, door 1 `K` / `W` | "A pod's identity is its only credential, and the wrong one is refused by Vault." |
| 1–2 | door 4 `K` | "Passwords that exist for one knock." |
| 2–4 | door 8: cleo requests, eve self-approves (refused), dirk approves, cleo opens | "Two different people, enforced by Vault, not by this screen." |
| 4–5 | `./scenarios/01_kill_leader/run.sh` on the Cluster page | "And it survives losing its leader mid-sentence." |

## Scenarios to drop in

Each prints what to watch and ends with PASS/FAIL; the presenter scripts
are in each README.

| Scenario | Time | Good for |
| --- | --- | --- |
| [01 kill the leader](../scenarios/01_kill_leader/README.md) | 1 min | HA |
| [02 seal Vault restarts](../scenarios/02_seal_vault_restart/README.md) | 1 min | the seal chain |
| [03 cold start](../scenarios/03_cold_start/README.md) | 2 min | auto-unseal |
| [04 collector offline](../scenarios/04_collector_offline/README.md) | 1 min | audit never blocks Vault |
| [05 expiry](../scenarios/05_expiry/README.md) | 30 s (`--long` 11 min) | short-lived authority |
| [06 rotate door 7](../scenarios/06_rotate_door7/README.md) | 1 min | VSO |

After scenario 02, run `make vault-unseal` before continuing.

## If something goes wrong on stage

- A door shows **Refused** for its owner: read the reason in "How Vault
  decided". `token is expired` right after the laptop woke → wait 40 s.
- Anything else: `make verify` names the broken part; `make up` repairs it
  without touching data.
