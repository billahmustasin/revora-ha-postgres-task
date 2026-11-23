# Tear down app namespaces and the kind cluster (Windows entry point).
$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
$ClusterName = "postgres-ha"

Write-Host "==> Deleting namespaces (clean app teardown)"
kubectl delete namespace postgres-ha pg-restore-test --ignore-not-found --wait=false 2>$null | Out-Null

Write-Host "==> Deleting kind cluster '$ClusterName'"
$clusters = kind get clusters 2>$null
if ($clusters -split "`r?`n" | Where-Object { $_.Trim() -eq $ClusterName }) {
  kind delete cluster --name $ClusterName
} else {
  Write-Host "==> Cluster not found — nothing to do"
}
Write-Host "==> Down complete"
