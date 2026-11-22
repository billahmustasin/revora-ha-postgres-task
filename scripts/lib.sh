#!/usr/bin/env bash
# Shared helpers for operational scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-postgres-ha}"
NS="${NS:-postgres-ha}"
IMAGE="${IMAGE:-postgres-patroni:16}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

wait_for_primary() {
  local tries="${1:-60}"
  local i
  for i in $(seq 1 "$tries"); do
    if kubectl get endpoints -n "$NS" postgres-ha -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -qE '[0-9]'; then
      return 0
    fi
    sleep 5
  done
  return 1
}

primary_pod() {
  kubectl get pods -n "$NS" -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null \
    || kubectl get pods -n "$NS" -l "app=postgres-ha,role=master" -o jsonpath='{.items[0].metadata.name}'
}

# Postgres listens on unix socket under /tmp in our Patroni config.
psql_primary() {
  local pod
  pod="$(primary_pod)"
  kubectl -n "$NS" exec "$pod" -c postgres -- psql -h /tmp -U postgres "$@"
}
