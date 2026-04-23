# ADR-001: Monorepo and Single Collector Direction

## Status
Accepted

## Context
The project includes:
- shared docs
- one evolving architecture
- one collector direction
- one backend ingestion direction
- shared transport contracts

## Decision
Use one repository with separated directories.
Use one collector app with multiple sensor adapters.

## Consequences
### Positive
- easier end-to-end changes
- shared contracts stay close to implementation
- docs, code, and architecture evolve together

### Negative
- repository will contain multiple runtimes
- requires discipline in directory structure