# Create Kubernetes Secrets from local .env (gitignored).
# If .env is missing: copy .env.example and fill placeholders with random values.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $Root ".env"
$Example = Join-Path $Root ".env.example"
$Placeholder = '<set-me>'

function Log($msg) { Write-Host "==> $msg" }
function New-Rand([int]$Len = 32) {
  $bytes = New-Object byte[] $Len
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $s = [Convert]::ToBase64String($bytes) -replace '[/+=]', ''
  return $s.Substring(0, [Math]::Min($Len, $s.Length))
}

if (-not (Test-Path $EnvFile)) {
  if (-not (Test-Path $Example)) { throw "Missing $Example" }
  Log "No .env found - filling .env.example placeholders into .env (gitignored)"
  $lines = Get-Content $Example | ForEach-Object {
    if ($_ -like ('*{0}*' -f $Placeholder)) {
      $_ -replace [regex]::Escape($Placeholder), (New-Rand 32)
    } else {
      $_
    }
  }
  Set-Content -Path $EnvFile -Value $lines -Encoding utf8
  Log "Wrote $EnvFile"
}

if (Select-String -Path $EnvFile -SimpleMatch -Pattern $Placeholder -Quiet) {
  throw ('.env still contains {0} - set values or delete .env and re-run' -f $Placeholder)
}

Get-Content $EnvFile | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith("#")) { return }
  $i = $line.IndexOf("=")
  if ($i -lt 1) { return }
  $name = $line.Substring(0, $i).Trim()
  $value = $line.Substring($i + 1).Trim()
  Set-Item -Path "Env:$name" -Value $value
}

foreach ($req in @(
  "SUPERUSER_PASSWORD", "REPLICATOR_PASSWORD", "ADMIN_PASSWORD", "APP_PASSWORD",
  "MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD"
)) {
  if (-not [string]::IsNullOrWhiteSpace((Get-Item "Env:$req" -ErrorAction SilentlyContinue).Value)) { continue }
  throw "$req missing in .env"
}

kubectl apply -f "$Root\k8s\namespace.yaml" | Out-Null

Log "Applying Secrets in postgres-ha (from local .env)"
kubectl -n postgres-ha create secret generic postgres-ha-credentials `
  --from-literal=superuser-password=$env:SUPERUSER_PASSWORD `
  --from-literal=replicator-password=$env:REPLICATOR_PASSWORD `
  --from-literal=admin-password=$env:ADMIN_PASSWORD `
  --from-literal=app-password=$env:APP_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n postgres-ha create secret generic minio-credentials `
  --from-literal=accesskey=$env:MINIO_ROOT_USER `
  --from-literal=secretkey=$env:MINIO_ROOT_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

Log "Applying MinIO credentials in pg-restore-test"
kubectl -n pg-restore-test create secret generic minio-credentials `
  --from-literal=accesskey=$env:MINIO_ROOT_USER `
  --from-literal=secretkey=$env:MINIO_ROOT_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

Log "Secrets applied (values stay on this machine / in the cluster only)"
