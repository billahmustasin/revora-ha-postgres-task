# AI-assisted process (repeatability)

This project was built with an AI coding agent (Cursor). The goal is a **repeatable playbook**, not a one-off chat.

## Playbook phases

1. **Spec lock** — acceptance checklist in README; pin versions in `VERSIONS.md`.
2. **Design** — use `ai/prompts/01-design.md` before writing manifests.
3. **Implement** — manifests/scripts against the checklist only.
4. **Verify** — `make failover-test` / `make restore-test` must pass; record RTO.
5. **Document** — DESIGN / RUNBOOK / known limitations (honest gaps).

## Determinism (fixed vs model judgement)

| Fixed | Model judgement |
|-------|-----------------|
| Acceptance tests (`make` targets) | Exact YAML structure |
| Pinned image tags (`VERSIONS.md`) | Probe timings, resource requests |
| Prompt templates in `ai/prompts/` | Wording of docs |
| Forbidden tooling list (no operators) | Choice among allowed tools (Patroni vs repmgr) |

Re-runs should keep the same Makefile contracts and version pins; agents may vary on cosmetic YAML.

## Agent-agnostic method

1. Paste the assignment + `ai/prompts/01-design.md` → produce DESIGN decisions.
2. Paste DESIGN + `ai/prompts/02-implement.md` → generate tree under `k8s/` + `docker/`.
3. Paste `ai/prompts/03-verify.md` → produce/adjust test scripts.
4. Keep raw session logs in `ai/sessions/` (redact secrets only).

Vendor-specific UI steps (Cursor composer, etc.) stay out of the core method.

## Generalisation: HA Redis with Sentinel

| Reuse unchanged | Rewrite |
|-----------------|---------|
| `kind/cluster.yaml`, Makefile shape | Redis + Sentinel manifests |
| `scripts/up.sh` / `down.sh` pattern | Failover test (Sentinel failover) |
| NetworkPolicy / PDB patterns | Backup story (RDB/AOF → object storage) |
| `docs/AI_PROCESS.md` structure | DESIGN (Sentinel quorum vs Patroni DCS) |

Same phases: spec → design prompt → implement → verify → document gaps.

## Optional second-agent compare

Re-run design (`ai/prompts/01-design.md`) with a different model; diff sync vs async and DCS choices into `ai/sessions/second-agent-design-notes.md`.

## Session logs

See `ai/sessions/` for implementation session notes (secrets redacted).
