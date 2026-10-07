# Getting started

From an empty Mac to a signed-in corridor. Every command is run from the
repository root. Expected durations are from an M4 Pro (12 cores, 48 GB).

## 1. Install the tools

```sh
brew install bash jq terraform hashicorp/tap/vault node openssl
```

macOS ships bash 3.2; the scripts refuse to run on it. Homebrew's bash is
picked up through `#!/usr/bin/env bash` as long as `/opt/homebrew/bin` comes
first in your `PATH`.

Install **OpenShift Local** from
<https://console.redhat.com/openshift/create/local> (choose macOS,
download the installer, run it). Check with `crc version`.

## 2. Pull secret and licence

1. On the same Red Hat page, **Download pull secret**. Save it as
   `.secrets/crc/pull-secret.json`:

   ```sh
   mkdir -p .secrets/crc
   cp ~/Downloads/pull-secret.txt .secrets/crc/pull-secret.json
   ```

2. Put the Vault Enterprise licence at `lics/vault.hclic`.

Both paths are gitignored. Nothing under `.secrets/` or `lics/*.hclic` is
ever committed.

## 3. Start OpenShift Local

Stop the Podman machine first (`podman machine stop`): two VMs fighting
for memory caused clock drift and token failures before.

```sh
make crc-up
```

This sets 8 vCPU / 24 GB / 80 GB, runs `crc setup` if needed and starts
the cluster. **First start ≈ 10 minutes**; later starts ≈ 3–5 minutes. It
ends by copying CRC's admin kubeconfig to `.secrets/kube/config`; every
script uses that file, so you never need `oc login`.

The macOS password prompt during `crc setup` is expected (it adds the
`*.crc.testing` hosts entries).

## 4. Bring up Red Doors

```sh
make up
```

`make up` runs 15 steps, each safe to repeat
(`./scripts/rehydrate.sh --list` prints them):

| Step | What | From zero |
| --- | --- | --- |
| 1–3 | CRC check, namespaces, CA + Vault TLS certs | < 1 min |
| 4 | seal Vault (init + unseal), Transit key, then 3 main Vault nodes auto-unsealed | 3–4 min |
| 5–8 | admin token, audit devices, auth methods/engines/policies (Terraform), door values | 1–2 min |
| 9 | OpenLDAP (built in-cluster) + Keycloak + Vault OIDC | 4–5 min |
| 10–11 | PostgreSQL + database engine, Vault Secrets Operator | 2–3 min |
| 12–14 | door openers, API, UI (built in-cluster) | 4–6 min |
| 15 | `make verify` | 10 s |

If a step fails, it prints the step number; fix the cause and resume with
`make up FROM=<n>`. A converged second run takes about 50 seconds and
changes nothing.

Vault's init output (unseal key, root token) is written to
`.secrets/vault/`. Keep that directory: without it the seal Vault cannot
be unsealed after a restart.

## 5. Verify

```sh
make verify
```

Expect `✓ All checks passed (40 pass, 0 warn)`. Any `✗` names what to run.

## 6. Sign in

```sh
make demo-users
```

| User | Group | Can |
| --- | --- | --- |
| ada | board | open door 2; knock on machine doors |
| ben | staff | sign in, but door 2 refuses him |
| cleo | requesters | request the launch codes (door 8) |
| dirk | approvers | approve someone else's request |
| eve | requesters + approvers | request; her self-approval does not count |
| finn | auditors | look at everything, change nothing |

Open <https://doors.apps-crc.testing> → **Sign in** → Keycloak login →
back in the corridor. The browser warns about the certificate the first
time: it is signed by OpenShift Local's ingress CA. To trust it, and the
project CA that signs the Vault UI, run (asks for your password):

```sh
make trust          # make trust-status to check, make untrust to undo
```

Restart the browser afterwards.

## 7. Next

- Rehearse with the [demo guide](demo-guide.md).
- `make down` at the end of the day — it keeps every PVC and `.secrets/`.
- Something odd? [Troubleshooting](troubleshooting.md).

Other URLs: Vault UI <https://vault.apps-crc.testing> (token:
`.secrets/vault/admin-token`, namespace `red-doors`; its certificate comes
from the project CA, which `make trust` also trusts), Keycloak
<https://keycloak.apps-crc.testing>, OpenShift console via
`make crc-console`.
