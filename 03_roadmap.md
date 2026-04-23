# Roadmap

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
* prepare basic dashboards (done)
* validate alerting (Telegram)

Status: in progress

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

## Stage 8 — Correlation Analysis

* correlate sleep-related metrics with:

  * temperature
  * humidity
  * air quality
  * noise
  * light

Status: future

---

## Stage 9 — ML Experiments

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
