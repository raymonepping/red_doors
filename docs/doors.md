# The doors

Each door: what is behind it, how Vault decides, who owns it, the wrong
key, what the audience sees, and what can go wrong. Doors appear in the
corridor in **story order** (1, 3, 5, 2, 4, 6, 7, 8): machines first, then
people, then two people.

Policies live in Vault namespace `red-doors`; the UI shows them verbatim
from Vault (read live by the API), not from this page. Source:
`terraform/vault-doors/policies/` and `terraform/vault-identity/policies/`.

---

## Door 1 — Production deploy key · Kubernetes auth

- **Owner:** pod `opener-1`, service account `rd-doors:opener-1`, role
  `opener-1`.
- **How:** the pod sends its projected service-account token (audience
  `vault`, 10-min lifetime). Vault checks it with OpenShift's TokenReview
  and maps it to exactly one role. Token TTL 5 min, revoked after use.

  ```hcl
  path "doors/data/1-production-deploy-key" { capabilities = ["read"] }
  ```

- **Wrong key:** the impostor, a real service account whose role grants
  only the lobby → `403 permission denied` on the door path.
- **Audience sees:** a pod with no password opens a door; a different pod
  with a perfectly valid identity is refused.
- **Can go wrong:** right after the Mac wakes from sleep, logins can fail
  for ~40 s with `token is expired` (VM clock jump); wait and knock again.

## Door 3 — Partner API key · AppRole, response-wrapped secret-id

- **Owner:** `opener-3`, which holds only the **role-id** (`door-3`).
- **How:** per knock, the API asks Vault for a secret-id. Its policy
  forces the response to be wrapped (30 s – 2 min), so the API gets an
  envelope it cannot open. opener-3 looks up the wrapping token (checks
  where it was created), unwraps it once, logs in, reads, revokes.
  secret-id TTL 5 min; token TTL 5 min.

  ```hcl
  path "doors/data/3-partner-api-key" { capabilities = ["read"] }
  ```

- **Wrong key:** replaying a wrapping token that was already unwrapped →
  Vault refuses (`wrapping token is not valid or does not exist`).
- **Audience sees:** tamper evidence: if anyone opened the envelope first,
  the rightful owner's unwrap fails and the door stays shut.
- **Can go wrong:** an envelope older than its wrap TTL is refused
  ([scenario 05](../scenarios/05_expiry/README.md) shows this on purpose).

## Door 5 — Treasury wire room · PKI + TLS certificate auth

- **Owner:** `opener-5`, in two steps:
  1. as SA `opener-5` (role `opener-5-issuer`) it may **only** issue a
     certificate from `pki-int/issue/treasury-client` (CN
     `opener-5.rd-doors`, TTL 10 min, max 30 min);
  2. it then logs in **with that certificate** at `cert/treasury`, which
     is the identity that may read the door.

  ```hcl
  # door-5-issuer
  path "pki-int/issue/treasury-client" { capabilities = ["update"] }
  # door-5
  path "doors/data/5-treasury-wire-room" { capabilities = ["read"] }
  ```

- **Wrong key:** a self-signed certificate with exactly the right CN →
  refused: the cert role trusts only the project's issuing CA.
- **Audience sees:** two identities in a row: the key cutter cannot open
  the door, only the key can, and it expires in 10 minutes.
- **Can go wrong:** Vault answers an *expired* client certificate with
  HTTP 500, not 4xx; the opener still reports it as refused.

## Door 2 — Board minutes · OIDC (a person)

- **Owner:** anyone in LDAP group `board` (ada).
- **How:** sign-in is a Vault OIDC login (`oidc`, role `visitor`). Vault
  sends the browser to Keycloak, Keycloak checks the password against
  OpenLDAP and returns the groups claim; Vault maps the group to identity
  group `board` with policy `door-2`. The door is opened with **the
  person's own token**.

  ```hcl
  path "doors/data/2-board-minutes" { capabilities = ["read"] }
  ```

- **Wrong key:** ben, signed in correctly, not on the board → `403`.
- **Audience sees:** same Vault, same door: the group decides.
- **Can go wrong:** names shown as `cn` instead of first name means the
  Keycloak first-name mapper drifted; `make identity-up` restores it.

