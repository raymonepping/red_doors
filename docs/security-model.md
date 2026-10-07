# Security model

Red Doors makes one claim: **every decision about a door is made by Vault,
from the identity presented, and nothing else in the system can make or
fake it.** This page states what each component can and cannot do, so that
claim can be checked.

## Trust boundaries

```text
operator ──unseal key──► seal Vault ──Transit (encrypt/decrypt only)──► main Vault cluster
                                                                         │
             OpenShift TokenReview ◄── Kubernetes auth ──────────────────┤
             Keycloak → OpenLDAP   ◄── OIDC auth ────────────────────────┤
             project issuing CA    ◄── TLS cert auth ────────────────────┤
             PostgreSQL            ◄── database engine (vault_admin) ────┘
```

1. **The seal Vault is the root of trust.** Whoever can unseal it can
   bring the main cluster up; nobody else can. Its token for the main
   cluster may only encrypt/decrypt with key `autounseal`.
2. **The main Vault cluster is the only decision point.** Door values,
   policies, the control group and the Sentinel EGP all live there, in
   namespace `red-doors`.
3. **Identity providers vouch; they do not decide.** OpenShift says which
   service account a token belongs to, Keycloak/LDAP say who a person is
   and which groups they are in, the issuing CA says a certificate is
   genuine. Vault maps that to exactly one role and policy.

## What each component can and cannot do

| Component | Can | Cannot |
| --- | --- | --- |
| seal Vault token | encrypt/decrypt with `transit/keys/autounseal` | read anything, manage the seal Vault |
| each opener | log in as its own identity; read its own door | read another door (policies are per path); keep a token (revoked after each knock) |
| impostor | log in as a real identity; read the lobby | read any door: that is what "wrong key" shows |
| API (`rd-api`) | mint door-3 secret-ids **wrapped** (30 s – 2 min, enforced by Vault); read policy text and the EGP for display; resolve entity → group names; get its own DB login | read any door path (verified: capabilities on all 7 door paths → deny); unwrap anything; open door 2 or 8 (those use the person's token) |
| UI + BFF | hold the person's Vault token and door-8 wrapping tokens in a server-side session | expose a Vault token to the browser; decide an outcome (it displays Vault's answer) |
| VSO (`vso-door-7`) | read door 7 and write it into one Secret in `rd-doors` | read other doors |
| people | what their groups' policies allow (board → door 2, requesters → request door 8, approvers → authorize others' requests, auditors → metadata) | approve their own door-8 request (Sentinel EGP), read door 8 without approval (control group) |
| PostgreSQL | store payroll rows, merger **ciphertext**, API attempts and audit entries | decrypt the merger memo; see released values (never stored) |

## Why the API cannot read door secrets

The API is the component most likely to be "convenient" to over-privilege,
so it is deliberately blind:

- Its policy (`terraform/vault-api/rd-api.hcl`) grants no path under
  `doors/`, `database/creds/payroll-reader`, `transit/` or `pki-int/`.
- For door 3 it can create a secret-id only as a wrapped response; it
  never holds the role-id, so even an unwrapped secret-id would be useless
  to it.
- Released values pass from opener → API → browser once and are never
  persisted: `api.attempts` stores identity, decision, denial and Vault
  request ids only.
- `make api-smoke` checks `sys/capabilities-self` for `rd-api` on every
  door path and fails unless all are `deny`.

## Short-lived authority

Machine tokens live 2–5 minutes and are revoked after use; door 4 logins
are dropped from PostgreSQL right after the knock; door 5 certificates
live 10 minutes; door 3 envelopes are single-use; door 8 requests expire
after 10 minutes. [Scenario 05](../scenarios/05_expiry/README.md) shows
each refusal coming from Vault or PostgreSQL.

## Audit

Two audit devices: stdout (always available) and a socket to the API's
collector. Vault HMACs sensitive fields; the UI shows them as HMACs. The
collector being down never blocks Vault.

## What is demo-grade

Acceptable for a laptop demo, not for production:

- **OpenShift Local**: one node, so "HA" is three pods on one VM.
  Anti-affinity is disabled.
- **Seal Vault with one Shamir share** stored in `.secrets/` next to the
  repo. Production: several key holders, or an HSM/cloud KMS seal.
- **Self-signed project CA** for Vault TLS, and OpenShift Local's ingress
  CA for Routes; browsers trust neither by default.
- **Root and admin tokens on disk** (`.secrets/vault/`). Production: root
  revoked after bootstrap; admin access via an auth method with MFA.
- **Keycloak in dev-file storage**, OpenLDAP with demo users and generated
  passwords printed by `make demo-users`.
- **PostgreSQL without TLS** inside the cluster (`sslmode=disable`).
- **Long periodic tokens** (720 h) so the estate survives a laptop being
  off for days.
- **The same person in requesters and approvers** (eve), on purpose, to
  show the EGP.
