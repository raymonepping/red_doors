# RED DOORS

## Vault Enterprise on OpenShift — eight doors, eight ways in

You are working on a new engineering project called **Red Doors**.

Red Doors is a local, reproducible demonstration of **HashiCorp Vault
Enterprise running inside OpenShift** (OpenShift Local / CRC on an Apple
Silicon Mac). It is not a production product. It is a technically credible,
visually polished reference system that a presenter can run live.

---

## 1. Core thesis

> **Every door opens for exactly one kind of identity — and Vault is the
> only one who decides.**

A corridor of red doors. Behind each door is something a real business
guards (the payroll database, the launch codes, the board minutes…). Each
door opens **only** through one specific Vault method. When a door opens,
the UI shows three things, all taken from real system state:

1. **Who** knocked — the identity (a pod's service account, a person, a
   certificate, an AppRole…).
2. **How Vault decided** — auth method, matched role, policies attached,
   TTL, and for door 8 the approval that was required.
3. **The audit entry** — the actual Vault audit record for that request
   (HMAC'd fields stay HMAC'd).

When a door refuses, it shows the same three things for the denial.

The audience must leave understanding: *"who is allowed to open this, and
why?"* — the same question Durin, Editors Factory and Arcanium answer, now
asked inside OpenShift.

Do not build a generic secrets browser. Vault must be architecturally
meaningful at every door.

---

## 2. Decisions already made (do not re-litigate)

| Area | Decision |
| --- | --- |
| Platform | **Full OpenShift Local** (CRC 2.64 / OpenShift 4.22, arm64, `vfkit`). Not MicroShift — door 7 needs OperatorHub and the console is part of the show. |
| Vault | **Vault Enterprise**, new cluster, **3-node Raft HA**, official Helm chart in OpenShift mode (`global.openshift=true`). |
| Auto-unseal | **In-cluster seal Vault**: a separate 1-node Vault Enterprise in its own namespace provides **Transit auto-unseal** for the main cluster. Same pattern as `vault-s` in Arcanium/Durin. The seal Vault itself is Shamir-sealed and unsealed by `make` from `.secrets/` — it is the root of trust and that is said out loud in the docs. |
| Humans | **OpenLDAP + Keycloak** in-cluster. Users live in LDAP; Keycloak federates them and is Vault's OIDC provider. |
| Behind each door | A **business item + the real value** Vault released. Never faked, short-lived where the method allows. |
| Machine doors | **One workload ("opener") per machine door**, each with its own identity. The UI triggers it; the API never holds those identities. |
| Builds | **OpenShift builds** (`oc start-build --from-dir`) into the internal registry. Podman is not required at runtime. |
| App shape | **Nuxt 4 UI + separate Express API** (Arcanium shape). |
| Demo flow | **Guided corridor** (story order) **+ free "all doors" view**. |
| Look & feel | **Vault daylight glass** — load the user-level `vault-ui-design` skill. Canonical implementation: `../arcanium/arcanium/ui`. |
| Licence | Vault Enterprise licence from `../arcanium/lics/vault_v21_ENT.hclic` (copy to `lics/`, gitignored). |
| Tooling | Make + Terraform (Vault provider) + Helm + `oc`. Secrets under `.secrets/` (gitignored). |

---

## 3. The eight doors

Order = corridor (story) order: machine identity → humans → data →
governance. Door numbers are stable IDs; never renumber.

| # | Door (business item) | Opened by | Behind it (real value) |
| --- | --- | --- | --- |
| 1 | **Production deploy key** | **Kubernetes auth** — the opener pod's projected service-account token is its only credential | KV v2 secret (the deploy key) |
| 2 | **Board minutes** | **OIDC (human)** — a person signs in via Keycloak; Vault maps their LDAP group to a policy | KV v2 secret readable only by the `board` group |
| 3 | **Partner API key** | **AppRole** — role-id baked into the opener, secret-id delivered **response-wrapped** by a trusted orchestrator that can wrap but never unwrap | KV v2 secret |
| 4 | **Payroll database** | **Dynamic database credentials** — PostgreSQL user minted for this request, TTL ≤ 5 min, revoked after use | Live query result from the `payroll` table using those creds (show the generated username + its expiry) |
| 5 | **Treasury wire room** | **PKI + TLS certificate auth** — the opener holds a Vault-issued client cert (TTL minutes); Vault's `cert` auth method validates it | KV v2 secret (wire-transfer approval code) |
| 6 | **Merger documents** | **Transit** — the document is stored only as ciphertext; the opener's policy allows `decrypt` on one key and nothing else | Plaintext of the document, alongside its `vault:v1:` ciphertext |
| 7 | **Customer database password** | **Vault Secrets Operator** — VSO syncs the secret into an OpenShift `Secret`; the opener pod never talks to Vault | Contents of the synced `Secret` + the VSO sync status/last-sync time |
| 8 | **Launch codes** | **Control group (two-person rule)** — a requester's read returns a wrapped, pending response; an approver from a different LDAP group must authorize before the requester can unwrap | KV v2 secret, visible only after approval |

