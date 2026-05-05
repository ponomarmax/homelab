# Payload Registry

This registry lists sensor-specific payload contracts that may be referenced by `StreamDescriptorContract.payload_schema` and `UploadChunkContract.transport.payload_schema`.

| Payload schema | Version | Sensor | Stream type | Status | Schema file | Example |
| --- | --- | --- | --- | --- | --- | --- |
| `polar.hr` | `1.0` | h10 | `hr` | accepted | `packages/schemas/payloads/polar/polar.hr.v1.schema.json` | `packages/schemas/examples/payloads/polar.hr.v1.json` |
| `polar.ppi` | `1.0` | verity_sense | `ppi` | accepted | `packages/schemas/payloads/polar/polar.ppi.v1.schema.json` | `packages/schemas/examples/payloads/polar.ppi.v1.json` |
| `polar.acc` | `1.0` | h10 | `acc` | accepted | `packages/schemas/payloads/polar/polar.acc.v1.schema.json` | `packages/schemas/examples/payloads/polar.acc.v1.json` |
| `polar.ecg` | `1.0` | h10 | `ecg` | accepted | `packages/schemas/payloads/polar/polar.ecg.v1.schema.json` | `packages/schemas/examples/payloads/polar.ecg.v1.json` |
| `polar.device_battery` | `1.0` | h10 | `battery` | accepted | `packages/schemas/payloads/polar/polar.device_battery.v1.schema.json` | `packages/schemas/examples/payloads/polar.device_battery.v1.json` |
| `polar.offline.hr` | `1.0` | verity_sense | `hr` | accepted | `packages/schemas/payloads/polar/polar.offline.hr.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.hr.v1.json` |
| `polar.offline.ppi` | `1.0` | verity_sense | `ppi` | accepted | `packages/schemas/payloads/polar/polar.offline.ppi.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.ppi.v1.json` |
| `polar.offline.acc` | `1.0` | verity_sense | `acc` | accepted | `packages/schemas/payloads/polar/polar.offline.acc.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.acc.v1.json` |
| `polar.offline.ppg` | `1.0` | verity_sense | `ppg` | accepted | `packages/schemas/payloads/polar/polar.offline.ppg.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.ppg.v1.json` |
| `polar.offline.mag` | `1.0` | verity_sense | `mag` | accepted | `packages/schemas/payloads/polar/polar.offline.mag.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.mag.v1.json` |
| `polar.offline.gyro` | `1.0` | verity_sense | `gyro` | accepted | `packages/schemas/payloads/polar/polar.offline.gyro.v1.schema.json` | `packages/schemas/examples/payloads/polar.offline.gyro.v1.json` |
| `muse.eeg` | `1.0-draft` | Muse Athena | `eeg` | draft | `packages/schemas/payloads/muse/muse.eeg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.eeg.v1-draft.json` |
| `muse.ppg` | `1.0-draft` | Muse Athena | `ppg` | draft | `packages/schemas/payloads/muse/muse.ppg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.ppg.v1-draft.json` |

## Rules

- Transport schema versions and payload versions are independent.
- Draft payloads must remain clearly marked as draft.
- Ingestion validates the transport envelope only; payload content remains opaque at ingest boundary.
- Deep sensor parsing belongs after raw ingestion.
- `polar.device_battery` is a known device-status stream and is supported by the wearable processing pipeline via a dedicated battery handler.
- Legacy offline gyro inputs (`payload.type=GYR`, `transport.payload_schema=polar.offline.gyr`, `payload_version=v1-draft`) must be normalized at collector/adapter edge to canonical `GYRO` / `polar.offline.gyro` / `1.0`.
- Legacy offline PPI envelope values (`payload_version=v1-draft`, `source.device_model=Polar Verity Sense`, `time.device_time_reference=polar:offline_recording`) must be normalized to `1.0`, `verity_sense`, and `polar`.
- `polar.offline.*` payloads preserve raw offline fields (including raw/zero timestamps) and do not define canonical `ts_utc`.
- Sensor payloads may include optional `stream_settings` to preserve SDK-negotiated runtime stream configuration as raw metadata.
