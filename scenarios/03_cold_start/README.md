# 03 — Cold start

`./scenarios/03_cold_start/run.sh` (≈ 2 min)

**Say:** "Power cut: everything down. Who brings Vault back?"
**Click:** **Cluster** page; run the script.
**They see:** the main Vault pods wait (no crash loop) while the seal Vault is sealed; one operator unseal of the seal Vault and the main cluster unseals itself within seconds — no main-cluster keys involved.
