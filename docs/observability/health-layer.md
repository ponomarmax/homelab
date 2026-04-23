# Health & Availability Layer (Planned)

## Purpose
Extend observability beyond resource metrics to service-level health.

## Problem
Resource metrics do not answer:
- is the service reachable?
- is the endpoint responding?
- are failures happening intermittently?

## Approach

### 1. Blackbox Probing
- HTTP checks for UI/API services
- TCP checks for internal services
- optional ICMP where useful

### 2. Health Dashboard
Separate dashboard containing:
- service availability
- probe success rate
- failed targets
- latency (optional)

### 3. Alerting (future)
- service down
- repeated probe failures
- instability patterns

## Design Constraints
- minimal overhead
- Docker Compose based
- reproducible
- no manual UI setup

## Not in scope (yet)
- full alerting stack
- advanced SLO/SLA tracking
- distributed tracing