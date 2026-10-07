# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-07

### Added

- OpenShift Local (CRC 2.64 / OCP 4.22) estate: six `rd-*` namespaces,
  NetworkPolicies, `restricted-v2` workloads, in-cluster builds.
- Vault Enterprise 2.1: in-cluster seal Vault (Transit auto-unseal) and a
  3-node Raft cluster; TLS with a project CA; `make vault-*`.
- Terraform for namespace `red-doors`: auth methods, engines, per-door
  policies, control group + Sentinel EGP, audit devices, API identity.
- Identity stack: OpenLDAP (built in-cluster) + Keycloak + Vault OIDC.
- PostgreSQL with Vault dynamic credentials; merger ciphertext (Transit);
  Vault Secrets Operator for door 7.
- Seven door openers and the eight doors.
- API (Express 5) with its own Vault identity, socket audit collector,
  OpenAPI contract, unit tests and a 39-check live smoke test.
- UI (Nuxt 4 SPA + BFF) in the Vault daylight glass design: corridor,
  door pages, decision panel, approvals, audit, cluster.
- `make up` / `down` / `verify` / `reset`, resilience scenarios 01–06.
- Playwright journeys + axe WCAG 2.1 AA gate (`make ui-test`).
- Documentation: getting started, architecture, doors, demo guide,
  operations, troubleshooting, security model.

### Fixed

- API database credentials renew against the wall clock and re-mint on a
  refused login (host sleep no longer breaks the API).
