# Runbook

## Bring up / tear down

```bash
make up      # or: ./scripts/up.sh   /  .\scripts\up.ps1
make down    # or: ./scripts/down.sh
make status
```

## Planned switchover

```bash
# Pick a healthy replica, then:
PRIMARY=$(kubectl -n postgres-ha get pods -l role=primary -o jsonpath='{.items[0].metadata.name}')
kubectl -n postgres-ha exec -it "$PRIMARY" -c postgres -- patronictl list
kubectl -n postgres-ha exec -it "$PRIMARY" -c postgres -- \
  patronictl switchover --candidate postgres-ha-1 --force
```

Clients keep using `postgres-ha.postgres-ha.svc.cluster.local`.

## Unplanned failover (test)

```bash
make failover-test
```

Script deletes the current primary, waits until another member accepts writes, prints `RTO_SECONDS`, and waits for the old primary to show `role=replica`.

## Minor-version upgrade

1. Bump Postgres tag in `docker/Dockerfile` / `VERSIONS.md` (e.g. 16.6 → 16.8).
2. `docker build -t postgres-patroni:16 ...` and `kind load docker-image ...`.
3. Rolling restart: `kubectl -n postgres-ha delete pod postgres-ha-2` (replica first), wait Ready, then switchover, then recycle former primary.
4. Prefer Patroni rolling update docs for production; this DIY image has no operator upgrade CRD.

## Backup now

```bash
make backup
```

## Restore whole cluster to empty namespace (PITR)

```bash
# Latest
make restore-test

# Point-in-time (do not take a newer backup after choosing the timestamp)
TARGET_TIME='2026-11-23 16:40:00+00' make restore-test
```

The Job runs in `pg-restore-test`, fetches base backup + WAL from MinIO, starts Postgres temporarily, and checks `ha_smoke` if present. Scripts copy MinIO credentials from the live primary’s WAL-G environment so the scratch restore uses the same keys as ongoing backups.

To rebuild the live cluster from backup (disaster recovery):

1. `make down` (or delete `postgres-ha` namespace).
2. Ensure MinIO data still holds backups (use external S3 in production).
3. Bootstrap a single Patroni member with `wal-g backup-fetch` into `PGDATA`, configure `restore_command`, promote, then scale replicas (advanced; the automated proof path is the scratch Job above).

## Inspect lag

```bash
make lag
```

## Prometheus

```bash
kubectl -n postgres-ha port-forward svc/prometheus 9090:9090
# open http://127.0.0.1:9090
```
