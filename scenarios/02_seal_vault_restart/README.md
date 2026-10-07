# 02 — The seal Vault restarts

`./scenarios/02_seal_vault_restart/run.sh` (≈ 1 min)

**Say:** "The seal Vault holds the key that unseals the main cluster. What if *it* restarts?"
**Click:** **Cluster** page; run the script.
**They see:** the seal Vault turns **SEALED**, the main cluster keeps serving and doors keep opening (it is already unsealed); `make vault-unseal` restores the chain.
