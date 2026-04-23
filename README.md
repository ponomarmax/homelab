# Homelab Platform

Local single-node platform for infrastructure, observability, smart-home automation, wearable data collection, ingestion, visualization, and future lightweight analytics.

The repository is organized as a monorepo so docs, contracts, collector apps, backend services, and operational tooling can evolve together.

## Top-Level Structure

- `docs/` - architecture, ADRs, wearable notes, and project planning
- `apps/` - client applications, starting with the iOS collector
- `services/` - backend services such as ingestion and visualization
- `packages/` - shared packages and schema contracts
- `infra/` - Docker Compose and environment documentation
- `data/` - local data landing areas; large datasets should not be committed
- `tools/` - helper scripts and validation utilities
- `notebooks/` - future lightweight analysis notebooks

## Current Focus

The current wearable foundation is raw-first ingestion:

1. one collector app
2. multiple sensor adapters
3. stable transport contracts
4. sensor-specific payload schemas
5. parsing and normalization after ingestion

See `docs/wearable/canonical_contracts.md` for contract semantics.
