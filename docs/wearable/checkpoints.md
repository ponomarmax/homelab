# Wearable Checkpoints

## Goal

Break the work into small observable vertical slices.

---

## CP0 — Documentation source of truth
- HR MVP pipeline architecture is documented
- testing strategy is documented
- time alignment rules are documented
- service boundaries and artifact layers are fixed before implementation

## CP1 — Polar connection state
- app scans and connects
- connection state is visible
- session lifecycle is visible

## CP2 — Mock HR visibility
- mock provider drives the collector without a real device
- live HR is visible in the app
- packet count grows
- last packet time is visible

## CP3 — Real HR end-to-end
- real HR is uploaded
- raw backend file is stored
- success / failure upload state is visible

## CP4 — Raw storage readability
- files are grouped by session and stream
- raw data is easy to inspect manually

## CP5 — Upload flow
- collector upload path is wired
- success / failure upload state is visible
- ingestion ACK is handled clearly

## CP6 — Basic resilience
- reconnect handling
- backend unavailable handling
- duplicate upload handling

## CP7 — Normalize HR
- raw HR is converted into clean sample-level rows
- canonical `ts_utc` is assigned in normalization
- time alignment decisions are inspectable

## CP8 — Build features
- first session-level multi-stream window features are produced
- feature artifacts are readable and verifiable

## CP9 — Build session summary
- deterministic session summary is produced
- summary remains independent from LLM interpretation

## CP10 — Orchestrator job
- single-container deterministic pipeline execution is defined
- step status and artifacts are tracked

## CP11 — LLM interpretation
- report generation consumes deterministic summary artifacts
- interpretation remains downstream from computed metrics

## CP12 — Telegram delivery
- final report is delivered through Telegram
- delivery is downstream from report generation

## CP13 — Full smoke
- minimal end-to-end HR pipeline passes as one coherent flow

Future extension checkpoints:
- sleep detection extension checkpoints CP14-CP21 are defined in `docs/wearable/sleep_detection_roadmap.md`
- PPI and ACC extension work must follow that roadmap and remain consistent with raw-first boundaries

## CP14 — Operational Offline PPI+ACC Session Flow

- one-button collector workflow for offline `PPI` + `ACC`:
  - start session
  - stop and sync
  - upload raw chunks
  - trigger pipeline
- operator endpoints for session listing/detail:
  - `/api/v1/operator/sessions`
  - `/api/v1/operator/sessions/{session_id}`
- no sleep-stage or ML logic in this checkpoint
