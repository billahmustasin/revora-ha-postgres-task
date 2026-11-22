# Pinned versions

| Component | Version | Notes |
|-----------|---------|-------|
| kind | 0.27.0 | Local multi-node Kubernetes |
| Kubernetes (kind node image) | v1.32.2 | `kindest/node:v1.32.2` |
| PostgreSQL | 16.6 | Official Debian image base |
| Patroni | 4.0.4 | `pip install patroni[kubernetes]==4.0.4` |
| WAL-G | v3.0.5 | Linux amd64 binary |
| MinIO | cleanstart/minio:latest | In-cluster S3 (Docker Hub mirror of MinIO) |
| postgres_exporter | v0.16.0 | Prometheus metrics |
| Prometheus | v2.55.1 | Scraping + alert rules |

Change these in one place (`VERSIONS.md`, `docker/Dockerfile`, manifests) before regenerating the cluster.
