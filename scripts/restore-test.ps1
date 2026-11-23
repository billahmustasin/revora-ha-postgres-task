# Automated restore proof: base backup → Job in pg-restore-test → verify.
# Usage:
#   .\scripts\restore-test.ps1
# Optional PITR (timestamp must be AFTER an existing base backup, covered by archived WAL):
#   .\scripts\backup-now.ps1
#   # wait, then pick UTC after that backup's modified time
#   $env:TARGET_TIME = '2026-11-23 16:40:00+00'
#   .\scripts\restore-test.ps1
#   Remove-Item Env:TARGET_TIME
$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Image = "postgres-patroni:16"
$ClusterName = "postgres-ha"
$Ns = "postgres-ha"
$RestoreNs = "pg-restore-test"
$TargetTime = if ($env:TARGET_TIME) { $env:TARGET_TIME.Trim() } else { "" }
if ($TargetTime) {
  Write-Host "==> PITR TARGET_TIME=$TargetTime"
} else {
  Write-Host "==> No TARGET_TIME set (recover to end of WAL / LATEST)"
}

if ($TargetTime) {
  Write-Host "==> PITR: using existing backups (not taking a newer base backup)"
  Write-Host "    TARGET_TIME must be after the latest base backup and within archived WAL"
} else {
  Write-Host "==> Ensuring a base backup exists"
  & "$Root\scripts\backup-now.ps1"
}

Write-Host "==> Preparing $RestoreNs namespace + MinIO credentials"
kubectl apply -f "$Root\k8s\namespace.yaml" | Out-Null

# Use the same credentials the live primary uses for WAL-G (not a freshly regenerated .env).
$primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}'
if (-not $primary) { throw "No primary pod found" }
$accessKey = (kubectl -n $Ns exec $primary -c postgres -- printenv AWS_ACCESS_KEY_ID).Trim()
$secretKey = (kubectl -n $Ns exec $primary -c postgres -- printenv AWS_SECRET_ACCESS_KEY).Trim()
if (-not $accessKey -or -not $secretKey) { throw "Primary is missing AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY" }

kubectl -n $RestoreNs create secret generic minio-credentials `
  --from-literal=accesskey=$accessKey `
  --from-literal=secretkey=$secretKey `
  --dry-run=client -o yaml | kubectl apply -f - | Out-Null

try {
  kind load docker-image $Image --name $ClusterName 2>$null | Out-Null
} catch {
  # Image may already be loaded on the kind nodes.
}

kubectl -n $RestoreNs delete job postgres-pitr-restore --ignore-not-found | Out-Null

# Render TARGET_TIME into the Job manifest (only the TARGET_TIME empty value).
$manifest = Get-Content "$Root\k8s\backup\restore-job.yaml" -Raw
if ($TargetTime) {
  $manifest = $manifest -replace '(?m)(name: TARGET_TIME\r?\n\s+value: )""', ('$1"{0}"' -f $TargetTime)
}
$tmp = Join-Path $env:TEMP ("restore-job-{0}.yaml" -f [guid]::NewGuid().ToString("n"))
[System.IO.File]::WriteAllText($tmp, $manifest)
try {
  kubectl apply -f $tmp
  if ($LASTEXITCODE -ne 0) { throw "kubectl apply failed for restore Job" }

  Write-Host "==> Waiting for restore Job (timeout 5m)"
  kubectl -n $RestoreNs wait --for=condition=complete job/postgres-pitr-restore --timeout=300s
  if ($LASTEXITCODE -ne 0) {
    kubectl -n $RestoreNs logs job/postgres-pitr-restore
    throw "Restore job failed or timed out"
  }
  kubectl -n $RestoreNs logs job/postgres-pitr-restore
  Write-Host "==> Restore test passed"
} finally {
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}
