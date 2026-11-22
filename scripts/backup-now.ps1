$ErrorActionPreference = "Continue"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Ns = "postgres-ha"
$primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}'
if (-not $primary) { throw "No primary" }
Write-Host "==> Base backup via $primary"
kubectl -n $Ns exec $primary -c postgres -- wal-g backup-push /home/postgres/pgdata/data
kubectl -n $Ns exec $primary -c postgres -- wal-g delete retain FULL 7 --confirm 2>$null
kubectl -n $Ns exec $primary -c postgres -- wal-g backup-list
Write-Host "==> Backup complete"
