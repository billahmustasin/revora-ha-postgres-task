#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kind

log "Deleting namespaces (clean app teardown)"
kubectl delete namespace postgres-ha pg-restore-test --ignore-not-found --wait=false 2>/dev/null || true

log "Deleting kind cluster '${CLUSTER_NAME}'"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  log "Cluster not found — nothing to do"
fi
log "Down complete"
