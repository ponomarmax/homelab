# Observability Layer

## Purpose

This layer provides visibility into:

* host-level metrics
* container-level metrics
* system health and resource usage

It is introduced early to:

* validate infrastructure behavior
* detect resource issues early (RAM, CPU, storage)
* support future debugging and analysis

---

## Stack (planned)

* Node Exporter — host metrics (DONE)
* Prometheus — metrics storage and scraping
* cAdvisor — container metrics
* Grafana — visualization
* Alerting — Telegram integration

---

## Principles

* Docker Compose as the default deployment model
* services added incrementally (checkpoint-based)
* minimal resource footprint
* no overengineering
* reproducible setup via repository

---

## Service Pattern

Each observability service should follow:

1. Compose definition
2. Config (if required)
3. Validation (not only container running)
4. Optional persistence (if stateful)
5. Documentation

---

## Validation Levels

Each service should be validated on:

1. Container level

* running state
* no restart loop

2. Network level

* port accessible
* endpoint reachable

3. Functional level

* actual metrics or UI working

4. (If stateful) Persistence level

* survives container recreate

---

## Directory Structure (conceptual)

infra / observability / compose
infra / observability / config
tools / scripts / observability
data / observability

---

## Next Steps

* Add Prometheus
* Connect Node Exporter as first scrape target
* Introduce retention strategy
* Add Grafana and dashboards
* Introduce alerting
