# Windows restore proof (mirrors scripts/restore-test.sh)
$ErrorActionPreference = "Continue"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Ns = "postgres-ha"
$Image = "postgres-patroni:16"
$TargetTime = $env:TARGET_TIME

Write-Host "==> Ensuring a base backup exists"
& "$Root\scripts\backup-now.ps1"
if ($LASTEXITCODE -ne 0) {
  # inline backup if backup-now.ps1 missing
  $primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}'
  kubectl -n $Ns exec $primary -c postgres -- wal-g backup-push /home/postgres/pgdata/data
}

Write-Host "==> Preparing pg-restore-test namespace + Secrets"
kubectl apply -f "$Root\k8s\namespace.yaml"
& "$Root\scripts\gen-secrets.ps1"
kind load docker-image $Image --name postgres-ha 2>$null | Out-Null

kubectl -n pg-restore-test delete job postgres-pitr-restore --ignore-not-found | Out-Null
$manifest = Get-Content "$Root\k8s\backup\restore-job.yaml" -Raw
if ($TargetTime) {
  $manifest = $manifest -replace 'value: ""', "value: `"$TargetTime`""
}
$tmp = Join-Path $env:TEMP "restore-job-rendered.yaml"
Set-Content -Path $tmp -Value $manifest -NoNewline
kubectl apply -f $tmp

Write-Host "==> Waiting for restore Job"
kubectl -n pg-restore-test wait --for=condition=complete job/postgres-pitr-restore --timeout=300s
if ($LASTEXITCODE -ne 0) {
  kubectl -n pg-restore-test logs job/postgres-pitr-restore
  throw "Restore job failed"
}
kubectl -n pg-restore-test logs job/postgres-pitr-restore
Write-Host "==> Restore test passed"
