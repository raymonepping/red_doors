# Prompt 04 — Identity: OpenLDAP + Keycloak, Vault OIDC, door 2 and door 8

## Context

Prompts 01–03 are done. Reuse Arcanium's identity work
(`../arcanium/compose/identity/`, `make identity-bootstrap` with its
`ensure_*` reconcile-don't-recreate style) and Durin's Keycloak + LDAP
federation — adapted to OpenShift (`rd-identity` namespace, Routes, SCCs).

## Goal

People with LDAP group memberships sign in through Keycloak, and **Vault
itself is the OIDC client**: the UI's login *is* a Vault login. The UI
trusts Vault; Vault trusts Keycloak. Door 2 and door 8 run on that.

## Deliverables

### OpenLDAP (`deploy/identity/openldap.yaml`)

- **arm64 image required.** Arcanium's `osixia/openldap` is amd64-only and
  will not run on CRC (no emulation). Evaluate candidates and record the
  choice + digest: an arm64 OpenLDAP image that runs under
  `restricted-v2` (random UID), or a small OpenLDAP image built in-cluster
  from a UBI/Alpine base via an OpenShift build. Avoid `anyuid` unless
  justified.
- Base DN `dc=reddoors,dc=local`, TLS optional (in-cluster only), PVC.
- Seed (idempotent LDIF via a Job):

| User | Groups | Role in the demo |
| --- | --- | --- |
| `ada` | `board`, `staff` | opens door 2 |
| `ben` | `staff` | **wrong key** at door 2 |
| `cleo` | `requesters`, `staff` | asks for the launch codes (door 8) |
| `dirk` | `approvers`, `staff` | approves door 8 |
| `eve` | `approvers`, `requesters`, `staff` | shows Vault refusing **self-approval** |
| `finn` | `auditors` | read-only audit view in the UI |

Passwords are generated into `.secrets/identity/users.json` (0600) on first
run, never committed; `make demo-users` prints them for the presenter.

### Keycloak (`deploy/identity/keycloak.yaml`)

- `quay.io/keycloak/keycloak` (multi-arch; record version + digest), its
  own small Postgres or dev-file storage on a PVC (decide, justify).
- Route `keycloak.apps-crc.testing` (edge/reencrypt TLS), hostname set so
  the `iss` claim matches the Route URL.
- Realm `red-doors`, LDAP user federation (read-only) + group mapper, client
  `vault` (confidential) with redirect URIs for the Red Doors UI callback
  (`https://doors.apps-crc.testing/auth/callback`) and the Vault UI
  (`https://vault.apps-crc.testing/ui/vault/auth/oidc/oidc/callback`),
  `groups` claim in the ID token.
- Bootstrap via `kcadm.sh`/admin API in a Job or script, **reconciling**
  (ensure realm, ensure client, ensure mapper) — reruns never recreate.
  Client secret → `.secrets/identity/vault-oidc-client-secret`.

### Vault OIDC (`terraform/vault-identity/`, namespace `red-doors`)

- `oidc/` auth method: discovery URL
  `https://keycloak.apps-crc.testing/realms/red-doors`,
  `oidc_discovery_ca_pem` = the CRC ingress CA (from
  `openshift-config-managed/default-ingress-cert`), client `vault`.
- **Verify in-cluster DNS** resolves `keycloak.apps-crc.testing` from the
  Vault pods; if not, document and apply the fix (e.g. CoreDNS forward or
  pod `hostAliases`) — don't switch to an http URL.
- Role `visitor`: `groups_claim=groups`, `user_claim=preferred_username`,
  `token_ttl=30m`, allowed redirect URIs as above, base policy
  `door-visitor` (token self-lookup only).
- External identity groups mapped from Keycloak groups: `board`,
  `requesters`, `approvers`, `auditors`.

### Door 2 — Board minutes

- Policy `door-2` on group `board`: `read` on `doors/data/2-board-minutes`.
- `ben` signs in fine but is denied at door 2 by Vault (no `board` group).

### Door 8 — Launch codes (control group)

- Policy `door-8-request` on group `requesters`:

  ```hcl
  path "doors/data/8-launch-codes" {
    capabilities = ["read"]
    control_group = {
      ttl = "10m"
      factor "two-person" {
        identity {
          group_names = ["approvers"]
          approvals   = 1
        }
      }
    }
  }
  ```

- Policy `door-8-approve` on group `approvers`: `update` on
  `sys/control-group/authorize`, `update` on `sys/control-group/request`.
- Verify Vault (not the UI) enforces: `cleo` reads → wrapping token +
  accessor; `dirk` authorizes → `cleo` unwraps → launch codes. `eve`
  requests and tries to approve her own request → Vault refuses
  (requester cannot satisfy her own factor). `finn` cannot request or
  approve.

## Validation

```sh
make identity-up && make identity-up      # idempotent
make demo-users
# Vault OIDC login as ada (vault login -method=oidc, browser) → policies include door-2 → read board minutes OK
# as ben → door 2 → 403
# door 8 full round trip cleo → dirk → cleo, and eve self-approval refused — paste the outputs
```

## Out of scope

The UI's sign-in screens (frontend prompts) — here, prove it with the Vault
CLI/UI.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