Every door also has a **wrong key** demo: a visibly different identity
tries the same door and is denied (e.g. door 1's opener SA in the wrong
namespace, a non-board user at door 2, an expired cert at door 5, the
requester approving their own request at door 8). Denials come from Vault,
never from UI logic.

---

## 4. Architecture

```text
OpenShift Local (CRC)
├── rd-vault-seal   seal Vault (1 node, Shamir) — Transit key `autounseal`
├── rd-vault        Vault Enterprise ×3 (Raft), transit-sealed by rd-vault-seal
│                   Routes: vault.apps-crc.testing (TLS passthrough)
├── rd-identity     OpenLDAP + Keycloak (realm `red-doors`)
├── rd-data         PostgreSQL (payroll schema, door-4 target)
├── rd-doors        opener-1 … opener-7 (one Deployment + ServiceAccount each)
│                   + door-5 mTLS endpoint if used
├── rd-app          red-doors-api (Express) + red-doors-ui (Nuxt 4)
│                   Routes: doors.apps-crc.testing
└── openshift-operators   Vault Secrets Operator (OperatorHub, certified)
```

- **Vault API from the Mac** (Terraform, scripts): through the passthrough
  Route with the project CA (`vault-tls/ca.pem`), never `-tls-skip-verify`.
- **Audit**: two audit devices — `file` to stdout (always succeeds) **and**
  `socket` to the API's audit collector. Vault blocks a request only if
  *every* device fails, so the collector can restart without freezing Vault.
  The API stores collected entries and joins them to door attempts by
  request ID / accessor.
- **API identity**: the API authenticates to Vault with its own Kubernetes
  auth role. Its policy can: wrap AppRole secret-ids (door 3), read
  control-group request status and authorize as the signed-in approver
  using *the approver's* token (door 8), read the audit stream it receives,
  and read health/HA status. It cannot read any door's secret.
- **Openers**: one small codebase (`openers/`) built once, deployed seven
  times with different `DOOR_ID`, service account and mounted credentials.
  An opener exposes `POST /knock` (internal only, called by the API) and
  returns: identity used, Vault response metadata (auth method, policies,
  token TTL, request_id), and the released value.
- **Human doors (2, 8)**: the UI's server side (BFF) runs the OIDC flow;
  the user's Vault token stays server-side in the session, never in the
  browser (same as Durin/Arcanium).

---

## 5. Reconnaissance — reuse, don't copy blindly

Before writing code, read these and list what you reuse and what you change:

- `../arcanium` — Vault Enterprise + seal Vault + Raft, Terraform layout,
  `make up` rehydration, `workload-credentials.sh`, `vault-rotator`
  sidecar pattern, `kmip-renewer` (cert renewal), Nuxt UI + Express API,
  OIDC BFF, Playwright + axe suite, `docs/frontend/config/DESIGN.md`.
- `../project_durin` — OIDC with Keycloak + LDAP, BFF session handling,
  daylight-glass origin, demo narrative structure.
- `../editors_factory` — Vault HA + Postgres dynamic creds, event timeline UI.
- `~/.claude/skills/vault-ui-design/` — the design system (mandatory).

### Lessons already paid for (apply them)

1. **Transit seal token expiry** silently crash-loops Vault nodes later.
   The seal token must be a **periodic orphan token** that Vault renews;
   verify renewal and add a `make` check that reports its TTL.
2. **Certificates expire.** Arcanium's KMIP client cert (7-day TTL) expired
   and the client restart-looped 17,008 times unnoticed. Every cert in this
   project has an owner that renews it, and every consumer reports
   `cert_expired` on `/health` (HTTP 503) instead of crash-looping.
3. **AppRole lockout**: default 5 failures → 15-minute lockout outlasts a
   repair loop; bound it (e.g. 30s) on demo roles.
