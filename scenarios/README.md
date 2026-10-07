# Scenarios

Each scenario prints what to watch, checks the outcome from real system state, and ends with PASS/FAIL. Run them on a converged estate (`make up && make verify`). `make scenarios` runs 01–06 in order.

| # | Scenario | Script |
| --- | --- | --- |
| 01 | Kill the active Vault pod | [01_kill_leader](01_kill_leader/README.md) |
| 02 | The seal Vault restarts | [02_seal_vault_restart](02_seal_vault_restart/README.md) |
| 03 | Cold start | [03_cold_start](03_cold_start/README.md) |
| 04 | Audit collector offline | [04_collector_offline](04_collector_offline/README.md) |
| 05 | Short-lived authority ends | [05_expiry](05_expiry/README.md) |
| 06 | Rotate door 7 in Vault | [06_rotate_door7](06_rotate_door7/README.md) |
