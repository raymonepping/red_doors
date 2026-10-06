# Red Doors — prompts

Execute in this order. Each prompt is self-contained, starts by reading
`base_project/00_01_red_doors.md`, and ends with an **Execution log** the
run appends to (what was done, deviations and why, validation output).
Do not start a prompt before the previous one's validation passes.

| # | Prompt | Delivers |
|---|---|---|
| 0 | [base_project/00_01_red_doors.md](base_project/00_01_red_doors.md) | Vision, decisions, the eight doors, architecture, lessons, definition of done (read-only) |
| 1 | [base_project/01_01_openshift_local_cluster.md](base_project/01_01_openshift_local_cluster.md) | CRC sized + running, namespaces, repo spine, Makefile |
| 2 | [base_project/02_01_vault_seal_and_cluster.md](base_project/02_01_vault_seal_and_cluster.md) | Seal Vault + 3-node Vault Enterprise, Transit auto-unseal |
| 3 | [base_project/03_01_vault_terraform_baseline.md](base_project/03_01_vault_terraform_baseline.md) | Engines, auth methods, per-door policies, seeded values |
| 4 | [base_project/04_01_identity_stack.md](base_project/04_01_identity_stack.md) | OpenLDAP + Keycloak, Vault OIDC, doors 2 and 8 |
| 5 | [base_project/05_01_data_and_operator.md](base_project/05_01_data_and_operator.md) | PostgreSQL + dynamic creds (door 4), VSO (door 7) |
| 6 | [base_project/06_01_door_openers.md](base_project/06_01_door_openers.md) | Opener workloads, one identity each |
| 7 | [base_project/07_01_doors_api.md](base_project/07_01_doors_api.md) | API: knocks, door 8 workflow, audit collector |
| 8 | [frontend/01_00_red_doors_design_spec.md](frontend/01_00_red_doors_design_spec.md) | Door component + design contract (sign-off gate) |
| 9 | [frontend/01_01_corridor_ui.md](frontend/01_01_corridor_ui.md) | Nuxt UI + BFF: corridor, doors, approvals, audit, cluster |
| 10 | [base_project/08_01_resilience_and_rehydration.md](base_project/08_01_resilience_and_rehydration.md) | `make up`/`verify`, failure scenarios |
| 11 | [frontend/02_01_playwright_journeys.md](frontend/02_01_playwright_journeys.md) | Journeys for all doors + axe gate |
| 12 | [docs/01_write_documentation.md](docs/01_write_documentation.md) | README + docs set |

Design: every UI decision follows the user-level `vault-ui-design` skill
(Vault daylight glass). Canonical reference: `../arcanium`.
