#!/usr/bin/env bash
# Show streaming replication lag from the primary.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kubectl
PRIMARY="$(primary_pod)"
[[ -n "${PRIMARY}" ]] || die "No primary"

kubectl -n "$NS" exec "$PRIMARY" -c postgres -- psql -h /tmp -U postgres -c "
SELECT
  application_name,
  client_addr,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)     AS sent_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)    AS write_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)    AS flush_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)   AS replay_lag_bytes,
  replay_lag
FROM pg_stat_replication
ORDER BY application_name;
"
