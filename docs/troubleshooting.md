# Troubleshooting

Real problems hit while building Red Doors (prompts 01–08 and the UI
prompts), each as symptom → cause → fix. Start with `make verify`: every
✗ names the broken part, and `make up` repairs anything that drifted
without touching data.

## OpenShift Local

**`crc start` hangs or the Mac crawls; later, tokens fail with clock errors.**
Cause: the Podman machine is running alongside CRC; the two VMs starve each
other and the guest clock drifts.
Fix: `podman machine stop`. `make crc-up` refuses to start while Podman
runs (override with `ALLOW_PODMAN=1` only if you know why).

**After the Mac wakes from sleep, random Kubernetes logins fail for ~40 s
with `invalid expiration time (exp) claim: token is expired`.**
Cause: on wake, the VM's clock jumps forward (chronyd: "Forward time jump
detected"). Projected service-account tokens already on disk are past
their `exp` until the kubelet refreshes them.
Fix: wait a minute and retry. Before a demo, keep the Mac plugged in and
awake. Check with
`ssh -i ~/.crc/machines/crc/id_ed25519 -p 2222 core@127.0.0.1 journalctl -u chronyd`.

**After a long sleep, builds fail: `Failed to push image … authentication required`.**
Cause: the builder service account's registry token went stale in the
clock jump.
Fix: delete the controller-managed secret; OpenShift recreates it at once:
`oc -n rd-app delete secret $(oc -n rd-app get sa builder -o jsonpath='{.imagePullSecrets[0].name}')`,
then rerun the build (`make api-up` / `make ui-up`). Pulls recover on their
own within a minute.

**`oc` says "Unauthorized" / wrong cluster after recreating the VM.**
Cause: a recreated VM has a new CA; the old `.secrets/kube/config` no
longer matches.
Fix: `make oc-login` (copies CRC's admin kubeconfig again).

**Scripts fail with syntax errors on `declare -A` or `${var,,}`.**
Cause: macOS `/bin/bash` is 3.2.
Fix: `brew install bash`; the scripts refuse to run on bash < 4.

## Vault

**Main Vault pods in CrashLoopBackOff after a restart.**
Cause: with `seal "transit"`, Vault exits at startup when the seal Vault is
sealed.
Fix: `make vault-unseal`. The init container `wait-for-seal-vault` now
makes the pods wait instead of crash-looping.

**Main cluster seals after weeks of running; logs show 403 on transit.**
Cause: the seal token expired. A 24 h token is not enough when the laptop
is off for days.
Fix: the token is periodic 720 h and `make up` re-issues it below 1 h;
`make seal-token-status` shows it.

**Raft peers advertise `https://$(HOSTNAME):8200` literally.**
Cause: Kubernetes only expands `$(VAR)` for variables defined earlier in
the env list.
Fix: keep the chart default `api_addr` (`$(POD_IP)`).

**Terraform gets 403 on paths like `red-doors/red-doors/...`.**
Cause: an exported `VAULT_NAMESPACE` is prefixed on top of the module's
own namespace.
Fix: `scripts/tf.sh` unsets `VAULT_NAMESPACE`; always run Terraform via
`make tf-*`.

**Every request denied right after changing the door-8 EGP.**
Cause: the Sentinel policy referenced `controlgroup` without
`import "controlgroup"`; a failing EGP denies everything on its paths.
Fix: keep the import; test EGP changes with `make api-smoke`.

**Eve could approve her own launch-code request.**
Cause: the control group counts "one member of approvers", and eve is one.
Fix: Sentinel EGP `door-8-two-different-people` (Vault enforces it, not the UI).

**Door 5 refusal shows HTTP 500, not 403.**
Cause: Vault answers an expired client certificate with 500.
Fix: none needed; the opener classifies it as refused.

**Probe/debug pods get the `anyuid` SCC.**
Cause: OpenShift picks the most permissive SCC the SA may use.
Fix: annotate pods with `openshift.io/required-scc: restricted-v2`.

## Identity

**Names in the UI show the full `cn` instead of the first name.**
Cause: Keycloak's default LDAP first-name mapper reads `cn`.
Fix: `make identity-up` sets it to `givenName`.

## Data and API

**The UI shows `password authentication failed for user "v-red-door-api-rw-…"`.**
Cause: the API's database lease was revoked while the host slept; a single
long `setTimeout` woke too late to renew it.
Fix: built in now. The API checks its renewal deadline against the wall
clock every 15 s and re-mints on a refused login (`28P01`). On an old
image: `oc -n rd-app rollout restart deploy/red-doors-api`.

**`psql -v name=value -c "…:'name'…"` doesn't substitute.**
Cause: psql variables are not interpolated in `-c` strings.
Fix: pipe SQL on stdin (the scripts do).

**The audit drawer says "collector offline".**
Cause: the API (which hosts the socket collector) is down or restarting.
Vault keeps serving through its stdout audit device.
Fix: `make api-up`; Vault reconnects the socket by itself.

**Door 7 shows no audit entries.**
Not a fault: opener-7 reads the Secret VSO mounted and never calls Vault
per knock.

## UI

**No navigation or sign-out on a phone.**
Fixed: the menu button opens the navigation sheet; the persona stays
visible in the top bar.

**A page scrolls horizontally on a phone.**
Cause: grid children without `min-width: 0` cannot shrink.
Fix: keep the `min-width: 0` guards when adding grid layouts.

**Playwright runs take hours and fail with sign-in pages.**
Cause: the Mac slept during the run (lid closed on battery); sessions
expired and every wait timed out. `caffeinate` cannot prevent lid-closed
battery sleep.
Fix: run with the Mac awake and plugged in; `make ui-test` takes ~4 min.

## Shell gotchas

- An `ls` alias to `eza --icons` stalls without a TTY. Scripts avoid bare
  `ls`.
- In zsh, unquoted globs that match nothing abort the command; quote them.
