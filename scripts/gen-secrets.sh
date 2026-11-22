#!/usr/bin/env bash
# Create Kubernetes Secrets from a local .env (gitignored).
# If .env is missing: copy .env.example and replace <set-me> with random values.
# Usage: ./scripts/gen-secrets.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${ROOT}/.env"
EXAMPLE="${ROOT}/.env.example"

rand() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '/+=' | head -c 32
  else
    head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | head -c 32
  fi
}

fill_placeholders() {
  local src="$1" dest="$2"
  : > "${dest}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == *"<set-me>"* ]]; then
      # One placeholder per line in .env.example
      printf '%s\n' "${line/<set-me>/$(rand)}" >> "${dest}"
    else
      printf '%s\n' "${line}" >> "${dest}"
    fi
  done < "${src}"
}

if [[ ! -f "${ENV_FILE}" ]]; then
  [[ -f "${EXAMPLE}" ]] || die "Missing ${EXAMPLE}"
  log "No .env found — filling .env.example placeholders into .env (gitignored)"
  fill_placeholders "${EXAMPLE}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}" || true
  log "Wrote ${ENV_FILE}"
fi

if grep -q '<set-me>' "${ENV_FILE}"; then
  die ".env still contains <set-me> — set values or delete .env and re-run"
fi

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

: "${SUPERUSER_PASSWORD:?SUPERUSER_PASSWORD missing in .env}"
: "${REPLICATOR_PASSWORD:?REPLICATOR_PASSWORD missing in .env}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD missing in .env}"
: "${APP_PASSWORD:?APP_PASSWORD missing in .env}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER missing in .env}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD missing in .env}"

need kubectl

kubectl apply -f "${ROOT}/k8s/namespace.yaml" >/dev/null

log "Applying Secrets in postgres-ha (from local .env)"
kubectl -n postgres-ha create secret generic postgres-ha-credentials \
  --from-literal=superuser-password="${SUPERUSER_PASSWORD}" \
  --from-literal=replicator-password="${REPLICATOR_PASSWORD}" \
  --from-literal=admin-password="${ADMIN_PASSWORD}" \
  --from-literal=app-password="${APP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n postgres-ha create secret generic minio-credentials \
  --from-literal=accesskey="${MINIO_ROOT_USER}" \
  --from-literal=secretkey="${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying MinIO credentials in pg-restore-test"
kubectl -n pg-restore-test create secret generic minio-credentials \
  --from-literal=accesskey="${MINIO_ROOT_USER}" \
  --from-literal=secretkey="${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Secrets applied (values stay on this machine / in the cluster only)"
