# Refactor Playbook: Normalize -> Features/Window

## Purpose

Provide a repeatable playbook for applying the same modular refactor approach from `normalize` to `features` and window builders.

## When to Use

Use this playbook when:
- stream logic is spread across large files
- common orchestration is mixed with stream-specific field/timestamp logic
- adding new device/mode/stream becomes risky or repetitive

## Target Shape

Use the same axis in all steps:
- `vendor -> device -> mode -> stream`

Recommended structure for each step:
- `.../<step>/<vendor>/common/*`
- `.../<step>/<vendor>/<device>/<mode>/common.py`
- `.../<step>/<vendor>/<device>/<mode>/streams/*.py`
- `.../<step>/<vendor>/<device>/<mode>/streams/policies.py` (if needed)

## Refactor Sequence

1. Freeze behavior
- Add or confirm focused tests around current behavior.
- Record current artifact fields and reports.

2. Extract common runner
- Move chunk/parquet iteration and report scaffolding into `common.py`.
- Keep stream-specific computations out of runner.

3. Introduce stream policies/hooks
- Define policy contracts per stream for:
  - required fields
  - field mapping
  - timing rules
  - interpolation/repair hooks (if applicable)

4. Move stream logic to `streams/*.py`
- One stream module = one stream behavior entry.
- Runner calls policy hooks only.

5. Migrate registry
- Update registry imports to explicit stream handlers.
- Keep backward-compatible aliases temporarily if needed.

6. Validate and document
- Run focused tests then broader tests.
- Update docs and progress log.

## Applying to `features` and Window Builders

Current `features` pattern already has registry dispatch and per-stream builders. Refactor target is mainly naming/placement and common orchestration.

### Step A: Introduce features common layer

Create shared helpers for:
- loading clean parquet
- validating required metadata
- writing output artifact
- consistent warning/error status formatting

These belong in:
- `pipeline/features/common/*`

### Step B: Convert builders to device/mode/stream layout

Move current modules like:
- `hr_window.py`, `acc_window.py`, `ecg_window.py`, `ppg_window.py`, `vector_window.py`, `battery_window.py`

toward:
- `pipeline/features/polar/h10/online/streams/*.py`
- `pipeline/features/polar/verity_sense/offline/streams/*.py`

Keep shared math (for example vector aggregation) in:
- `pipeline/features/polar/common/*`

### Step C: Add feature policies if branching grows

If a builder supports many schemas/variants, define policy classes:
- window sizes
- required columns
- aggregation functions
- gap handling behavior

### Step D: Keep step runner thin

`features/step.py` should orchestrate:
- selection
- read -> handle -> write
- run-state

No stream math in step runner.

## Naming Standard (Recommended)

For policies:
- `<Device><Mode><Kind>Policy`

For runners/orchestrators:
- `<Device><Mode><Pattern>Normalizer`
- `<Device><Mode><Pattern>FeatureBuilder`

For stream handlers:
- `<Device><Mode><Stream>FeatureBuilder`
- `Polar<Stream>Normalizer` where service-wide compatibility naming is already used

## Compatibility Strategy

If class/module names change:
- keep aliases during migration
- migrate registry imports first
- migrate tests second
- remove aliases only after a stable cycle

## Validation Checklist

For each refactor PR:
- tests for changed stream handlers
- deterministic rerun check
- raw artifact immutability check
- unchanged run-state shape unless explicitly planned
- unchanged artifact field names unless explicitly planned

## Quick “Do/Don’t”

Do:
- small, staged refactors
- explicit policy contracts
- strict runner/handler separation

Don’t:
- embed stream-specific hacks in generic step runners
- mix architecture move with large behavior rewrite
- hide new logic in ad-hoc utilities without tests
