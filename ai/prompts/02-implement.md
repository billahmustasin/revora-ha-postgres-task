# Prompt: Implement phase

Implement the approved design for PostgreSQL HA on kind.

Requirements:
- Image: Postgres 16 + Patroni + WAL-G (Dockerfile).
- For Kubernetes DCS: top-level Patroni `namespace` must be the K8s namespace **without** leading/trailing slashes.
- StatefulSet of 3, Services for primary (`role=master`) and replica (`role=replica`).
- MinIO in-cluster; WAL-G archive_command; CronJob base backup + retention.
- Restore Job in `pg-restore-test` namespace with optional TARGET_TIME.
- NetworkPolicy (ingress), PDB, Secrets, postgres_exporter + Prometheus alerts.
- Scripts: up, down, failover-test (print RTO), restore-test, lag.
- Makefile targets matching README acceptance checklist.

Do not use forbidden operators. Pin versions. No real production credentials.
