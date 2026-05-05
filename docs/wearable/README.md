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
