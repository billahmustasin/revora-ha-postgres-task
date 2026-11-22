#!/usr/bin/env bash
# Trigger an immediate base backup on the primary (also used before restore-test).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kubectl

PRIMARY="$(primary_pod)"
[[ -n "${PRIMARY}" ]] || die "No primary pod found"
log "Base backup via ${PRIMARY}"
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- wal-g backup-push /home/postgres/pgdata/data
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- wal-g delete retain FULL 7 --confirm || true
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- wal-g backup-list
log "Backup complete"
