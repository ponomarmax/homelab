# HR MVP Pipeline Architecture

## Purpose

This document defines the agreed architecture for the wearable heart-rate MVP pipeline.

It is a documentation-only checkpoint and acts as the source of truth before implementation starts.

This checkpoint does **not** introduce:
- runtime code
- new services in Compose
- new dependencies
- behavior changes

---

## MVP Scope

Strict MVP flow:

`Polar Verity Sense HR -> iOS Collector -> wearable-ingestion-api -> raw JSONL -> nightly-orchestrator-job -> normalize -> clean Parquet -> window features -> nightly summary -> LLM interpretation -> Telegram`

MVP focus:
- heart rate only
- single-node deployment
- deterministic processing steps
- raw-first ingestion
- explicit artifact boundaries

Non-goals for MVP:
- sleep stages
- ML models
- multi-service orchestration
- advanced UI
- environment ingestion

---

## End-to-End Flow

Primary flow:

`iOS Collector -> wearable-ingestion-api -> raw JSONL`

`nightly-orchestrator-job -> normalize -> clean Parquet -> window features -> summary JSON -> report MD -> Telegram`

The ingestion API is always-on.
The orchestrator is a single-container batch-style job.

---

## Service Topology

### 1. iOS Collector

Role:
- connect to the wearable
- manage session lifecycle
- collect stream payloads
- upload chunks using canonical transport contracts

The collector is the only mobile entry point for wearable collection.

### 2. `wearable-ingestion-api`

Role:
- receive upload chunks
- validate transport contract
- persist raw JSONL
- return ACK

Must do:
- stay lightweight
- remain always-on
- preserve raw upload truth

Must **not** do:
- normalize timestamps
- compute features
- call LLM
- send Telegram
- perform analytical aggregation

### 3. `nightly-orchestrator-job`

Role:
- run pipeline steps
- track run status
- produce artifacts
- remain extensible for future streams

The orchestrator is deterministic workflow logic, **not** an AI agent.

Initial steps:
- `normalize_hr`
- `build_window_features`
- `build_nightly_summary`
- `generate_llm_report`
- `send_telegram`

---

## iOS Collector Architecture

### Extensibility

The collector must support pluggable device adapters.

Required separation:

`UI -> Collector Core -> Device Adapter -> Transport`

Design rules:
- the collector core manages session lifecycle and upload coordination
- the device adapter handles vendor-specific data capture
- the transport layer maps collected data into shared contracts
- adding a new device must not require rewriting collector core logic

The collector must be able to support multiple stream types over time, including:
- HR
- PPI
- ACC
- EEG

### Collection Modes

Supported collection modes:
- `live` for MVP
- `offline_recording` in the future
- `imported_data` in the future

Collection mode must be stored in session metadata.

Terminology rule:
- UX-facing names may use `live` and `imported_data`
- transport metadata should remain aligned with canonical contracts such as `online_live`, `offline_recording`, and `file_import`

The system must **not** assume `collector_received_at` equals real sample time.

### Testability

The collector must support:
- mock data providers
- tests without a real physical device
- deterministic fixture-driven validation where possible

### UX Principles

The MVP collector UI should be:
- clean
- minimal
- responsive
- explicitly state-driven

Required visible states:
- disconnected
- device selected
- collecting
- stopped

Required MVP interactions:
- simple device selection
- explicit start session
- explicit stop session
- latest HR visible on screen

Checkpoint 1 implementation baseline:
- runnable in iOS Simulator
- mock HR stream only
- no Bluetooth
- no real Polar SDK
- no backend upload yet

Checkpoint 2 extension:
- mock sessions now produce explicit session metadata
- the collector tracks buffered HR samples during a session
- the transport boundary includes a stream descriptor for HR
- the collector can prepare upload chunk payloads from buffered mock samples
- upload chunk preparation is local only and does not call the backend yet

Future but not MVP:
- device list
- session history
- mode selection
- diagnostics

Non-goals:
- complex UI
- animations
- a heavy design system

---

## Data Layers

### 1. Raw

Format:
- JSONL

Rules:
- append-only
- full truth
- preserve all available timestamps
- no normalization
- no analytical assumptions

Collector-side pre-ingestion note:
- the iOS collector may prepare upload chunk payloads before sending them
- those chunks are transport envelopes, not the raw storage layer itself
- raw JSONL persistence still starts at `wearable-ingestion-api`

