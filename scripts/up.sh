#!/usr/bin/env bash
# Single entry point: create kind cluster, build image, deploy stack, wait healthy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need kind
need kubectl
need docker

log "Creating kind cluster '${CLUSTER_NAME}' (idempotent)"
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --config "${ROOT}/kind/cluster.yaml" --image kindest/node:v1.32.2
else
  log "Cluster already exists"
fi
kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null

log "Building ${IMAGE}"
docker build -t "${IMAGE}" -f "${ROOT}/docker/Dockerfile" "${ROOT}"

log "Pulling MinIO image"
docker pull cleanstart/minio:latest

log "Loading images into kind"
kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
kind load docker-image cleanstart/minio:latest --name "${CLUSTER_NAME}"

log "Applying namespaces and Secrets (from local .env)"
kubectl apply -f "${ROOT}/k8s/namespace.yaml"
"${SCRIPT_DIR}/gen-secrets.sh"
kubectl apply -f "${ROOT}/k8s/postgres/rbac.yaml"
kubectl apply -f "${ROOT}/k8s/postgres/services.yaml"
kubectl apply -f "${ROOT}/k8s/postgres/pdb.yaml"
kubectl apply -f "${ROOT}/k8s/minio/deployment.yaml"

log "Waiting for MinIO"
kubectl -n "$NS" rollout status deployment/minio --timeout=180s
kubectl -n "$NS" wait --for=condition=complete job/minio-create-bucket --timeout=180s || \
  kubectl -n "$NS" delete job minio-create-bucket --ignore-not-found && \
  kubectl apply -f "${ROOT}/k8s/minio/deployment.yaml" && \
  kubectl -n "$NS" wait --for=condition=complete job/minio-create-bucket --timeout=180s

log "Deploying Postgres / Patroni"
kubectl apply -f "${ROOT}/k8s/postgres/statefulset.yaml"
kubectl apply -f "${ROOT}/k8s/postgres/networkpolicy.yaml"
kubectl apply -f "${ROOT}/k8s/backup/backup-cronjob.yaml"
kubectl apply -f "${ROOT}/k8s/monitoring/prometheus.yaml"

log "Waiting for StatefulSet pods"
kubectl -n "$NS" rollout status statefulset/postgres-ha --timeout=300s || true
for i in 0 1 2; do
  kubectl -n "$NS" wait --for=condition=Ready "pod/postgres-ha-${i}" --timeout=300s
done

log "Waiting for Patroni primary endpoint"
wait_for_primary 60 || die "Primary endpoint not ready"

log "Seeding smoke table"
PRIMARY="$(primary_pod)"
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- \
  psql -h /tmp -U postgres -c "CREATE TABLE IF NOT EXISTS ha_smoke (id serial primary key, note text, created_at timestamptz default now());"
kubectl -n "$NS" exec "$PRIMARY" -c postgres -- \
  psql -h /tmp -U postgres -c "INSERT INTO ha_smoke(note) VALUES ('bootstrap');"

log "Cluster is up"
kubectl -n "$NS" get pods -o wide
kubectl -n "$NS" get svc
echo
echo "Primary DNS:  postgres-ha.${NS}.svc.cluster.local:5432"
echo "Replica DNS:  postgres-ha-replica.${NS}.svc.cluster.local:5432"
echo "Prometheus:   kubectl -n ${NS} port-forward svc/prometheus 9090:9090"
