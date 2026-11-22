# Windows entry point (PowerShell). Prefer `make up` on Linux/macOS.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Cluster = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "postgres-ha" }
$Image = if ($env:IMAGE) { $env:IMAGE } else { "postgres-patroni:16" }
$Ns = "postgres-ha"
$MinioImage = "cleanstart/minio:latest"

function Log($msg) { Write-Host "==> $msg" }
function Assert-Exit($msg) {
  if ($LASTEXITCODE -ne 0) { throw $msg }
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) { throw "kind not found on PATH" }
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { throw "kubectl not found on PATH" }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker not found on PATH" }

$env:Path = "$env:USERPROFILE\bin;$env:Path"

Log "Creating kind cluster '$Cluster' (idempotent)"
$raw = cmd /c "kind get clusters 2>nul"
$clusters = @()
if ($raw) { $clusters = @($raw -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) }
if ($clusters -notcontains $Cluster) {
  kind create cluster --config "$Root\kind\cluster.yaml" --image kindest/node:v1.32.2
  Assert-Exit "kind create cluster failed"
} else {
  Log "Cluster already exists"
}
kubectl cluster-info --context "kind-$Cluster" | Out-Null

Log "Ensuring images exist locally"
docker image inspect $Image 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  docker build -t $Image -f "$Root\docker\Dockerfile" $Root
  Assert-Exit "docker build failed"
}
docker pull $MinioImage
Assert-Exit "docker pull $MinioImage failed"

Log "Loading images into kind"
kind load docker-image $Image --name $Cluster
kind load docker-image $MinioImage --name $Cluster

Log "Applying manifests and Secrets (from local .env)"
kubectl apply -f "$Root\k8s\namespace.yaml"
& "$Root\scripts\gen-secrets.ps1"
Assert-Exit "gen-secrets failed"
kubectl apply -f "$Root\k8s\postgres\rbac.yaml"
kubectl apply -f "$Root\k8s\postgres\services.yaml"
kubectl apply -f "$Root\k8s\postgres\pdb.yaml"
kubectl apply -f "$Root\k8s\minio\deployment.yaml"

Log "Waiting for MinIO"
kubectl -n $Ns rollout status deployment/minio --timeout=240s
Assert-Exit "MinIO rollout failed"
kubectl -n $Ns delete job minio-create-bucket --ignore-not-found | Out-Null
kubectl apply -f "$Root\k8s\minio\deployment.yaml"
kubectl -n $Ns wait --for=condition=complete job/minio-create-bucket --timeout=240s
Assert-Exit "MinIO bucket job failed"

Log "Deploying Postgres / Patroni + backup + monitoring"
kubectl apply -f "$Root\k8s\postgres\statefulset.yaml"
kubectl apply -f "$Root\k8s\postgres\networkpolicy.yaml"
kubectl apply -f "$Root\k8s\backup\backup-cronjob.yaml"
kubectl apply -f "$Root\k8s\monitoring\prometheus.yaml"

Log "Waiting for pods"
foreach ($i in 0,1,2) {
  kubectl -n $Ns wait --for=condition=Ready "pod/postgres-ha-$i" --timeout=420s
  Assert-Exit "pod postgres-ha-$i not Ready"
}

Log "Waiting for primary endpoint"
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
  $eps = kubectl get endpoints -n $Ns postgres-ha -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
  if ($eps) { $ready = $true; break }
  Start-Sleep -Seconds 5
}
if (-not $ready) { throw "Primary endpoint not ready" }

$primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=primary" -o jsonpath='{.items[0].metadata.name}'
if (-not $primary) {
  $primary = kubectl get pods -n $Ns -l "app=postgres-ha,role=master" -o jsonpath='{.items[0].metadata.name}'
}
if (-not $primary) { throw "No primary pod labeled role=primary/master" }
Log "Seeding smoke table on $primary"
kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -c "CREATE TABLE IF NOT EXISTS ha_smoke (id serial primary key, note text, created_at timestamptz default now());"
kubectl -n $Ns exec $primary -c postgres -- psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('bootstrap');"

kubectl -n $Ns get pods -o wide -L role
kubectl -n $Ns get svc
Write-Host ""
Write-Host "Primary DNS:  postgres-ha.$Ns.svc.cluster.local:5432"
Write-Host "Replica DNS:  postgres-ha-replica.$Ns.svc.cluster.local:5432"
