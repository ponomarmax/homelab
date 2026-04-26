# Payload Registry

This registry lists sensor-specific payload contracts that may be referenced by `StreamDescriptorContract.payload_schema` and `UploadChunkContract.transport.payload_schema`.

| Payload schema | Version | Sensor | Stream type | Status | Schema file | Example |
| --- | --- | --- | --- | --- | --- | --- |
| `polar.hr` | `1.0` | Polar H10 | `hr` | accepted | `packages/schemas/payloads/polar/polar.hr.v1.schema.json` | `packages/schemas/examples/payloads/polar.hr.v1.json` |
| `polar.ppi` | `1.0` | Polar Verity Sense | `ppi` | accepted | `packages/schemas/payloads/polar/polar.ppi.v1.schema.json` | `packages/schemas/examples/payloads/polar.ppi.v1.json` |
| `polar.acc` | `1.0` | Polar H10 | `acc` | accepted | `packages/schemas/payloads/polar/polar.acc.v1.schema.json` | `packages/schemas/examples/payloads/polar.acc.v1.json` |
| `polar.ecg` | `1.0` | Polar H10 | `ecg` | accepted | `packages/schemas/payloads/polar/polar.ecg.v1.schema.json` | `packages/schemas/examples/payloads/polar.ecg.v1.json` |
| `polar.device_battery` | `1.0` | Polar H10 | `device_battery` | accepted | `packages/schemas/payloads/polar/polar.device_battery.v1.schema.json` | `packages/schemas/examples/payloads/polar.device_battery.v1.json` |
| `muse.eeg` | `1.0-draft` | Muse Athena | `eeg` | draft | `packages/schemas/payloads/muse/muse.eeg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.eeg.v1-draft.json` |
| `muse.ppg` | `1.0-draft` | Muse Athena | `ppg` | draft | `packages/schemas/payloads/muse/muse.ppg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.ppg.v1-draft.json` |

## Rules

- Transport schema versions and payload versions are independent.
- Draft payloads must remain clearly marked as draft.
- Ingestion validates the transport envelope only; payload content remains opaque at ingest boundary.
- Deep sensor parsing belongs after raw ingestion.
- `polar.device_battery` is a known device-status stream and is non-analytical by default.
- Analytical HR/ACC/ECG pipeline steps must skip `device_battery` unless a dedicated battery handler is added.
