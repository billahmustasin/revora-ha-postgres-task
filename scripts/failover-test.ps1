# Unplanned failover RTO test.
# Blocks StatefulSet reschedule of the killed primary until another member promotes.
$ErrorActionPreference = "Continue"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$Ns = "postgres-ha"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$BlockPatch = Join-Path $Root "scripts\failover-block-patch.json"

function PrimaryPod {
  $json = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o json 2>$null
  if (-not $json) { return $null }
  $items = ($json | ConvertFrom-Json).items
  if ($items -and $items.Count -gt 0) { return $items[0].metadata.name }
  return $null
}

function ClearBlock {
  $clear = Join-Path $Root "scripts\failover-clear-patch.json"
  kubectl -n $Ns patch statefulset postgres-ha --type=json --patch-file $clear 2>$null | Out-Null
}

$primary = PrimaryPod
if (-not $primary) { throw "No primary" }
Write-Host "==> Current primary: $primary"
kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('pre-failover');" | Out-Null

Write-Host "==> Patching StatefulSet with blocking nodeSelector"
kubectl -n $Ns patch statefulset postgres-ha --type=merge --patch-file $BlockPatch
if ($LASTEXITCODE -ne 0) { throw "Failed to apply blocking patch" }

$start = Get-Date
$startIso = $start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "==> Deleting primary pod at $startIso"
kubectl -n $Ns delete pod $primary --grace-period=0 --force 2>$null | Out-Null

$newPrimary = $null
try {
  for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    $cand = PrimaryPod
    if (-not $cand) { continue }
    if ($cand -eq $primary) { continue }
    kubectl -n $Ns exec $cand -c postgres -- psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('post-failover');" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $newPrimary = $cand; break }
    Write-Host "  ... waiting ($i) cand=$cand"
  }
} finally {
  Write-Host "==> Clearing scheduling block so old primary can rejoin"
  ClearBlock
}

$end = Get-Date
$rto = [int]($end - $start).TotalSeconds
if (-not $newPrimary) {
  kubectl -n $Ns get pods -l app=postgres-ha -L role
  throw "Failover did not promote another member within timeout"
}

Write-Host "==> New primary: $newPrimary"
Write-Host "==> RTO: ${rto}s (from delete to writable new primary)"
Write-Host "RTO_SECONDS=$rto"

Write-Host "==> Waiting for former primary pod to rejoin as replica"
for ($i = 0; $i -lt 90; $i++) {
  $role = kubectl -n $Ns get pod $primary -o jsonpath='{.metadata.labels.role}' 2>$null
  $ready = kubectl -n $Ns get pod $primary -o jsonpath='{.status.containerStatuses[0].ready}' 2>$null
  if ($role -eq "replica" -and $ready -eq "true") {
    Write-Host "==> $primary rejoined as replica"
    break
  }
  Start-Sleep -Seconds 5
}
kubectl -n $Ns get pods -l app=postgres-ha -L role
