# Payload Registry

This registry lists sensor-specific payload contracts that may be referenced by `StreamDescriptorContract.payload_schema` and `UploadChunkContract.transport.payload_schema`.

| Payload schema | Version | Sensor | Stream type | Status | Schema file | Example |
| --- | --- | --- | --- | --- | --- | --- |
| `polar.hr` | `1.0` | Polar Verity Sense | `hr` | accepted | `packages/schemas/payloads/polar/polar.hr.v1.schema.json` | `packages/schemas/examples/payloads/polar.hr.v1.json` |
| `polar.ppi` | `1.0` | Polar Verity Sense | `ppi` | accepted | `packages/schemas/payloads/polar/polar.ppi.v1.schema.json` | `packages/schemas/examples/payloads/polar.ppi.v1.json` |
| `polar.acc` | `1.0` | Polar Verity Sense | `acc` | accepted | `packages/schemas/payloads/polar/polar.acc.v1.schema.json` | `packages/schemas/examples/payloads/polar.acc.v1.json` |
| `muse.eeg` | `1.0-draft` | Muse Athena | `eeg` | draft | `packages/schemas/payloads/muse/muse.eeg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.eeg.v1-draft.json` |
| `muse.ppg` | `1.0-draft` | Muse Athena | `ppg` | draft | `packages/schemas/payloads/muse/muse.ppg.v1-draft.schema.json` | `packages/schemas/examples/payloads/muse.ppg.v1-draft.json` |

## Rules

- Transport schema versions and payload versions are independent.
- Draft payloads must remain clearly marked as draft.
- Ingestion should validate that a referenced payload schema is registered or explicitly allowed.
- Deep sensor parsing belongs after raw ingestion.
