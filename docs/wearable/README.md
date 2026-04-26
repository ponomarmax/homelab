# Wearable Data Docs

This directory contains the canonical documentation for wearable data collection.

## Files
- `canonical_contracts.md` — shared transport contracts between collector and backend
- `hr_mvp_pipeline.md` — agreed HR MVP pipeline architecture before implementation
- `time_alignment.md` — canonical timestamp alignment rules for normalization
- `testing_strategy.md` — test layers, fixtures, and smoke strategy
- `payload_registry.md` — registered payload schema ids and versions
- `polar_verity_sense.md` — current Polar-specific notes
- `muse_athena.md` — current Muse-specific notes
- `checkpoints.md` — implementation checkpoints and validation path

## Principles
- one collector app
- multiple sensor adapters
- stable outer transport metadata
- flexible sensor-specific payloads
- raw-first ingestion
- parsing after ingestion

## Real Payload Examples

These are minimal examples from real Polar H10 raw collection shape.

### HR (`polar.hr`)

```json
{
  "received_at_collector": "2026-04-25T11:56:27.357Z",
  "hr": 71
}
```

### ACC (`polar.acc`)

```json
{
  "device_time_ns": 3412345678900,
  "x_mg": 10,
  "y_mg": -3,
  "z_mg": 1005,
  "received_at_collector": "2026-04-25T11:56:27.357Z"
}
```

### ECG (`polar.ecg`)

```json
{
  "device_time_ns": 3412345678900,
  "ecg_uv": 120,
  "received_at_collector": "2026-04-25T11:56:27.357Z"
}
```

### Battery (`polar.device_battery`)

```json
{
  "stream_type": "device_battery",
  "payload_schema": "polar.device_battery",
  "payload": {}
}
```

Battery is device-status telemetry and is non-analytical by default.
Pipeline discovery must treat `device_battery` as a known non-analytical stream and skip it unless a dedicated handler is added.
