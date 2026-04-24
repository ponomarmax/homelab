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

## Architecture summary
The current homelab architecture is:
- single-node
- Docker-first
- repository-controlled
- persistence-aware
- observability-enabled

The observability baseline is now a first-class architectural layer rather than a future placeholder.