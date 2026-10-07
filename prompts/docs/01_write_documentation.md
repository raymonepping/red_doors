# Docs 01 — Write the documentation

## Context

Everything is built and verified. Reuse the documentation shape of
`../arcanium/docs/` and `../project_durin/docs/` (index, getting-started,
architecture, demo guide, operations, troubleshooting, security model).
Write for **a colleague who has never seen the project** and must run the
demo alone. Plain, direct language; no marketing.

## Deliverables

- `README.md` — what Red Doors is (thesis in one paragraph), the eight
  doors table, prerequisites (CRC, pull secret, licence, resources),
  `make crc-up && make up`, where to click, links to docs.
- `docs/getting-started.md` — first run from zero, including the Red Hat
  pull secret, licence placement, expected durations, first sign-in.
- `docs/architecture.md` — namespaces, the seal chain, Vault topology,
  identities per door, audit flow (two devices), API/BFF boundaries; one
  diagram (mermaid or SVG) that matches the running system.
- `docs/doors.md` — per door: business item, Vault method, policy text,
  owner identity, wrong key, what the audience sees, what can go wrong.
- `docs/demo-guide.md` — a 15-minute and a 5-minute run sheet using the
  guided corridor, the failover and seal scenarios, presenter keyboard
  shortcuts, what to say at each door.
- `docs/operations.md` — every `make` target, `make up`/`down`/`reset`
  semantics, where secrets live, renewals (seal token, TLS, per-knock
  certs), adding a ninth door.
- `docs/troubleshooting.md` — real problems hit during prompts 01–08
  (taken from their execution logs), symptom → cause → fix.
- `docs/security-model.md` — trust boundaries, what each component can and
  cannot do, why the API can't read door secrets, why the seal Vault is
  the root of trust, what is demo-grade (CRC, self-signed CA, single node).
- `CHANGELOG.md` entry; `docs/frontend/DESIGN.md` already exists (link it).

## Validation

A dry run: follow `getting-started.md` literally on the running system
(skipping only the CRC download) and fix every step that doesn't match.
Check all relative links. Markdown lint clean.

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 2026-10-07

#### What was done

- `README.md` rewritten (thesis, eight doors, prerequisites, run, links).
- `docs/README.md` (index), `getting-started.md`, `architecture.md`
  (mermaid diagram of the running system), `doors.md` (policy text from
  `terraform/*/policies` and the Sentinel EGP), `demo-guide.md` (15- and
  5-minute run sheets), `operations.md`, `troubleshooting.md` (from the
  execution logs of prompts 01–08 and frontend 01–02), `security-model.md`.
- `CHANGELOG.md`: 1.0.0.

#### Deviations and why

- Role/SA names in `architecture.md` were checked against Terraform
  (`opener-5-issuer`, SA `impostor`, SA `vso-door-7`), not the prompt text.
- The dry run found one mismatch: the Vault UI Route is passthrough TLS and
  presents the project CA (`vault-tls/ca.pem`), not the ingress CA;
  `getting-started.md` now says so.

#### Validation output

```text
dry run of getting-started.md (CRC download skipped):
  tools: bash 5.3, jq 1.8.2, terraform 1.14.2, vault 2.1.0+ent, node 25.2, openssl 3.6.3, crc 2.64.0
  pull secret ✓ licence ✓
  make crc-up        → CRC already running; kubeconfig refreshed
  make up            → 51 s, verify 40/40
  make verify        → ✓ All checks passed (40 pass, 0 warn)
  make demo-users    → 6 users, groups as documented
  https://doors.apps-crc.testing 200 (ingress CA) · https://vault.apps-crc.testing/ui/ 200 (project CA)
  https://keycloak.apps-crc.testing 302
relative links (README, docs, scenarios) → 0 broken
markdownlint (MD013 off, as for all prompts) → clean
```