## Door 4 — Payroll database · dynamic credentials

- **Owner:** `opener-4` (role `opener-4`).
- **How:** Vault creates a PostgreSQL login for this knock
  (`database/creds/payroll-reader`: `SELECT` on `payroll` only, TTL 5 min,
  max 10 min). The opener reads rows, then revokes the lease, and the login
  is dropped from PostgreSQL immediately.

  ```hcl
  path "database/creds/payroll-reader" { capabilities = ["read"] }
  ```

- **Wrong key:** the impostor asking for payroll credentials → `403`.
- **Audience sees:** a generated username (`v-red-door-payroll-…`), its
  lifetime, and that it is gone right after.
- **Can go wrong:** if Vault's own `vault_admin` connection fails, run
  `make data-up` (it re-applies the database engine config).

## Door 6 — Merger documents · Transit, decrypt-only

- **Owner:** `opener-6` (role `opener-6`).
- **How:** the memo is stored in PostgreSQL **only as ciphertext**
  (`rd-data/reddoors.merger_docs`). The opener fetches it and asks Vault to
  decrypt with key `merger-docs`. Then it tries to *encrypt* with the same
  identity, to prove that is refused.

  ```hcl
  path "transit/decrypt/merger-docs" { capabilities = ["update"] }
  ```

- **Wrong key:** the impostor trying to decrypt → `403`.
- **Audience sees:** plaintext appears; the same identity's encrypt
  attempt is refused. Decrypt-only means exactly that.
- **Can go wrong:** an empty `merger_docs` table → `make data-up` re-seeds
  the ciphertext.

## Door 7 — Customer DB password · Vault Secrets Operator

- **Owner:** `opener-7`, which **never talks to Vault**. VSO authenticates
  as SA `vso-door-7` (policy `door-7`), syncs
  `doors/7-customer-db-password` into Secret `door-7-customer-db`, mounts
  it into opener-7 and rolls the pod when it changes.

  ```hcl
  path "doors/data/7-customer-db-password" { capabilities = ["read"] }
  ```

- **Wrong key:** a pod the operator never synced the Secret into → "no
  Secret door-7-customer-db is mounted in this pod".
- **Audience sees:** `make door7-rotate` writes a new password in Vault;
  within seconds VSO syncs it, rolls the pod, and the next knock shows the
  new value ([scenario 06](../scenarios/06_rotate_door7/README.md)).
- **Note:** a knock on door 7 produces **no Vault audit entry**: there is
  no Vault call per knock. The sync shows up as VSO's own reads.

## Door 8 — Launch codes · control group + Sentinel EGP

- **Owner:** a requester (cleo or eve) **plus a different** approver
  (dirk, or eve for someone else's request).
- **How:** the read is governed by a control group:

  ```hcl
  path "doors/data/8-launch-codes" {
    capabilities = ["read"]
    control_group = {
      ttl = "10m"
      factor "two-person" {
        identity { group_names = ["approvers"]  approvals = 1 }
      }
    }
  }
  ```

  The request returns a **wrapped, pending** answer that the BFF keeps in
  the requester's server-side session. An approver authorizes it
  (`door-8-approve`: `sys/control-group/authorize` and `/request`). The
  requester unwraps once.

  Eve is in both `requesters` and `approvers`, so the control group alone
  would let her approve herself. The Sentinel EGP
  `door-8-two-different-people` closes that gap:

  ```sentinel
  import "controlgroup"
  authz = controlgroup.authorizations else []
  requester = identity.entity.id else ""
  others = filter authz as a { a.entity.id is not requester }
  main = rule { length(authz) is 0 or length(others) > 0 }
  ```

- **Wrong key:** eve approving her own request → Vault records it,
  reports `approved: false`, and her open is refused ("needs further
  authorization"). finn (auditor) and ben cannot approve at all.
- **Audience sees:** three browsers, three people; self-approval visibly
  does not count, and the codes open exactly once.
- **Can go wrong:** an unapproved request expires after 10 minutes, and so
  does an approved one that is not opened in time.
