# Prompt 01 — OpenShift Local cluster + repo spine

## Context

Read `00_01_red_doors.md` first. The Mac is an Apple M4 Pro (12 cores,
48 GB RAM). OpenShift Local is installed (`/usr/local/bin/crc`, CRC 2.64,
OpenShift 4.22.14, bundle already downloaded to `~/.crc/cache`). No CRC VM
exists yet. The Podman machine is normally stopped while Red Doors runs —
the two VMs must not compete for memory (past incidents: CPU starvation →
VM clock drift → JWT/TOTP failures).

`red_doors/` already has: README, CHANGELOG, CONTRIBUTING, LICENSE (empty),
`.gitignore`, `.dockerignore`, `.gitleaks.toml`, `.env.example`,
`.github/` (gitleaks + release workflows), an empty `main.tf`.

## Goal

A running, correctly sized OpenShift Local cluster that `make` can start,
stop and inspect, plus the repository spine every later prompt builds on.

## Deliverables

### CRC configuration (`make crc-up`)

- `crc config set preset openshift`, `cpus 8`, `memory 24576` (24 GB),
  `disk-size 80`, `consent-telemetry no`. Justify the numbers in a comment:
  OpenShift itself ≈ 10–11 GB; Vault ×4, Keycloak, OpenLDAP, Postgres, VSO,
  API, UI and seven openers ≈ 6–7 GB; headroom for builds.
- Pull secret read from `.secrets/crc/pull-secret.json` (gitignored; the
  user downloads it from console.redhat.com/openshift/create/local).
  `make crc-up` fails with a clear message if it is missing.
- `crc setup` (idempotent) then `crc start -p <pull-secret>`.
- After start: `eval $(crc oc-env)`, log in as `kubeadmin` with the
  password from `crc console --credentials`, write a dedicated kubeconfig to
  `.secrets/kube/config` and make every script use `KUBECONFIG` from there
  (never touch `~/.kube/config`).
- Refuse to start if the Podman machine is running, unless
  `ALLOW_PODMAN=1` (print why).

### Make targets (`Makefile`, `make help` self-documenting like Arcanium)

