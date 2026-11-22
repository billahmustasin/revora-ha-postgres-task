#!/usr/bin/env bash
# Kill the current primary (block reschedule) and measure RTO until another member writes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kubectl

clear_block() {
  kubectl -n "$NS" patch statefulset postgres-ha --type=json \
    --patch-file "${SCRIPT_DIR}/failover-clear-patch.json" >/dev/null 2>&1 || true
}

PRIMARY="$(primary_pod)"
[[ -n "${PRIMARY}" ]] || die "No primary pod found"
log "Current primary: ${PRIMARY}"

kubectl -n "$NS" exec "$PRIMARY" -c postgres -- \
  psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('pre-failover');" >/dev/null

log "Patching StatefulSet with blocking nodeSelector"
kubectl -n "$NS" patch statefulset postgres-ha --type=merge \
  --patch-file "${SCRIPT_DIR}/failover-block-patch.json" >/dev/null

START_EPOCH="$(date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "Deleting primary pod at ${START_ISO}"
kubectl -n "$NS" delete pod "$PRIMARY" --grace-period=0 --force >/dev/null 2>&1 || true

NEW_PRIMARY=""
trap clear_block EXIT
for i in $(seq 1 90); do
  CAND="$(primary_pod || true)"
  if [[ -n "${CAND}" && "${CAND}" != "${PRIMARY}" ]]; then
    if kubectl -n "$NS" exec "$CAND" -c postgres -- \
      psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('post-failover');" >/dev/null 2>&1; then
      NEW_PRIMARY="$CAND"
      break
    fi
  fi
  sleep 2
done

clear_block
trap - EXIT

END_EPOCH="$(date +%s)"
END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RTO=$((END_EPOCH - START_EPOCH))

[[ -n "${NEW_PRIMARY}" ]] || die "Failover did not promote another member within timeout"

log "New primary: ${NEW_PRIMARY}"
log "RTO: ${RTO}s (from ${START_ISO} to ${END_ISO})"
echo "RTO_SECONDS=${RTO}"

log "Waiting for former primary to rejoin as replica"
for i in $(seq 1 90); do
  ROLE="$(kubectl -n "$NS" get pod "$PRIMARY" -o jsonpath='{.metadata.labels.role}' 2>/dev/null || true)"
  READY="$(kubectl -n "$NS" get pod "$PRIMARY" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
  if [[ "${ROLE}" == "replica" && "${READY}" == "true" ]]; then
    log "${PRIMARY} rejoined as replica"
    kubectl -n "$NS" get pods -l app=postgres-ha -L role
    exit 0
  fi
  sleep 5
done

log "Warning: ${PRIMARY} did not show role=replica yet"
kubectl -n "$NS" get pods -l app=postgres-ha -L role
exit 0
