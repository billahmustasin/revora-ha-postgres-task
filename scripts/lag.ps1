# Show streaming replication lag from the primary (Windows entry point).
# Usage: .\scripts\lag.ps1
$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Ns = "postgres-ha"

$json = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o json 2>$null
if (-not $json) { throw "Failed to list pods in $Ns" }
$items = ($json | ConvertFrom-Json).items
if (-not $items -or $items.Count -eq 0) { throw "No primary pod found (label role=primary)" }
$primary = $items[0].metadata.name

Write-Host "==> Replication lag from primary: $primary"
kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -c @"
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
"@