### 2. Clean Time Series

Format:
- Parquet

Rules:
- canonical `ts_utc`
- sample-level rows
- no aggregation
- traceable back to raw inputs

### 3. Window Features

Format:
- Parquet

Rules:
- first aggregation layer
- window sizes begin with `30s`, `1m`, and `5m`

### 4. Nightly Summary

Format:
- JSON

Rules:
- deterministic
- computed without LLM

### 5. Report

Format:
- Markdown

Rules:
- interpretation layer only
- generated from deterministic summary artifacts

### 6. Telegram Output

Rules:
- final delivery layer
- downstream of report generation

---

## Storage Layout

Target storage paths:

- `/data/wearable/raw/`
- `/data/wearable/processed/clean_timeseries/`
- `/data/wearable/processed/window_features/`
- `/data/wearable/summaries/`
- `/data/wearable/reports/`
- `/data/wearable/pipeline_runs/`

These paths define the intended repository and runtime storage model for the pipeline artifacts.

---

## Extensibility Model

The pipeline separates **step** from **handler**.

Definition:
- Step = pipeline phase
- Handler = stream-specific logic inside that phase

Examples:

`normalize`
- `PolarHrNormalizer`
- `PolarPpiNormalizer`
- `PolarAccNormalizer`

`features`
- `HrFeatureBuilder`
- `HrvFeatureBuilder`
- `MovementFeatureBuilder`

Rule:
Adding a new stream should extend handler coverage inside existing steps rather than forcing a pipeline rewrite.

This keeps the outer pipeline stable while allowing stream-specific logic to grow over time.

---

## Time Alignment

Time alignment rules are defined in detail in `docs/wearable/time_alignment.md`.

Architecture-level rules:
- raw timestamps are always preserved
- `ts_utc` is the canonical analytical timestamp
- alignment is performed only in the normalizer
- the normalizer expands batches into sample-level rows
- the normalizer must not aggregate

Required support:
- live mode
- offline mode
- batch expansion

Confidence levels:
- high
- medium
- low

Required artifact:
- `time_alignment_report.json`

---

## Testing Strategy

Testing strategy is defined in detail in `docs/wearable/testing_strategy.md`.

Architecture-level rules:
- synthetic fixtures must be supported
- sanitized real fixtures should be used where possible
- private real data may be used in private validation paths
- each pipeline step should be independently verifiable
- the full HR flow should have a smoke path

Target commands:
- `make test`
- `make test-pipeline`
- `make smoke-hr`

Testing depth will evolve by checkpoint.

---

## Developer File Browser

An optional developer file browser may be added as a local-only read-only utility.

Rules:
- browse `/data`
- local only
- read-only
- not part of the pipeline
- not required for MVP execution

---

## Environment Data Compatibility

The architecture must remain compatible with future environment ingestion.

Future continuous flow:

`Airlytix ES1 -> ESPHome -> Home Assistant -> environment ingestion -> raw environment data -> clean time series -> window features -> join with sleep session -> nightly summary`

Key rules:
- environment data is continuous, not session-based
- raw environment data is time-partitioned, not session-partitioned
- sleep session defines the later join window: `sleep_start_utc -> sleep_end_utc`
- environment data is joined later by time

Do **not**:
- bind environment data to a wearable session at ingestion
- hardcode HR-only assumptions into pipeline architecture

Future ingestion examples:
- Home Assistant API
- ESPHome integration

Environment normalization should follow the same high-level model:
- raw
- clean time series
- window features

---

## Dashboard / Tablet Display

Future display layer may include:
- Grafana dashboards
- tablet kiosk display
- real-time environment metrics
- alerts such as CO2 or air-quality warnings

This is a future architecture note only.

Non-goal for MVP:
- do not implement dashboards as part of this checkpoint

---

## Roadmap Order

Planned HR MVP sequence:

0. docs
1. iOS skeleton
2. mock HR
3. real HR
4. ingestion API
5. upload flow
6. raw storage
7. normalize
8. features
9. summary
10. orchestrator
11. LLM
12. Telegram
13. full smoke

---

## Constraints for This Checkpoint

This checkpoint must not:
- add runtime code
- add services
- add dependencies
- add ML
- add LLM integration
- change runtime architecture

The goal is only to document the agreed target architecture clearly and consistently.
