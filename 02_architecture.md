# Architecture

## Overview

Single-node local platform based on Docker Compose.

Host machine:
- Intel i7-10510U
- 8GB RAM
- 512GB SSD

---

## High-Level Architecture

User
↓
Reverse Proxy
↓
Services Layer
  - Home Assistant
  - Monitoring stack
  - Future data services
↓
Docker Engine
↓
Linux host

---

## Service Groups

### 1. Infrastructure Layer
- Docker Engine
- Docker Compose
- Reverse Proxy

### 2. Smart Home Layer
- Home Assistant
- Sensors / device integrations

### 3. Observability Layer
- Prometheus
- Node Exporter
- cAdvisor
- Grafana

### 4. Data Layer (future)
- ingestion services
- time-series or structured storage
- export/import utilities

### 5. Analytics / ML Layer (future)
- feature extraction
- notebooks or scripts
- lightweight experiments

---

## Design Principles

- service isolation via Docker
- minimal external exposure
- modular structure
- low resource footprint
- monitoring added early
- reusable repo structure for future services

---

## Networking (conceptual)

- edge network -> reverse proxy
- internal network -> application services
- monitoring network -> metrics collection

---

## Storage

Persistent storage is required for:
- Home Assistant
- Prometheus
- Grafana
- future collected data

Docker volumes should be used by default.