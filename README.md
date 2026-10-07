# Red Doors

Eight red doors on OpenShift. Behind each one is something a business
guards: a deploy key, the board minutes, the payroll database, the launch
codes. Each door opens for exactly **one kind of identity** (a pod, a
person, a certificate, a second approver), and **HashiCorp Vault Enterprise
is the only thing that decides**. The UI never fakes an outcome: every
"opened" and every "refused" on screen is Vault's own answer, with the
policy that caused it and the audit entries that recorded it.

It runs entirely on a laptop: OpenShift Local (CRC) with a 3-node Vault
Enterprise cluster that is auto-unsealed by a second, in-cluster "seal
Vault", plus OpenLDAP, Keycloak, PostgreSQL and the Vault Secrets Operator.

## The eight doors

| # | Behind the door | Opened by | Vault method | Wrong key (refused by Vault) |
| --- | --- | --- | --- | --- |
| 1 | Production deploy key | pod `opener-1` | Kubernetes auth | a real service account with no business here |
| 2 | Board minutes | a person in LDAP group `board` (ada) | OIDC (Keycloak → LDAP) | a signed-in colleague not on the board (ben) |
| 3 | Partner API key | `opener-3` | AppRole, secret-id response-wrapped | a replayed, already-used wrapping token |
| 4 | Payroll database | `opener-4` | Dynamic PostgreSQL credentials | the impostor asking for payroll credentials |
| 5 | Treasury wire room | `opener-5` | PKI-issued 10-min cert + TLS cert auth | a self-signed cert with exactly the right name |
| 6 | Merger documents | `opener-6` | Transit, decrypt-only | the impostor trying to decrypt |
| 7 | Customer DB password | `opener-7` | Vault Secrets Operator | a pod the operator never synced the Secret into |
| 8 | Launch codes | requester (cleo) + a *different* approver (dirk) | Control group + Sentinel EGP | approving your own request (eve) |

Details per door: [docs/doors.md](docs/doors.md).

## Prerequisites

- **Mac with Apple Silicon**, 48 GB RAM recommended (the VM takes 24 GB /
  8 vCPU / 80 GB disk). The Podman machine must be **stopped**.
- **OpenShift Local (`crc`)** installed — [download](https://console.redhat.com/openshift/create/local).
- **Red Hat pull secret** (free Red Hat account) saved as
  `.secrets/crc/pull-secret.json`.
- **Vault Enterprise licence** saved as `lics/vault.hclic`.
- Tools: `oc` (bundled with CRC), `vault`, `terraform`, `jq`, `node` ≥ 24,
  `openssl`, GNU `bash` ≥ 4 (`brew install bash`).

## Run it

```sh
make crc-up      # first time ≈ 10 min: configure + start OpenShift Local
make up          # ≈ 15–20 min from zero, ≈ 1 min when already converged
make verify      # 40 checks, every door owner-opens / wrong-key-refused
make demo-users  # sign-in names and passwords
```

Open **<https://doors.apps-crc.testing>**, sign in as `ada`, and walk the
corridor (keys: `←` `→` move, `K` knock, `W` wrong key, `D` decision).
The certificate is from OpenShift Local's own CA; accept it, or trust
`vault-tls/ingress-ca.pem` in your keychain.

`make down` stops everything and keeps all data; `make up` brings it back.

## Documentation

| Doc | For |
| --- | --- |
| [Getting started](docs/getting-started.md) | first run from zero |
| [Demo guide](docs/demo-guide.md) | 15- and 5-minute run sheets, what to say |
| [Doors](docs/doors.md) | each door: method, policy, owner, wrong key |
| [Architecture](docs/architecture.md) | namespaces, seal chain, identities, audit |
| [Security model](docs/security-model.md) | trust boundaries, what is demo-grade |
| [Operations](docs/operations.md) | every `make` target, secrets, renewals, a ninth door |
| [Troubleshooting](docs/troubleshooting.md) | real problems and their fixes |
| [Scenarios](scenarios/README.md) | failover, seal restart, cold start, expiry, rotation |
| [UI design](docs/frontend/DESIGN.md) | the Vault daylight glass design system |

## License

[GPL-3.0](LICENSE)