4. **`token_policies` round-trip hazard**: never write back the output of
   `vault read -field=token_policies`; always specify the full list.
5. **Architecture**: CRC is arm64 with no emulation. Every image must have
   an arm64 manifest — check before choosing it (`osixia/openldap`, used in
   Arcanium, is **amd64-only**; pick an arm64-capable OpenLDAP).
6. **OpenShift SCC `restricted-v2`** runs containers as a random UID.
   Choose/configure images that tolerate it; don't reach for `anyuid`
   unless documented and justified per workload.
7. **macOS xattrs** (`com.apple.provenance`) leak `._*` files into build
   archives and break Node/Nitro builds: `xattr -rc` the source, add `._*`
   to `.dockerignore`, set `COPYFILE_DISABLE=1`.
8. **Postgres loopback trust**: test DB credentials over the network
   hostname, never `127.0.0.1` inside the pod.
9. **Never fabricate evidence.** If the UI shows something, the API read it
   from Vault, OpenShift or the audit stream. Missing data shows as
   missing.
10. **Kubernetes `$(VAR)` expansion is order-dependent** (found in prompt 02):
    a variable is only expanded if it is defined *earlier* in the container's
    env list. Check rendered manifests (`helm template`) for literal `$(…)`.
11. **A transit-sealed Vault exits at startup if its seal Vault is sealed**
    (found in prompt 02) — it doesn't wait. Main pods carry a
    `wait-for-seal-vault` init container; any new Vault workload that depends
    on another service at startup needs the same explicit wait.

---

## 6. Principles

- **Least privilege per door**: each opener's policy grants exactly one
  path/capability. Show the policy text in the door's "how Vault decided"
  panel.
- **Short-lived authority**: tokens, DB creds, certs and wrapped responses
  have TTLs measured in minutes; the UI shows countdowns.
- **Separation of duties**: door 8's approver cannot be the requester
  (enforced by Vault control-group factors, not by the UI).
- **Idempotent operations**: `make up` can be rerun at any time and brings
  the estate to the desired state without losing data.
- **Secrets never in git**: `.secrets/`, `lics/*.hclic`, `.env`, kubeconfigs.
- **Reproducible from zero**: `make crc-up && make up` on a clean CRC.

---

## 7. Delivery plan (execute in order; each prompt ends with an execution log)

| Prompt | Delivers |
| --- | --- |
| `01_01_openshift_local_cluster.md` | CRC sized + running, `oc` access, namespaces, repo skeleton, Makefile spine |
| `02_01_vault_seal_and_cluster.md` | TLS CA, seal Vault, 3-node Vault Enterprise with Transit auto-unseal, Routes, init/unseal automation |
| `03_01_vault_terraform_baseline.md` | Audit devices, secrets engines, auth methods, per-door policies, admin token model |
| `04_01_identity_stack.md` | OpenLDAP + Keycloak, realm/users/groups, Vault OIDC + identity groups |
| `05_01_data_and_operator.md` | PostgreSQL + database engine (door 4), Vault Secrets Operator (door 7) |
| `06_01_door_openers.md` | The opener codebase + seven deployments, OpenShift builds, per-door identities |
| `07_01_doors_api.md` | Express API: door registry, knock orchestration, door 8 workflow, audit collector, OpenAPI |
| `../frontend/01_00_red_doors_design_spec.md` | Visual contract on top of `vault-ui-design` |
| `../frontend/01_01_corridor_ui.md` | Nuxt 4 UI + BFF: corridor, all-doors, door detail, approvals, cluster |
| `08_01_resilience_and_rehydration.md` | Pod loss / seal Vault restart / expiry scenarios, `make up` rehydration, `verify-stack` |
| `../frontend/02_01_playwright_journeys.md` | Journeys for all eight doors + wrong keys, axe AA scan |
| `../docs/01_write_documentation.md` | README, architecture, demo guide, troubleshooting |

---

## 8. Definition of done (whole project)

- `make crc-up && make up` on a fresh CRC brings everything up; rerunning
  `make up` is a no-op apart from renewals.
- All eight doors open for the right identity and refuse the wrong one,
  live, with real audit entries shown.
- Killing the active Vault pod: a door still opens within seconds (HA).
- Restarting the seal Vault: the main cluster keeps serving; after a full
  restart `make up` restores the unseal chain.
- UI passes the Playwright journeys and an axe WCAG 2.1 AA scan with 0
  violations at 1440×900 and 390×844.
- Docs let a colleague run the demo without asking you anything.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
