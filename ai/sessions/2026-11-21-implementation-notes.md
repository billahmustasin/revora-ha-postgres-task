# Session notes (redacted) — 2026-11-21

Unedited process summary of the implementation session. Secrets omitted.

## Approach

1. Locked stack: kind + Patroni + Postgres 16 + WAL-G + MinIO + Prometheus.
2. Scaffolded Makefile, kind config, manifests, Docker image, scripts.
3. Hit Docker Hub pull denials for `minio/minio` → switched to `cleanstart/minio`.
4. Patroni ObjectCache ApiException loop:
   - First suspected missing `kubernetes` Python package → pinned/installed explicitly.
   - Root cause found via DEBUG logs: API calls to `namespaces//postgres-ha//...` (403).
   - Cause: top-level Patroni `namespace: /postgres-ha/` (etcd-style) used as K8s namespace.
   - Fix: `namespace: postgres-ha` without slashes; `use_endpoints: false` + label selectors.
5. Softened liveness probes so DCS bootstrap is not killed mid-start.
6. Docker Desktop crashed during image export (read-only FS); required Desktop/WSL restart before reload.

## Fixed before code

- Acceptance targets: up, lag, failover-test, backup, restore-test.
- Version pins in VERSIONS.md.

## Follow-ups for verifier

- Confirm `make failover-test` RTO and paste into README table.
- Confirm restore Job log contains `RESTORE TEST PASSED`.