`crc-up`, `crc-down` (stop, keep VM), `crc-status`, `crc-console` (open the
web console + print credentials), `oc-login`, `namespaces`, `status`
(nodes, cluster operators degraded/available summary, our namespaces' pods),
`help`. Every target idempotent.

### Namespaces (projects)

`rd-vault-seal`, `rd-vault`, `rd-identity`, `rd-data`, `rd-doors`, `rd-app`,
each labelled `app.kubernetes.io/part-of=red-doors`. Managed by a manifest
under `deploy/base/namespaces.yaml` applied with `oc apply`.

### Internal registry

Confirm the image registry is available for OpenShift builds; expose its
default route only if a later step needs pulling from the Mac (it should
not — builds happen in-cluster).

### Repo layout (create empty folders with a one-line README where useful)

```text
deploy/        manifests + Helm values per component (base/, vault-seal/, vault/, identity/, data/, doors/, app/)
terraform/     Vault configuration modules (prompt 03+)
scripts/       bash helpers (set -euo pipefail, shellcheck-clean)
openers/       door opener workload (prompt 06)
api/           Express API (prompt 07)
ui/            Nuxt 4 UI (frontend prompts)
lics/          Vault licence (gitignored except README)
.secrets/      everything secret (gitignored)
docs/          documentation
```

- `.gitignore` must cover `.secrets/`, `lics/*.hclic`, `.env`, `*.kubeconfig`,
  `vault-tls/*.key`, `node_modules`, `.nuxt`, `.output`, `.terraform`,
  `*.tfstate*`, `._*`. Verify with `git check-ignore`.
- `.dockerignore` adds `._*`, `.secrets`, `node_modules`.
- Remove the placeholder `main.tf` (Terraform lives in `terraform/`) and
  fill `LICENSE` (ask the user which licence if not obvious; Arcanium's is
  the reference).

## Validation

```sh
make crc-up            # first run creates the VM; second run is a no-op
make status            # 1 node Ready; no Degraded cluster operators
oc --kubeconfig .secrets/kube/config get ns -l app.kubernetes.io/part-of=red-doors   # 6 namespaces
crc status             # Running, disk/memory as configured
git status --short     # no secret material staged; check-ignore covers .secrets/
```

Also record: time to first start, memory used by the VM at idle, and
whether `crc start` after a Mac sleep needs anything extra.

## Out of scope

Vault, identity, apps. Do not install operators yet.

## Execution log

Appended by each run: what was done, deviations and why, validation output.

### Run 1 — 2026-10-06

#### Done

- First `crc start` was run by hand before this prompt executed: Podman
  Desktop's OpenShift Local extension sat at "Initializing" indefinitely.
  `crc setup --check-only` showed setup had completed; the extension was
  waiting on a VM that did not exist yet. Bypassed it with
  `crc start -p .secrets/crc/pull-secret.json` from the CLI. Pull secret
  from `~/Downloads/pull-secret.txt` → `.secrets/crc/pull-secret.json`
  (0600, gitignored, JSON validated: 4 registries).
- `scripts/lib.sh` (shared helpers, project `KUBECONFIG`, `crc oc-env` for
  `oc`), `scripts/crc.sh` (`up|down|status|console|login`), `Makefile`
  (`help`, `crc-up`, `crc-down`, `crc-status`, `crc-console`, `oc-login`,
  `namespaces`, `status`), `deploy/base/namespaces.yaml` (6 namespaces,
  labelled + described).
- Repo layout: `deploy/{base,vault-seal,vault,identity,data,doors,app}`,
  `terraform/`, `openers/`, `api/`, `ui/`, `lics/` with one-line READMEs.
  Placeholder `main.tf` removed.
- `.gitignore` gained `lics/*.hclic`, `*.kubeconfig`, `.nuxt/`, `.output/`,
  `._*` (all five were previously tracked); `.dockerignore` gained `._*`,
  `.secrets`, `.nuxt`, `.output`.

#### Deviations

- **Kubeconfig = CRC's system:admin client certificate, not a kubeadmin
  login.** `oc login -u kubeadmin` yields a token that expires after 24h,
  which would break every script daily. `~/.crc/machines/crc/kubeconfig`
  authenticates `system:admin` with a client cert valid until 2036; it is
  copied to `.secrets/kube/config` (0600) on every `make crc-up` /
  `make oc-login` because a recreated VM gets a new CA. `kubeadmin`
  credentials remain available via `make crc-console`.
- CRC does not persist a config value equal to its default (`preset`), so
  `ensure_config` treats "Default value 'X' is used" as X — otherwise every
  run re-set it.
- `LICENSE` left empty: the scaffold README says MIT but Arcanium (the
  reference) is GPL-3.0 — asked the user.
- The Podman-running refusal could not be exercised live (CRC was already
  running, which skips the check by design; Podman stopped). Logic reviewed,
  shellcheck clean.

#### Validation output

```text
shellcheck -x scripts/*.sh          → clean
make crc-up (×2)                    → "CRC already running", kubeconfig refreshed, no config changes
make namespaces (×2)                → 6 created, then 6 unchanged
make status                         → CRC running — OpenShift 4.22.14, RAM 7.3 / 25.1 GB, disk 25 / 85 GB
                                       node crc Ready v1.35.6
                                       cluster operators: 24/24 available, 0 degraded
                                       internal image registry: Managed
                                       rd-* namespaces present, no pods
oc get ns -l app.kubernetes.io/part-of=red-doors → rd-app rd-data rd-doors rd-identity rd-vault rd-vault-seal
git check-ignore                    → .secrets/, lics/*.hclic, .env, *.kubeconfig, vault-tls/*.key,
                                       node_modules, .nuxt, .output, .terraform, *.tfstate*, ._* all ignored
```

#### Recorded

- First start ≈ 10 min (VM create → operators stable 3/3).
- Idle memory: 7.3–7.7 GB of the 24 GB VM; disk 26 GB of 80 GB.
- Mac sleep/resume: not yet observed — to record on the next resume.
- Host prep that run: 33 GB of caches cleared (npm, Homebrew, Trash,
  `~/Library/Caches`) to give CRC disk headroom; Podman machine stopped
  (0 containers) to free RAM.
