# Schemas

Shared JSON Schema contracts for wearable transport and payload data.

## Layout

- `transport/` - stable collector-to-backend transport contracts
- `payloads/` - sensor-specific payload contracts
- `examples/transport/` - example transport documents
- `examples/payloads/` - example inner payload documents

## Contract Boundary

Transport schemas define the upload envelope and backend response shapes.
Payload schemas define sensor-specific data inside `UploadChunkContract.payload`.

Ingestion validates and stores raw chunks first. Parsing and normalization happen later.

## Validation

At minimum, every schema and example should be valid JSON:

```bash
tools/scripts/validate-json.sh
```

For full JSON Schema validation, use a Draft 2020-12 compatible validator such as `ajv` or `python-jsonschema` in a later tooling step.
