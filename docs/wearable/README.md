# Wearable Contracts

Detailed wearable transport/payload contracts and device notes.

## Scope
- Multi-stream raw ingestion contracts (collector -> ingestion API).
- Stream taxonomy, device/mode matrix, and payload registry.
- Transport envelope vs payload separation.
- Raw-first ingestion boundaries.

## Contract Sources
- `docs/wearable/canonical_contracts.md`
- `docs/wearable/payload_registry.md`
- `packages/schemas/transport/*`
- `packages/schemas/payloads/*`
- `packages/schemas/examples/*`

## Pipeline Engineering Docs
- `docs/wearable/pipeline_service_best_practices.md`
- `docs/wearable/refactor_playbook_normalize_features_window.md`

## Canonical Stream Taxonomy
- Online `verity_sense`: `hr`
- Online `h10`: `hr`, `acc`, `ecg`, `battery`
- Offline `verity_sense`: `hr`, `acc`, `gyro`, `mag`, `ppg`, `ppi`

## Canonical Device Models
- `h10`
- `verity_sense`

## Battery Contract Rule
- `stream_type` MUST be `battery`.
- `transport.payload_schema` MUST be `polar.device_battery`.

## Ingestion Boundary
- Ingestion validates transport metadata and persists raw payload as-is.
- Ingestion does not normalize, compute features, call LLMs, or deliver reports.

## Grafana Session Explorer (Debug Layer)
- Grafana explorer must consume processed deterministic artifacts only (`clean_timeseries`, `window_features`, `session_summary`).
- Export step: `export_grafana_views` in `wearable-pipeline-api`.
- Trigger endpoint: `POST /api/v1/pipeline/export/grafana-session` with `{ "session_id": "<id>" }`.
- Output:
  - `/data/wearable/grafana/sessions.json`
  - `/data/wearable/grafana/normalized_ppi_points.csv`
  - `/data/wearable/grafana/feature_windows.csv`
  - `/data/wearable/grafana/quality_events.csv`
- Scope is debug/validation only. This layer is not a replacement for canonical artifacts and not an LLM/reporting layer.
