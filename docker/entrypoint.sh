#!/usr/bin/env bash
set -euo pipefail

SCOPE="${PATRONI_SCOPE:-postgres-ha}"
NAMESPACE="${PATRONI_KUBERNETES_NAMESPACE:-postgres-ha}"
NAME="${PATRONI_NAME:-${HOSTNAME}}"
POD_IP="${POD_IP:-$(hostname -i | awk '{print $1}')}"

: "${SUPERUSER_PASSWORD:?SUPERUSER_PASSWORD is required}"
: "${REPLICATOR_PASSWORD:?REPLICATOR_PASSWORD is required}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required}"

mkdir -p /home/postgres/pgdata /tmp
chmod 700 /home/postgres/pgdata || true

# Render Patroni config from template (no secrets in the image).
sed \
  -e "s|__SCOPE__|${SCOPE}|g" \
  -e "s|__NAME__|${NAME}|g" \
  -e "s|__NAMESPACE__|${NAMESPACE}|g" \
  -e "s|__POD_IP__|${POD_IP}|g" \
  -e "s|__SUPERUSER_PASSWORD__|${SUPERUSER_PASSWORD}|g" \
  -e "s|__REPLICATOR_PASSWORD__|${REPLICATOR_PASSWORD}|g" \
  -e "s|__ADMIN_PASSWORD__|${ADMIN_PASSWORD}|g" \
  /etc/patroni/patroni.yml.tpl > /etc/patroni/patroni.yml

chmod 600 /etc/patroni/patroni.yml

# WAL-G / S3 (MinIO) environment is injected by the StatefulSet.
export PGHOST=/tmp
export WALG_COMPRESSION_METHOD="${WALG_COMPRESSION_METHOD:-lz4}"

exec patroni /etc/patroni/patroni.yml
