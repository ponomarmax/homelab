# Wearable Pipeline API Best Practices

## Purpose

Define stable engineering practices for `services/wearable-pipeline-api` so runtime evolution stays modular, deterministic, and resource-light.

This document is implementation-oriented and complements:
- `docs/wearable/canonical_contracts.md`
- `docs/wearable/payload_registry.md`
- `docs/wearable/time_alignment.md`

## Scope Boundaries

- Ingestion is raw-first and payload-opaque.
- Pipeline normalization assigns canonical analytical `ts_utc`.
- Feature builders consume normalized artifacts only.
- Session summary consumes feature artifacts only.
- No sleep inference/ML/LLM/reporting/Telegram logic inside normalize or window feature code.

## Runtime Constraints

- Single-node deployment.
- Docker Compose first.
- No Kubernetes assumptions.
- Keep memory profile lightweight (8 GB host budget).
- Avoid always-on new services for pipeline refactors.

## Pipeline Architecture

Current runtime flow:
1. `normalize`
2. `window_features`
3. `build_session_summary`

Required architectural properties:
- Step boundaries are explicit and deterministic.
- Step run-state is persisted per session and step.
- Each step reads only upstream artifacts and writes only its own layer.
- Raw JSONL is immutable and never rewritten.

## Dispatch Model (Required)

Use registry dispatch keyed by:
- `source_vendor`
- canonical `device_model`
- `payload_schema`

Never dispatch only by folder name or stream directory.

For each stream:
- keep stream-specific logic in stream-specific modules
- keep common orchestration in `common.py` runners
- keep policy/config in policy classes or constants

## Folder and Naming Conventions

For normalize code:
- `polar/common/*` for cross-device shared utilities.
- `polar/<device>/<mode>/common.py` for mode-specific orchestration.
- `polar/<device>/<mode>/streams/*.py` for stream-specific field/timestamp logic.

Class naming convention:
- Orchestrators: `<Device><Mode><Pattern>Normalizer`
- Policies: `<Device><Mode><Kind>Policy`
- Stream handlers: `Polar<Stream>Normalizer` or `<Device><Mode><Stream>Normalizer` when scope-specific.

Compatibility rule:
- If renaming public classes, keep short-term aliases until all imports are migrated.

## Time Alignment Rules

- Use `time_alignment_report.json` for inspectable alignment decisions.
- Keep L0/L1/L2/L3/L4 logic explicit and testable.
- If cross-stream gating degrades confidence/level, write warning and rationale to report.
- Preserve raw timing fields where present; do not fabricate unavailable source values.
- For Verity Sense offline `ppi`, prefer interval-based (`ppInMs`) reconstruction when sample timestamps are invalid/zero.
- Treat `timeStamp` as diagnostic/provenance when it is cyclic/non-monotonic.
- Record startup-delay usage explicitly (`ppi_startup_delay_applied`, `ppi_startup_delay_seconds`) when enabled for session-specific modes.

## Artifact Rules

Normalize step must produce:
- clean sample-level Parquet
- `time_alignment_report.json`
- run-state entry

Window features step must produce:
- deterministic window Parquet artifacts
- run-state entry

Summary step must produce:
- deterministic `session_summary.json`
- run-state entry

## Testing Strategy (Service-Level)

Required for every structural refactor:
- targeted unit/integration tests for changed modules
- rerun idempotence check
- raw JSONL immutability check
- smoke run for one known sanitized session if lightweight

Prefer narrow commands first:
- run focused tests for changed step/module
- then run full service test file/suite if cheap

## Refactor Rules

Before refactor:
- map existing registry keys and handlers
- preserve behavior first, then simplify structure

During refactor:
- no behavior changes mixed with large moves unless explicitly required
- keep patches small and incremental
- preserve artifact schema/field names unless checkpoint explicitly allows change

After refactor:
- verify imports, registry coverage, and tests
- document moved modules and new extension points

## Anti-Patterns (Avoid)

- Stream-specific hacks inside generic runners.
- Dispatch based on path heuristics instead of metadata keys.
- Cross-step coupling (features reading raw JSONL directly).
- Implicit time assumptions hidden in utility helpers.
- Big-bang refactors without compatibility aliases or tests.

## Definition of Done for Structural Refactor

- Architecture remains registry-driven and modular.
- Common vs stream-specific responsibilities are clear.
- Artifacts and run-state behavior are unchanged unless planned.
- Relevant tests pass.
- Documentation updated with new structure and extension workflow.
