# 02 Architecture

## Purpose
This document describes the current target architecture of the homelab repository and the main responsibilities of each layer.

## High-level architecture
The system is designed as a **single-node homelab platform** running on a Linux host with **Docker Compose** as the default deployment model.

Core principles:
- single-node first
- reproducible infrastructure
- repository-controlled configuration
- lightweight services
- gradual service introduction
- operational clarity over premature complexity

## Main layers

### 1. Host layer
The Linux host is the execution environment for all containerized services.

Responsibilities:
- Docker Engine
- Docker Compose plugin
- local filesystem for persistent state
- local networking / LAN access
- basic OS-level administration

The host should remain as minimal as reasonably possible.
Prefer repository-controlled containerized services over manually installed long-running host services.

### 2. Edge / access layer
This layer represents the future entry points and externally reachable services.

Possible responsibilities:
- reverse proxy
- local-only UI access
- future secure service exposure
- network boundary management

This layer should stay intentionally small and explicit.

### 3. Service / application layer
This layer contains the actual homelab services deployed through Docker Compose.

Examples:
- Home Assistant and related automation services
- future ingestion / API / utility services
- observability services
- other self-hosted application components

### 4. Data / persistence layer
This layer contains all stateful storage used by services.

Responsibilities:
- service persistence
- volume / bind mount strategy
- repository-visible storage conventions
- future backup-aware layout

State must not be treated as living “inside containers”.
Containers are replaceable. Persistent state must survive recreate/update flows.

---

## NEW — Observability baseline architecture

The repository now includes a baseline observability stack implemented as part of the current architecture, not just as a future idea.

### Observability goals
The observability layer exists to provide:
- visibility into Linux host health
- visibility into Docker container resource usage
- a persistent metrics store
- a usable UI for metrics exploration
- repository-controlled dashboards as code
- a future base for alerting and notification flows

### Implemented observability services

#### Node Exporter
Role:
- exposes Linux host metrics

Examples of metric areas:
- CPU
- memory
- filesystem
- load
- network

Operational classification:
- effectively stateless

#### Prometheus
Role:
- scrapes metrics endpoints
- stores time-series data
- acts as the metrics backbone for the observability stack

Operational classification:
- stateful

Important notes:
- persistence must be explicit
- retention must be explicitly limited
- future metrics sources should integrate here first

#### cAdvisor
Role:
- exposes container-level resource metrics

Examples of metric areas:
- per-container CPU
- per-container memory
- container network traffic
- container-related storage signals where available

Operational classification:
- effectively stateless

#### Grafana
Role:
- observability UI layer
- Prometheus data visualization
- dashboard provisioning and organization
- future baseline for alerting UX and integrations

Operational classification:
- stateful

Important notes:
- persistence must be explicit
- Prometheus datasource should be provisioned from repository-controlled files
- dashboards should be managed as code, not primarily through manual UI creation

---

## NEW — Observability data flow

Current baseline flow:

`Linux host -> Node Exporter -> Prometheus`
`Docker runtime / containers -> cAdvisor -> Prometheus`
`Prometheus -> Grafana`

This creates two first-class observability perspectives:
- host / server observability
- container / Docker observability

---

## NEW — Dashboard-as-code architecture

Grafana dashboards are treated as part of infrastructure-as-code.

Principles:
- dashboards live in the repository
- dashboards are provisioned automatically
- dashboard structure should remain understandable and extendable
- future dashboards should follow the same conventions instead of being created manually in UI as the main path

Baseline dashboard organization should remain clearly separated by concern:
- host / Linux server dashboards
- Docker / container dashboards
- optional future overview / health dashboards

---

## NEW — Stateful vs stateless observability services

### Stateful
- Prometheus
- Grafana

These services require explicit persistence strategy and lightweight recreate validation.

### Effectively stateless
- Node Exporter
- cAdvisor

These services do not require persistent storage as part of the baseline design.

---

## Service integration model
All new services should be integrated with these principles:

- deployed primarily through Docker Compose
- configuration should live in repository-controlled locations
- service-specific logic stays near the service where appropriate
- shared scripts should be reused when genuinely generic
- stateful services must declare persistence explicitly
- validation must go beyond “container is running”

---

## NEW — Validation philosophy in architecture

A service is not considered integrated only because a container starts.

Expected validation types:
- process/container validation
- endpoint or UI validation
- functional validation
- persistence validation for stateful services

Examples:
- a metrics endpoint must return meaningful data
- Prometheus must actually scrape targets
- Grafana must actually query Prometheus
- dashboards must be provisioned automatically and show real non-empty data

