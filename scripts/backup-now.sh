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

# Ensure the backup's stop-WAL is archived before any restore uses LATEST.
log "Switching WAL and waiting for archive"
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- psql -h /tmp -U postgres -c "SELECT pg_switch_wal();" >/dev/null
ok=0
for _ in $(seq 1 30); do
  row="$(kubectl -n "$NS" exec "$PRIMARY" -c postgres -- psql -h /tmp -U postgres -tAc "SELECT archived_count, last_archived_wal FROM pg_stat_archiver;" | tr -d '\r')"
  if [[ "${row}" =~ [0-9A-Fa-f]{24} ]]; then
    log "pg_stat_archiver: ${row}"
    ok=1
    break
  fi
  sleep 2
done
[[ "${ok}" -eq 1 ]] || log "WARNING: could not confirm WAL archive yet; restore may need a moment"

kubectl -n "$NS" exec "$PRIMARY" -c postgres -- wal-g delete retain FULL 7 --confirm || true
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- wal-g backup-list
log "Backup complete"
