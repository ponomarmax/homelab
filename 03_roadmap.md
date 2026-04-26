# Roadmap

## Wearable HR MVP checkpoint order

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

Status: documentation checkpoint defined

---

## Stage 1 — Repository and Infrastructure Initialization

* create repository structure
* add docs and rules
* initialize Docker-based platform

Status: done

---

## Stage 2 — Monitoring and Observability

* deploy Node Exporter (done)
* deploy Prometheus (done)
* deploy cAdvisor (done)
* deploy Grafana (done)
* add dashboards as code (done)
* validate alerting (Telegram)

Status: in progress

### Stage 2 Notes

Observability baseline is now implemented and includes:
- host metrics (Node Exporter)
- container metrics (cAdvisor)
- metrics storage (Prometheus)
- visualization (Grafana)
- dashboards as code (provisioned from repository)

Remaining work in this stage focuses on:
- alerting validation
- notification path (Telegram)
- observability hardening and cleanup

---

## Stage 3 — Home Assistant Setup

* deploy Home Assistant
* verify basic functionality
* confirm persistence and restart behavior

Status: planned

---

## Stage 4 — First Sensor Integration

* choose first sensor
* connect it to Home Assistant
* validate data flow

Status: planned

---

## Stage 5 — First Automation

* create environment-based automation
* likely scenario: air purifier control based on humidity / air quality

Status: planned

---

## Stage 6 — Environmental Data Collection

* accumulate sensor data over time
* identify useful metrics and trends

Status: planned

---

## Stage 7 — External Data Integration

* investigate Garmin data access
* investigate sleep app data access
* identify legal and technical integration paths
* use export-based workflows if APIs are unavailable

Status: planned

---

## Stage 8 — Wearable HR MVP Pipeline

Goal:
Deliver a strict HR-only end-to-end pipeline with raw-first storage and deterministic nightly processing.

Planned sequence:
- CP0: document HR MVP architecture, testing strategy, and time alignment
- CP1: add iOS collector skeleton (done)
- CP2: add mock HR session metadata and upload chunk preparation (done)
- CP3: validate real HR collection
- CP4: add ingestion API
- CP5: add upload flow
- CP6: persist raw JSONL
- CP7: normalize to clean Parquet
- CP8: build window features (session-based multi-stream processing)
- CP9: build nightly deterministic summary
- CP10: add single-container orchestrator
- CP11: add LLM interpretation layer
- CP12: add Telegram delivery
- CP13: run full smoke validation

Rules:
- no agent frameworks
- no multi-service orchestration for MVP
- each step must be independently verifiable
- adding future streams should extend handlers, not rewrite the pipeline

---

## Stage 9 — Correlation Analysis

* correlate sleep-related metrics with:

  * temperature
  * humidity
  * air quality
  * noise
  * light

Status: future

---

## Stage 10 — ML Experiments

* feature engineering
* simple baseline models
* anomaly detection or prediction experiments

Status: future

## Future Work — Health & Availability Layer (Planned)

Status: planned, non-blocking

Goal:
Add service-level health monitoring on top of existing resource monitoring.

Current limitation:
The system currently provides:
- host metrics (Node Exporter)
- container resource metrics (cAdvisor)
- storage & visualization (Prometheus + Grafana)

However, it lacks:
- explicit service availability checks
- restart/failure detection signals
- endpoint-level validation (is service actually responding?)

Planned additions:

1. Blackbox Exporter
   - HTTP/TCP probes for critical services
   - validate real availability, not just container presence

2. Health Dashboard
   - separate from resource dashboards
   - show:
     - service availability
     - probe success/failure
     - target status
     - basic system health overview

3. Basic Alerting Signals (future extension)
   - service down
   - probe failure
   - repeated failures / flapping
   - critical container instability

Design principles:
- keep separate from resource dashboards
- minimal but meaningful signals
- repository-controlled configuration
- reproducible via Docker Compose

This work is intentionally deferred until:
- baseline observability stack is stable
- dashboards are validated
