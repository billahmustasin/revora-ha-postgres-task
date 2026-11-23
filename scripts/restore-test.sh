#!/usr/bin/env bash
# Automated restore proof: base backup → Job in pg-restore-test → verify.
# Optional PITR: take a backup first, then
# TARGET_TIME='2026-11-23 16:40:00+00' make restore-test
# TARGET_TIME must be after that backup and within archived WAL.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kubectl
TARGET_TIME="${TARGET_TIME:-}"

if [[ -n "${TARGET_TIME}" ]]; then
  log "PITR: using existing backups (not taking a newer base backup)"
  log "TARGET_TIME must be after the latest base backup and within archived WAL"
else
  log "Ensuring a base backup exists"
  "${SCRIPT_DIR}/backup-now.sh"
fi

log "Preparing pg-restore-test namespace + MinIO credentials"
kubectl apply -f "${ROOT}/k8s/namespace.yaml"

# Use the same credentials the live primary uses for WAL-G (not a freshly regenerated .env).
PRIMARY="$(kubectl get pods -n "${NS}" -l app=postgres-ha,role=primary -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${PRIMARY}" ]] || die "No primary pod found"

if [[ -n "${TARGET_TIME}" ]]; then
  if [[ ! "${TARGET_TIME}" =~ (Z|[+-][0-9]{2}) ]]; then
    TARGET_TIME="${TARGET_TIME}+00"
    log "No timezone on TARGET_TIME; assuming UTC (${TARGET_TIME})"
  fi
  log "Committing WAL until an archived transaction is at or after TARGET_TIME"
  reached=0
  commit_at=""
  for _ in $(seq 1 15); do
    commit_at="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- psql -q -h /tmp -U postgres -tAc "INSERT INTO ha_smoke(note) VALUES ('pitr-wal') RETURNING created_at::text;" | tr -d '\r')"
    wal_file="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- psql -h /tmp -U postgres -tAc "SELECT pg_walfile_name(pg_switch_wal() - 1);" | tr -d '\r')"
    archived_wal=""
    for _j in $(seq 1 15); do
      sleep 2
      archived_wal="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- psql -h /tmp -U postgres -tAc "SELECT COALESCE(last_archived_wal,'') FROM pg_stat_archiver;" | tr -d '\r')"
      [[ -n "${archived_wal}" && "${archived_wal}" > "${wal_file}" || "${archived_wal}" == "${wal_file}" ]] && break
    done
    ok="$(kubectl -n "${NS}" exec "${PRIMARY}" -c postgres -- psql -h /tmp -U postgres -tAc "SELECT (timestamptz '${commit_at}' >= timestamptz '${TARGET_TIME}');" | tr -d '\r')"
    log "commit=${commit_at} wal=${wal_file} archived=${archived_wal} reached=${ok}"
    if [[ ( "${archived_wal}" > "${wal_file}" || "${archived_wal}" == "${wal_file}" ) && "${ok}" == "t" ]]; then
      reached=1
      break
    fi
  done
  [[ "${reached}" -eq 1 ]] || die "Could not archive a transaction at or after TARGET_TIME=${TARGET_TIME} (last commit=${commit_at}). Use a UTC time after the latest base backup and not in the future."
fi

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
kubectl -n pg-restore-test logs job/postgres-pitr-restore | tee /tmp/restore-test.log
grep -q "RESTORE TEST PASSED" /tmp/restore-test.log
log "Restore test passed"
