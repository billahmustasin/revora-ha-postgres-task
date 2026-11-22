# Prompt: Design phase

You are designing a PostgreSQL HA system on Kubernetes for a take-home assignment.

Constraints:
- No Postgres operators (CloudNativePG, Crunchy, Zalando operator, Bitnami postgresql-ha, managed DBs).
- Patroni or repmgr allowed if we deploy and wire them ourselves.
- Must: 1 primary + 2 replicas, streaming replication, stable primary + replica endpoints, automatic failover with fencing, WAL archive + base backups to S3-compatible storage, PITR, automated restore test, single entrypoint up/down.
- Prefer a small explainable system over a large opaque one.

Deliverable:
1. Component table (cluster, Postgres, DCS, backup, monitoring).
2. Sync vs async decision with explicit RPO.
3. Fencing / leader-election explanation.
4. Repo layout.
5. Acceptance tests as Makefile targets.
6. Known limitations list.

Do not write full manifests yet.
