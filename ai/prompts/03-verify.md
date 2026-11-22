# Prompt: Verify phase

Given this repository, produce/adjust verification so that:

1. `make up` yields Ready pods with one `role=master` and two `role=replica`.
2. `make lag` shows streaming replicas.
3. `make failover-test` deletes primary, measures RTO_SECONDS, confirms rejoin.
4. `make backup` creates a WAL-G backup visible via `wal-g backup-list`.
5. `make restore-test` Job succeeds; optional PITR with TARGET_TIME.

If something fails, diagnose from pod logs and Kubernetes API errors (watch for wrong Patroni namespace path like `/postgres-ha/`), fix the root cause, and re-run only the failing target. Document measured RTO in README.
