# PostgreSQL HA on Kubernetes — single entry points
# Requires: docker, kind, kubectl, bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: up down failover-test restore-test backup lag status secrets help

help:
	@echo "Targets:"
	@echo "  make up             Create kind cluster and deploy the stack"
	@echo "  make secrets        Apply K8s Secrets from local .env (gitignored)"
	@echo "  make down           Tear down namespaces and kind cluster"
	@echo "  make failover-test  Kill primary, measure RTO, wait for rejoin"
	@echo "  make restore-test   Base backup + restore Job (PITR via TARGET_TIME=...)"
	@echo "  make backup         Run an immediate WAL-G base backup"
	@echo "  make lag            Show replication lag from primary"
	@echo "  make status         Pods, services, Patroni roles"

secrets:
	$(ROOT)/scripts/gen-secrets.sh

up:
	$(ROOT)/scripts/up.sh

down:
	$(ROOT)/scripts/down.sh

failover-test:
	$(ROOT)/scripts/failover-test.sh

restore-test:
	$(ROOT)/scripts/restore-test.sh

backup:
	$(ROOT)/scripts/backup-now.sh

lag:
	$(ROOT)/scripts/lag.sh

status:
	kubectl -n postgres-ha get pods -o wide -L role
	kubectl -n postgres-ha get svc,endpoints
	kubectl -n postgres-ha get pdb
