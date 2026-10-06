# Frontend 01_01 — Corridor UI + BFF (Nuxt 4)

## Context

`01_00` is signed off (door component sheet approved). The API (prompt 07)
runs internally in `rd-app`. Follow `vault-ui-design` and Red Doors'
`docs/frontend/DESIGN.md`. Reuse: Durin's BFF/session handling
(`../project_durin/ui/server/`), Arcanium's shell, command palette, gateway
and Playwright setup.

## Goal

The presenter's tool: a guided corridor through eight doors plus a free
view, where every door opening shows who knocked, how Vault decided, and
the audit entry — all real.

## Architecture

- **Nuxt 4, `ssr: false` (SPA) + Nitro server as BFF** (Durin's model).
  Arcanium's SSR path cost real time (hydration mismatches, CSP vs inline
  bootstrap scripts) and Red Doors gains nothing from SSR.
- **Sign-in = Vault OIDC.** `/auth/login` → BFF calls Vault
  `auth/oidc/oidc/auth_url` (role `visitor`,
  `redirect_uri=https://doors.apps-crc.testing/auth/callback`) → browser →
  Keycloak → `/auth/callback` → BFF calls `auth/oidc/oidc/callback` →
  **Vault token** + entity + groups. The UI trusts Vault; Vault trusts
  Keycloak. Mention this on the sign-in page in one sentence.
- Session server-side (Nitro storage), httpOnly + Secure + SameSite=Lax
  cookie. The session holds: the user's Vault token, entity id, display
  name, groups, and door-8 wrapping tokens the user owns. **Nothing secret
  reaches the browser** except the released door values the user is
  allowed to see. Sign-out revokes the Vault token.
- BFF → API over the cluster network only (`/api/v1/*` proxy that injects
  `X-Triggered-By` and, for human doors, `X-Vault-Token` from the session).
- Route `doors.apps-crc.testing` (edge TLS). Security headers as in
  Arcanium (`nuxt.config.ts` comments on `script-src 'unsafe-inline'` and
  `Cache-Control: no-store` explain why).
- Built in-cluster (`BuildConfig` + `ImageStream red-doors-ui`,
  `make ui-build`), lessons: `xattr -rc`, `._*` ignored, `node -e fetch`
  healthcheck (no wget in slim images).

## Screens

1. **Sign-in** — ink hero "Eight doors. Eight ways in.", one button.
   `make demo-users` names shown as a presenter hint only in dev.
