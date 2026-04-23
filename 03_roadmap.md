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
* deploy cAdvisor
* deploy Grafana
* prepare basic dashboards
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
