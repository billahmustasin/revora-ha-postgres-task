# PostgreSQL HA on Kubernetes (no operator)

Highly available PostgreSQL 16 on a local **kind** cluster using **Patroni** (Kubernetes DCS), streaming replication, **WAL-G → MinIO** backups with PITR, and Prometheus metrics.

Forbidden operators/charts are **not** used. Patroni is deployed and wired by hand (allowed by the assignment FAQ).

## Prerequisites

Install these on the machine where you will run the stack (Linux, macOS, or Windows):

| Tool | Why | Notes |
|------|-----|--------|
| **Docker** | Builds the Postgres/Patroni image; runs kind nodes | Docker Desktop on Windows/macOS; Engine on Linux. Must be running before `make up`. |
| **kind** ≥ 0.27 | Local multi-node Kubernetes | [Install kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **kubectl** | Talk to the cluster | Client ≥ 1.28 recommended; [install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| **Git** | Clone this repository | — |
| **make** + **bash** | Linux/macOS entry points | Windows: use PowerShell scripts below (make optional) |
| **Network** | Pull base images on first build | `postgres:16.6`, `cleanstart/minio`, Prometheus, exporter |

Optional: `openssl` (used by `gen-secrets.sh` for random passwords; falls back to `/dev/urandom`).

Verify tools:

```bash
docker version
kind version
kubectl version --client
```

## Clone and set up

**No real credentials are in git.** `.env.example` only has keys with `<set-me>`. The first bring-up fills a local gitignored `.env` with random values and creates Kubernetes Secrets in the cluster.

### 1. Clone

```bash
git clone <YOUR_REPO_URL>
cd revora-ha-postgres-task
```

### 2. Bring the stack up

**Linux / macOS** (or Git Bash):

```bash
make up
```

This will:

1. Create a 3-node kind cluster named `postgres-ha` (if missing)
2. Build `postgres-patroni:16` and load it into kind
3. Pull/load MinIO, generate Secrets from `.env.example` → `.env`
4. Deploy Postgres (Patroni), MinIO, backup CronJobs, Prometheus
5. Wait until 1 primary + 2 replicas are Ready and seed a smoke table

**Windows (PowerShell)** — Docker Desktop must be running; put `kind` and `kubectl` on `PATH`:

```powershell
.\scripts\up.ps1
```

First run can take **10–20 minutes** (image builds + pulls).

### 3. Check health

```bash
make status
make lag
```

Windows:

```powershell
kubectl -n postgres-ha get pods -o wide -L role
.\scripts\lag.ps1
```

You should see one pod with `role=primary` and two with `role=replica`.

### 4. Run the verification targets

```bash
make failover-test    # kill primary, print RTO, wait for rejoin
make backup           # WAL-G base backup to MinIO
make restore-test     # restore into pg-restore-test namespace
# Optional PITR:
TARGET_TIME='2026-11-21 12:00:00+00' make restore-test
```

Windows equivalents: `.\scripts\up.ps1`, `.\scripts\down.ps1`, `.\scripts\failover-test.ps1`, `.\scripts\backup-now.ps1`, `.\scripts\restore-test.ps1`, `.\scripts\lag.ps1`.

### 5. Tear down

```bash
make down
```

Windows:

```powershell
.\scripts\down.ps1
```

Deletes the app namespaces and the kind cluster.

### Secrets note

- Do **not** commit `.env` (it is gitignored).
- To rotate passwords: delete `.env`, then `make secrets` or re-run `make up`.
- Shape of Secrets (no values): `k8s/postgres/secret.example.yaml`.

## Architecture

| Layer | Choice |
|-------|--------|
| Cluster | kind, 3 nodes (simulated zones) |
| Postgres | 16.6 + Patroni 4.0.4 in one image |
| DCS | Kubernetes API (ConfigMaps) + pod `role=primary\|replica` labels |
| Replication | Async streaming + slots + `max_slot_wal_keep_size=1GB` |
| Endpoints | `postgres-ha` (primary), `postgres-ha-replica` (replicas) |
| Backups | WAL-G continuous WAL + CronJob base backups → MinIO |
| Verify | Job in `pg-restore-test` namespace |
| Observability | postgres_exporter + Prometheus alert rules |

See [docs/DESIGN.md](docs/DESIGN.md) for sync/async, fencing, and RPO/RTO.

## Client connectivity

| Purpose | DNS |
|---------|-----|
| Writes (primary) | `postgres-ha.postgres-ha.svc.cluster.local:5432` |
| Reads (replicas) | `postgres-ha-replica.postgres-ha.svc.cluster.local:5432` |

After failover, Patroni retargets the `role=primary` label; clients reconnect to the **same** Service DNS (retry/reconnect required at the app layer).

**Secrets:** none committed. `gen-secrets` generates a local `.env` (gitignored) with random values and applies them to the cluster. Never commit `.env` or live Secret YAML.

## Measured behaviour (fill after your run)

| Metric | Value | How |
|--------|-------|-----|
| RPO | Async: unreplicated WAL (observed 0 bytes lag at idle) | `make lag` / `pg_stat_replication` |
| RTO | **22s** (measured 2026-11-21) | `make failover-test` / `scripts/failover-test.ps1` — delete primary → other member accepts `INSERT` |

## Operability

- Planned switchover and minor upgrade: [docs/RUNBOOK.md](docs/RUNBOOK.md)
- AI process / repeatability: [docs/AI_PROCESS.md](docs/AI_PROCESS.md)
- Pinned versions: [VERSIONS.md](VERSIONS.md)

## Acceptance checklist

- [x] `make up` / `.\scripts\up.ps1` → 1 primary + 2 replicas Ready
- [x] Lag query shows two streaming replicas (0 bytes at idle)
- [x] Failover test promotes automatically (RTO 22s); old primary rejoins as replica
- [x] Primary/replica Service DNS unchanged across failover
- [x] WAL-G base backup listed in MinIO
- [x] Restore Job completes with `RESTORE TEST PASSED` (`ha_smoke` rows verified)
- [ ] Optional: `TARGET_TIME=... make restore-test` for PITR demo in video

## Known limitations

- kind is single-machine; zone labels are simulated. Real multi-zone needs topology-aware StorageClasses and true zone spread.
- NetworkPolicy restricts **ingress** only; egress left open so Patroni can reach the API server without brittle CIDRs.
- Postgres TLS / cert-manager not enabled (passwords via generated Secrets only).
- PgBouncer omitted (optional in the brief).
- Grafana omitted; Prometheus + alert rules are enough for the scope.
- MinIO image: `cleanstart/minio` (Docker Hub `minio/minio` was not pullable in some environments).

## Repository layout

```
Makefile, README.md, VERSIONS.md
kind/ cluster.yaml
docker/ Dockerfile, entrypoint.sh, patroni.yml.tpl
k8s/ namespace, postgres, minio, backup, monitoring
scripts/ up, down, failover-test, restore-test, backup-now, lag
docs/ DESIGN, RUNBOOK, AI_PROCESS
ai/ prompts/, sessions/
```
