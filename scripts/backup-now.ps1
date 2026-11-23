$ErrorActionPreference = "Continue"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Ns = "postgres-ha"
$primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}'
if (-not $primary) { throw "No primary" }
Write-Host "==> Base backup via $primary"
kubectl -n $Ns exec $primary -c postgres -- wal-g backup-push /home/postgres/pgdata/data
if ($LASTEXITCODE -ne 0) { throw "wal-g backup-push failed" }

# Ensure the backup's stop-WAL is archived before any restore uses LATEST.
Write-Host "==> Switching WAL and waiting for archive"
kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -c "SELECT pg_switch_wal();" | Out-Null
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
  $row = kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -tAc "SELECT archived_count, last_archived_wal FROM pg_stat_archiver;"
  if ($LASTEXITCODE -eq 0 -and $row -match '\S') {
    Write-Host "    pg_stat_archiver: $($row.Trim())"
    if ($row -match '[0-9A-F]{24}') { $ok = $true; break }
  }
  Start-Sleep 2
}
if (-not $ok) { Write-Host "WARNING: could not confirm WAL archive yet; restore may need a moment" }

kubectl -n $Ns exec $primary -c postgres -- wal-g delete retain FULL 7 --confirm 2>$null | Out-Null
kubectl -n $Ns exec $primary -c postgres -- wal-g backup-list
Write-Host "==> Backup complete"
