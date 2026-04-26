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

`pipeline processing -> normalize -> clean Parquet -> window features -> session_summary.json -> insights/reporting layer -> optional Telegram delivery`

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

iOS Collector
  -> UploadChunkContract (v1.0)
  -> wearable-ingestion-api
  -> structured raw storage (append-only JSONL)

`wearable-pipeline-api -> normalize -> clean Parquet -> window features -> summary JSON -> (Here a place for LLM communication but let mock it for a while) report MD -> Telegram`

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

### Automatic chunk upload (HR MVP)

For live HR collection:

- samples are buffered in memory
- chunk is flushed when:
  - sample count >= 20
  - OR 30 seconds passed
- whichever happens first
- remaining samples are flushed on session stop

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

### Raw ingestion behavior (Baseline V1)

- chunks are uploaded via UploadChunkContract
- ingestion API stores each chunk as one JSON line
- storage is partitioned by user, source, date, session, and stream_type
- one `chunks.jsonl` file per session per stream_type
- ingestion does not modify payloads

### 3. `wearable-pipeline-api` / pipeline processing

Role:
- run deterministic pipeline steps
- track run status
- produce processing artifacts
- remain extensible for future streams

The pipeline is deterministic workflow logic, **not** an AI agent.

Initial deterministic steps:
- `normalize_hr`
- `build_window_features`
- `build_session_summary`

Rules:
- session summary is computed from processed artifacts, not from raw ingestion directly
- session summary is deterministic and non-LLM
- session summary may represent a night session, daytime session, test session, or long-running wearable session
- session summary is the compact factual artifact used by future reporting and interpretation layers

---

### 4. Future `wearable-insights-job`

Role:
- read deterministic `session_summary.json`
- build prompts for optional LLM interpretation
- call an LLM provider when enabled
- validate and store LLM responses
- generate human-readable reports
- send reports to communication channels such as Telegram

This service/job is downstream of deterministic processing.

It must not:
- read raw ingestion as its primary input
- normalize timestamps
- build window features
- mutate deterministic artifacts
- be required for the core processing pipeline to succeed

Recommended first inputs:
- `session_summary.json`
- pipeline run metadata
- artifact paths

Recommended outputs:
- `llm_prompt.json` or `prompt.md`
- `llm_response.json`
- `report.md`
- delivery status metadata



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

### 4. Session Summary

Format:
- JSON

Rules:
- deterministic
- computed without LLM
- session-based, not necessarily night-based
- compact factual artifact for validation, reporting, and future interpretation

### 5. Insights / Report

Format:
- Markdown and/or JSON

Rules:
- interpretation layer only
- may use LLM later
- generated from deterministic session summary artifacts
- not required for deterministic pipeline success

### 6. Communication Output

Rules:
- final delivery layer
- downstream of report generation
- first planned channel: Telegram
- future channels may include email, dashboard annotations, or local notifications

---

## Storage Layout
## Pipeline Run State

Pipeline execution must produce lightweight run metadata.

Storage path:

/data/wearable/pipeline_runs/

Each step creates its own run record.

---

### Run Metadata Requirements

Each run must include:

- run_id
- step_name
- session_id
- started_at_utc
- finished_at_utc
- status: success | partial | failed
- discovered_streams

Per-stream results:

- stream_type
- handler_name
- status: success | skipped | failed
- input artifact path
- output artifact path (if produced)
- error message (if any)

---

### Rules

- Run state must be file-based
- No database required
- Must not be stored in raw layer
- Must be inspectable manually

---

### Purpose

- traceability
- debugging
- validation
- future orchestrator integration

---

## Extensibility Model

## Session-Based Multi-Stream Processing

### Processing Unit

The pipeline operates on the **session level**, not on individual streams.

A single session may contain multiple streams, for example:
- hr
- ppi
- acc
- gyro
- ppg
- eeg

All available streams within a session must be discovered and processed.

---

### Stream Discovery

Pipeline steps must:

1. Scan the session directory:
   `/data/wearable/raw/.../session_id=<id>/streams/`

2. Detect available `stream_type` folders.

3. Build a list of available streams for the session.

---

### Handler Dispatch

Each step must dispatch processing using a handler model:

- Step = pipeline phase
- Handler = stream-specific implementation

Examples:

normalize:
- PolarHrNormalizer
- PolarPpiNormalizer
- PolarAccNormalizer

window_features:
- HrWindowFeatureBuilder
- HrvWindowFeatureBuilder
- MovementFeatureBuilder

---

### Execution Rules

- Streams are processed sequentially (no parallelism in MVP)
- Unsupported streams are skipped with warnings
- One failed stream must not stop processing of other streams
- Each stream produces its own artifact

---

### Design Rule

Adding a new stream must:
- require adding a new handler
- NOT require rewriting pipeline steps

This ensures pipeline stability as new sensors are introduced.
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