---

## Future extension points
Likely future extensions include:
- baseline alert rules
- Telegram notification path
- additional dashboards
- service-level application metrics
- backup-aware persistence policy
- observability hardening and resource tuning

---

## NEW — Wearable HR MVP target architecture

The repository now also defines the target documentation architecture for the wearable HR MVP pipeline.

This section describes the agreed design before runtime implementation starts.

### Scope

Strict MVP path:

`Polar Verity Sense HR -> iOS Collector -> wearable-ingestion-api -> raw JSONL -> nightly-orchestrator-job -> normalize -> clean Parquet -> window features -> nightly summary -> LLM interpretation -> Telegram`

Current non-goals:
- sleep stages
- ML models
- multi-service orchestration
- advanced UI
- environment ingestion for MVP

### Wearable service topology

#### iOS Collector
Responsibilities:
- manage wearable session lifecycle
- collect stream payloads through pluggable device adapters
- upload transport-shaped chunks

Required architecture:

`UI -> Collector Core -> Device Adapter -> Transport`

Key rules:
- adding a new device must not rewrite collector core logic
- collection mode must be part of session metadata
- the collector must support mock data providers for testing

#### `wearable-ingestion-api`
Responsibilities:
- receive upload chunks
- validate contracts
- write raw JSONL
- return ACK

Must not:
- normalize timestamps
- compute features
- call LLM
- send Telegram

Operational role:
- lightweight
- always-on

#### `nightly-orchestrator-job`
Responsibilities:
- run deterministic pipeline steps
- track run status
- produce artifacts for downstream delivery

Initial planned steps:
- `normalize_hr`
- `build_window_features`
- `build_nightly_summary`
- `generate_llm_report`
- `send_telegram`

Important rule:
This is deterministic workflow orchestration, not an AI agent framework.

### Wearable data layers

1. Raw (`JSONL`)
   - append-only
   - preserves all timestamps
   - source-of-truth layer

2. Clean time series (`Parquet`)
   - canonical `ts_utc`
   - sample-level rows
   - no aggregation

3. Window features (`Parquet`)
   - first aggregation layer
   - intended windows include `30s`, `1m`, and `5m`

4. Nightly summary (`JSON`)
   - deterministic
   - computed without LLM

5. Report (`Markdown`)
   - interpretation layer only

6. Telegram output
   - final delivery layer

### Wearable storage layout

Target paths:
- `/data/wearable/raw/`
- `/data/wearable/processed/clean_timeseries/`
- `/data/wearable/processed/window_features/`
- `/data/wearable/summaries/`
- `/data/wearable/reports/`
- `/data/wearable/pipeline_runs/`

### Wearable extensibility model

The pipeline separates step orchestration from stream-specific handlers.

Definition:
- Step = pipeline phase
- Handler = stream-specific logic within a phase

Examples:
- normalization handlers such as `PolarHrNormalizer`, `PolarPpiNormalizer`, `PolarAccNormalizer`
- feature handlers such as `HrFeatureBuilder`, `HrvFeatureBuilder`, `MovementFeatureBuilder`

Rule:
Adding a stream should extend handlers inside existing steps, not force a rewrite of the pipeline structure.

### Time alignment architecture

Rules:
- raw timestamps are preserved
- `ts_utc` is the canonical timestamp for downstream analytical layers
- alignment happens only in the normalizer
- batch payloads are expanded into sample-level rows
- the normalizer does not aggregate

Required alignment artifact:
- `time_alignment_report.json`

Supported collection patterns:
- live mode
- offline mode
- batch expansion

### Environment compatibility

The architecture must stay compatible with future continuous environment data.

Expected future flow:

`Airlytix ES1 -> ESPHome -> Home Assistant -> environment ingestion -> raw environment data -> clean time series -> window features -> join with sleep session -> nightly summary`

Rules:
- environment data is continuous rather than session-based
- raw environment data is time-partitioned
- wearable or sleep sessions define later join windows
- environment data must not be bound to sessions at ingestion time

### Future display layer

Future but not MVP:
- Grafana dashboards
- tablet kiosk display
- real-time environment metrics
- alert-oriented screens such as CO2 or air-quality warnings

This layer is intentionally deferred and not part of current runtime scope.

## Architecture summary
The current homelab architecture is:
- single-node
- Docker-first
- repository-controlled
- persistence-aware
- observability-enabled
- raw-first for wearable ingestion
- designed for deterministic post-ingestion wearable processing

The observability baseline is now a first-class architectural layer rather than a future placeholder.