2. **Corridor (guided)** — the doors in perspective; one door in focus with
   a short narrative ("Door 4 — Payroll database. Nobody has a password.
   Vault will mint one for this knock and kill it afterwards."), and two
   actions: **Knock** (owner identity) and **Try the wrong key**. Keyboard:
   `→`/`←` move along the corridor, `K` knock, `W` wrong key, `D` open the
   decision panel. Progress shows which doors have been opened this session.
3. **All doors** — 8 door cards (medium door + method + last outcome);
   clicking goes to detail. For Q&A.
4. **Door detail** — door header, the room (released value, lifetime
   countdown), **How Vault decided** (steps from real data; the policy
   text verbatim), **Triggered by / Opened by** chips, the audit drawer,
   and recent attempts. Door-specific extras:
   - 3: wrapping-token lookup (creation path, TTL) and the "replay"
     wrong-key showing Vault's refusal.
   - 4: generated DB username, lease TTL, "revoked at", the rows returned.
   - 5: certificate serial / not-after / issuer; wrong key = self-signed.
   - 6: ciphertext beside plaintext; the denied encrypt attempt.
   - 7: synced `Secret` value, VSO last-sync time, "this pod has no Vault
     address"; **Rotate in Vault** button (operator only) → watch it sync.
   - 2: opens with the signed-in user's token; a non-board user sees
     Vault's denial with their own group list.
   - 8: see Approvals.
5. **Approvals (door 8)** — requesters: "Request launch codes", their
   pending requests (approvals x/1, expiry countdown) and **Open** once
   approved. Approvers: inbox with requester, time left, **Approve**. Eve's
   self-approval attempt shows what Vault did: her authorization recorded
   but not counted (`approved: false`, Sentinel EGP), her Open still
   refused until Dirk approves. Auditors: read-only.
6. **Audit** — recent entries, filter by door, raw JSON; banner when the
   collector is offline.
7. **Cluster** — the seal chain as a diagram (seal Vault → Transit →
   vault-0/1/2), leader/standby, unsealed state, Raft peers, seal-token TTL,
   VSO status, licence expiry; refreshes every 5s. During the "kill the
   active pod" demo, leadership visibly moves.

Shell: frosted rail (groups from `01_00`), floating glass topbar with the
signed-in user, their groups, cluster pill (leader + 3/3 unsealed) and a
door-8 pending pill for approvers; ⌘K palette to jump to any door.

## Honesty rules

- Every number, identity, policy and audit line comes from the API; the UI
  never invents outcomes. A denied door shows Vault's own error text.
- Timers count down from TTLs Vault returned, and show "expired" — they do
  not trigger fake state changes.
- Missing data renders as "not reported", never as a placeholder value.

## Deliverables

`ui/` (Nuxt 4), `deploy/app/ui.yaml`, `make ui-build ui-up`, generated API
types from `openapi/red-doors.yaml`.

## Validation

Walk the full corridor as `ada` (doors 1–7 via knocks/own token), `ben`
(door 2 denied), the door 8 round trip `cleo → dirk → cleo`, `eve`
self-approval refused, `finn` read-only. Screenshot every screen at
1440×900 and 390×844 in one batch, fix in one pass, confirm once. Axe scan
must be 0 violations (full suite in `02_01`).

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 1 — 2026-10-06

#### Done

- **BFF** (`ui/server/`): `/auth/login` asks Vault for Keycloak's authorize
  URL (role `visitor`, `client_nonce` cookie), `/auth/callback` exchanges
  the code with Vault → the person's Vault token → server-side session
  (`utils/session.ts`, Nitro storage, httpOnly/SameSite=Lax cookie, Secure
  behind the Route), `/auth/logout` revokes the token. `/api/session` (no
  token exposed). `/api/v1/**` proxy: `X-Triggered-By`, the person's token
  only for human doors, door-8 wrapping tokens kept in the requester's
  session (stripped from responses, injected on Open, `can_open` flag),
  auditors read-only for knocks.
- **Pages**: Sign-in, Corridor (guided, story order, receding row, keyboard
  `← → K W D`, session progress), All doors, Door detail (room, decision
  panel, identity chips, audit drawer, recent attempts), Approvals (door 8
  for requesters/approvers/auditors), Audit (live feed, collector-offline
  banner), Cluster (seal chain, nodes, licence, collector, openers, VSO).
- **Components**: `DoorStage`, `DecisionPanel`, `RoomValue`,
  `IdentityChips`, `AuditDrawer`, `OutcomePill`; shell = the skill's
  `shell.css` (rail, floating topbar, ⌘K palette, user menu).
- **Deploy**: `ui/Dockerfile` (two-stage, `USER 1001`, read-only root FS),
  `deploy/app/ui.yaml` (Route `doors.apps-crc.testing` edge, NetworkPolicy:
  router only), `scripts/ui.sh` (`make ui-up | ui-open`, clean source copy
  uploaded to the in-cluster build).

#### Deviations / fixes found by looking

- Keycloak's default LDAP "first name" mapper reads `cn` → names rendered
  "Ada Lindqvist Lindqvist"; `identity.sh` now maps it to `givenName`.
- Phone: the vault-ui-design shell hid the rail below 900 px and the user
  menu below 1180 px — no navigation or sign-out on phones. Added a menu
  button that opens the rail as a sheet, and kept the user menu visible.
  (Worth folding back into the skill's `shell.css`.)
- Grid children could not shrink (page-wide horizontal scroll on phones):
  `min-width: 0` guards; long chips/policy text wrap inside their panel.
- The swung door also projects upward in perspective → `RedDoor` reserves
  space above and below.
- API: door 2 now returns `triggered_by`; door-8 approver entity ids are
  resolved to the person's alias name (Vault auto-names OIDC entities
  `entity_xxxx`).
- Room labels humanised; revocation/lease shown once, as a sentence.

#### Validation output

```text
Browser (real Vault OIDC → Keycloak → LDAP, Playwright, 1440×900 and 390×844):
  ada: corridor door 1 knock (K) → Opened by Vault · wrong key (W) → Refused by Vault
       door 4 detail → minted DB login + 5 payroll rows + revoked-at · door 2 → Opened by Vault
  ben: door 2 → Refused by Vault (HTTP 403 permission denied, policy text shown)
door 8 (three browsers):
  cleo requests → pending, held in her session · dirk approves → Approved · cleo opens → codes
  eve self-approves → "recorded but did not count … (Sentinel EGP door-8-two-different-people)"
  eve opens → "Refused by Vault: Request needs further authorization" · dirk approves → eve opens
axe WCAG 2.1 A/AA → 54 page scans (sign-in + 13 routes × ada/finn × 2 viewports): 0 violations
screenshots → docs/screenshots/ui/ (25)
```
