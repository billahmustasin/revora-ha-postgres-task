#!/usr/bin/env bash
# Automated restore proof: base backup → Job in pg-restore-test → verify.
# Optional PITR: TARGET_TIME='2026-11-20 12:00:00+00' make restore-test
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kubectl
TARGET_TIME="${TARGET_TIME:-}"

log "Ensuring a base backup exists"
"${SCRIPT_DIR}/backup-now.sh"

log "Preparing pg-restore-test namespace + MinIO credentials"
kubectl apply -f "${ROOT}/k8s/namespace.yaml"

# Use the same credentials the live primary uses for WAL-G (not a freshly regenerated .env).
PRIMARY="$(kubectl get pods -n "${NS}" -l app=postgres-ha,role=primary -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${PRIMARY}" ]] || die "No primary pod found"
ACCESS_KEY="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- printenv AWS_ACCESS_KEY_ID | tr -d '\r')"
SECRET_KEY="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- printenv AWS_SECRET_ACCESS_KEY | tr -d '\r')"
[[ -n "${ACCESS_KEY}" && -n "${SECRET_KEY}" ]] || die "Primary is missing AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY"

kubectl -n pg-restore-test create secret generic minio-credentials \
  --from-literal=accesskey="${ACCESS_KEY}" \
  --from-literal=secretkey="${SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}" 2>/dev/null || true

kubectl -n pg-restore-test delete job postgres-pitr-restore --ignore-not-found
# Render TARGET_TIME into the Job manifest
TMP="$(mktemp)"
sed "s|value: \"\"|value: \"${TARGET_TIME}\"|" "${ROOT}/k8s/backup/restore-job.yaml" > "${TMP}"
kubectl apply -f "${TMP}"
rm -f "${TMP}"

log "Waiting for restore Job (timeout 5m)"
kubectl -n pg-restore-test wait --for=condition=complete job/postgres-pitr-restore --timeout=300s
kubectl -n pg-restore-test logs job/postgres-pitr-restore
log "Restore test passed"
