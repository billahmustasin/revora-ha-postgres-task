# Design

## Goals

Meet the take-home requirements with a system small enough to explain line-by-line: Patroni HA Postgres on Kubernetes, no database operator, automated backups/PITR, evidence for failover and restore.

## Replication: async vs sync

**Choice: asynchronous** streaming replication with replication slots.

| | Async (chosen) | Synchronous |
|--|----------------|-------------|
| RPO | Last unreplicated WAL (seconds under load) | Can be 0 to the sync standby |
| Latency | Primary commits without waiting for replica flush | Higher commit latency; stalls if sync standby dies |
| Local demo | Predictable on kind | Easy to wedge a 3-pod laptop cluster |

**RPO statement:** under normal load, RPO is the replication lag reported by `pg_stat_replication` / `make lag` (bytes + `replay_lag`). We cap runaway slot retention with `max_slot_wal_keep_size=1GB` so a stuck replica cannot fill the primary disk forever.

Slots (`use_slots: true`) keep replicas from permanently falling behind across short outages.

## Leader election and fencing

Patroni uses the **Kubernetes API as DCS** (ConfigMaps when `use_endpoints: false`).

- Only the member holding the leader key updates pod label `role=primary` (Patroni 4.x; older docs used `master`).
- The `postgres-ha` Service selects `role=primary` → at most one write endpoint.
- Replicas are labeled `role=replica` and selected by `postgres-ha-replica`.
- On failover, the old primary is demoted; `use_pg_rewind` (with remove-data-on-rewind-failure) brings it back as a replica, or it reclones if timelines diverge.

**Split-brain prevention:** a pod cannot accept writes as primary without owning the DCS leader lease/key. Kubernetes API consistency + Patroni’s TTL/loop_wait provide the fencing story (not a custom consensus implementation).

## Client connectivity

Stable ClusterIP DNS names; no manual endpoint changes after failover. Connection pooling (PgBouncer) was skipped to keep the attack surface and explanation surface smaller.

## Backups and PITR

- Continuous WAL archive: `archive_command = wal-g wal-push %p` → MinIO (`s3://postgres-backups/pgha`).
- Full base backups: CronJob every 6h (and `make backup`) via `wal-g backup-push` on the primary.
- Retention: `wal-g delete retain FULL 7 --confirm`.
- Restore/PITR: Job in `pg-restore-test` fetches `LATEST`, sets `restore_command`, optional `recovery_target_time`.

## Observability

`postgres_exporter` scrapes the primary Service; Prometheus loads alert rules for scrape failure, high lag, and Patroni member down. Grafana left out intentionally.

## Security (implemented vs deferred)

| Implemented | Deferred / documented |
|-------------|----------------------|
| Random secrets via `gen-secrets` → local `.env` (gitignored) | Postgres TLS / cert-manager |
| NetworkPolicy ingress on Postgres + MinIO | Strict egress allowlists |
| Non-root postgres UID in image | External secret manager / SealedSecrets |
| No credential files committed | Pod Security restricted mode |

## Multi-node / multi-zone notes

kind nodes carry simulated `topology.kubernetes.io/zone` labels. Pod anti-affinity prefers different hosts; topology spread uses `ScheduleAnyway`. On a real multi-zone cluster: use zone-aware volumes, `ScheduleAnyway` → `DoNotSchedule` where capacity allows, and regional object storage instead of in-cluster MinIO.
