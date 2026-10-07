# 06 — Rotate door 7 in Vault

`./scenarios/06_rotate_door7/run.sh` (≈ 1 min)

**Say:** "This application never talks to Vault. So how does it get a new password?"
**Click:** door 7 in the corridor (knock), run the script, knock again.
**They see:** the password changes in Vault, the Vault Secrets Operator syncs it into OpenShift and rolls the pod, and the next knock returns the new value — within seconds.
