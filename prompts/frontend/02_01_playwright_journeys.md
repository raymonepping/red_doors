# Frontend 02_01 — Playwright journeys + accessibility gate

## Context

The UI runs at `https://doors.apps-crc.testing`. Template:
`../arcanium/arcanium/ui/tests/` (real OIDC via Keycloak, saved
`storageState` per persona, axe scan of every screen, screenshot spec).
Nothing is mocked: the journeys drive real Vault decisions.

## Deliverables (`ui/tests/`, `ui/playwright.config.ts`)

- `global-setup.ts`: sign in once per persona (`ada`, `ben`, `cleo`,
  `dirk`, `eve`, `finn`) through `/auth/login` → Keycloak → callback;
  passwords read from `.secrets/identity/users.json` (never hardcoded,
  never committed; `.auth/` gitignored). Trust the CRC ingress CA (or
  `ignoreHTTPSErrors` only for the Route, documented).
- `doors.spec.ts`: for each door, owner opens it (assert the released value
  is non-empty, the decision panel shows the expected method/role/policy,
  and at least one joined audit entry) and the wrong key is denied (assert
  Vault's error text is shown and the door state is `refused`).
- `door8.spec.ts`: two browser contexts — `cleo` requests, `dirk` approves,
  `cleo` opens; `eve` self-approves → still pending (`approved: false`) and her Open is refused, then `dirk` approves → she can open; `finn` has no approve button
  and a direct API call is refused by Vault.
- `corridor.spec.ts`: keyboard walk (`→`, `K`, `W`, `D`), progress state.
- `cluster.spec.ts`: 3 nodes, one leader, seal chain visible; optional
  `@failover` test that deletes the active pod (behind an env flag) and
  waits for leadership to move.
- `a11y.spec.ts`: axe WCAG 2.1 A/AA on every screen for `ada` and `finn`,
  plus sign-in; **0 violations required**. Also run with
  `reducedMotion: 'reduce'`.
- `screens.spec.ts` (`@screens`): every screen at 1440×900 and 390×844 →
  `docs/screenshots/`.
- `make ui-test` runs everything except `@failover`/`@screens`.

## Validation

`make ui-test` green; `npx playwright test --grep @screens` produces the
screenshot set; paste the summary into the execution log.

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 2026-10-07

#### What was done

- `ui/playwright.config.ts` + `ui/tests/`: `users.ts`, `auth.ts`,
  `global-setup.ts` (real Keycloak sign-in per persona → `tests/.auth/`,
  gitignored; passwords read from `.secrets/identity/users.json`),
  `doors.spec.ts`, `door8.spec.ts`, `corridor.spec.ts`, `cluster.spec.ts`,
  `a11y.spec.ts`, `screens.spec.ts`.
- `make ui-test` (everything except `@failover`/`@screens`, via
  `grepInvert`), `make ui-test-failover`, `make ui-screens`.

#### Deviations and why

- `ignoreHTTPSErrors: true` instead of trusting the CRC ingress CA: the
  Routes are signed by OpenShift Local's own CA and only
  `*.apps-crc.testing` is visited. Documented in the config.
- Door 7 asserts **no** joined audit entry: its opener reads the Secret VSO
  mounted and never calls Vault per knock — that is the point of the door.
  Its wrong key is "no Secret mounted in this pod", not a Vault error.
- door 8 `finn`: the direct call goes through finn's own BFF session, so the
  API asks Vault with finn's token and Vault refuses.
- `@failover` uses CRC's own `oc` (`~/.crc/bin/oc/oc`) when `oc` is not on
  `PATH`.

#### Found by the suite (fixed)

- **API database login revoked after the Mac slept.** The pool re-minted
  credentials from one long `setTimeout`, which pauses while the host
  sleeps; Vault revoked the lease meanwhile and every DB query failed
  (`password authentication failed`). `api/src/db.js` now checks the renewal
  deadline against the wall clock every 15 s and, on `28P01`/`28000`,
  re-mints once and retries. Proven by `vault lease revoke -prefix
  database/creds/api-rw`: the next request returned all 8 doors.
- After the same sleep the builder's registry token was stale (push/pull
  `authentication required`); deleting the controller-managed
  `builder-dockercfg-*` secret regenerated it.

#### Validation output

```text
make ui-test            → 25 passed (4.0m)
  doors 1,3,4,5,6,7: owner opens (value, method/role/policy, audit join), wrong key refused
  door 2: ada opens, ben refused · finn read-only
  door 8: cleo→dirk→cleo opens once; eve self-approval not counted, refused, dirk approves, eve opens;
          finn has no buttons and Vault refuses his direct approve
  corridor: K / W / D / → ← · cluster: 3 nodes, one leader, seal chain unsealed
  axe WCAG 2.1 A/AA: sign-in + 13 screens × ada/finn × 1440/390 × motion/reduced → 0 violations
make ui-screens         → 2 passed (36.0s), 20 screenshots in docs/screenshots/ui/
make ui-test-failover   → 1 passed (18.9s): leader deleted, leadership moved, 3/3 back
```
