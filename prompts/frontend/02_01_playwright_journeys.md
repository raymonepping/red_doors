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
  `cleo` opens; `eve` self-approval refused; `finn` has no approve button
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
