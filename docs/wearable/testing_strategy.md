# Wearable Testing Strategy

## Purpose

This document defines the testing strategy for the wearable pipeline, starting with the HR MVP.

The strategy is designed to evolve by checkpoint while keeping each step verifiable and lightweight on a single-node homelab.

---

## Testing Goals

- validate contracts before runtime expansion
- keep pipeline steps independently testable
- support development without requiring a real device every time
- preserve confidence in raw-first ingestion
- verify artifacts, not just process success

---

## Fixture Types

### 1. Synthetic Fixtures

Use for:
- deterministic unit tests
- edge cases
- malformed contract cases
- timestamp alignment cases
- missing field validation

Properties:
- fully shareable
- safe for the repository
- easy to version

### 2. Sanitized Real Fixtures

Use for:
- realistic payload shape validation
- stream-specific parsing behavior
- timestamp drift and batch behavior
- artifact validation close to real conditions

Properties:
- derived from real collection data
- cleaned of sensitive or unnecessary metadata
- safe for repository use only after sanitization

### 3. Private Real Data

Use for:
- final realism checks
- smoke validation against actual collection patterns
- non-public regression confirmation

Properties:
- not committed to the repository
- stored privately
- used only in local or private validation flows

---

## Test Layers

### Unit Tests

Scope:
- helper logic
- timestamp expansion rules
- schema validation helpers
- feature calculations
- deterministic summary logic

Goal:
- keep business rules small and directly testable

### Contract Tests

Scope:
- `SessionContract`
- `StreamDescriptorContract`
- `UploadChunkContract`
- ACK and error shapes
- payload schema compatibility

Goal:
- confirm that transport boundaries stay stable

### Artifact Validation

Scope:
- raw JSONL shape
- clean Parquet schema
- feature Parquet schema
- summary JSON shape
- report Markdown presence and expected sections
- `time_alignment_report.json`

Goal:
- verify that each step produces inspectable outputs with consistent structure

### Step Tests

Scope:
- `normalize_hr`
- `build_window_features`
- `build_nightly_summary`
- `generate_llm_report`
- `send_telegram`

Goal:
- validate each step in isolation with known inputs and expected artifacts

Notes:
- deterministic steps should have deterministic expected outputs
- delivery steps may validate generated payloads or dry-run outputs rather than external side effects

### Smoke HR Pipeline

Scope:
- a minimal end-to-end HR path using controlled data

Target path:
- collector-style payload
- ingestion acceptance
- raw persistence
- normalization
- feature build
- summary generation
- report generation

Goal:
- confirm the pipeline still works as one coherent flow

---

## Verification Philosophy

Each logical step must be verifiable beyond "the process ran".

Verification should confirm:
- expected input contract
- expected artifact existence
- expected schema or structure
- expected traceability back to source artifacts

This is especially important for:
- raw persistence
- timestamp normalization
- feature window generation
- nightly summary generation

---

## Command Targets

Target command names:
- `make test`
- `make test-pipeline`
- `make smoke-hr`

Expected purpose:

`make test`
- run the main unit and contract-oriented test suite

`make test-pipeline`
- run pipeline step and artifact validation tests

`make smoke-hr`
- run the smallest practical HR end-to-end smoke path

These commands are target names for the implementation checkpoints that follow.
They are documented here before implementation to keep terminology stable.

---

## Checkpoint Evolution

Testing should evolve by checkpoint.

Checkpoint direction:

### CP0
- documentation only
- define test layers and target commands

### CP1 to CP3
- add collector mock-based tests
- add transport contract tests
- add fake and real HR upload checks

CP1 baseline:
- mock HR provider tests
- collector lifecycle tests
- collector domain model tests
- `xcodebuild build-for-testing` should compile the iOS app and unit tests without a real device

CP2 extension:
- session metadata creation tests
- sample sequence and buffered sample count tests
- upload chunk model tests
- timestamp preservation checks on prepared chunks
- session stop timestamp tests

### CP4 to CP7
- add raw storage readability checks
- add normalization and artifact validation
- add feature and summary step tests

### Later checkpoints
- extend smoke coverage
- add more stream handlers without rewriting the main test model
- add private real-data regression passes

---

## Resource Awareness

The testing strategy should stay lightweight:
- prefer small fixtures
- prefer deterministic local tests
- avoid large retained datasets in the repository
- keep smoke artifacts compact

This aligns with the single-node 8GB RAM constraint.

---

## Non-Goals

This strategy does not require:
- new runtime services
- distributed test infrastructure
- heavy local ML validation
- full production load testing

The goal is reliable incremental validation, not a heavy testing platform.
