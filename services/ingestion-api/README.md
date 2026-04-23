# Ingestion API

Placeholder for the backend ingestion service.

Initial responsibility:

- accept `UploadChunkContract`
- validate the outer transport envelope
- check that the referenced payload schema is registered or allowed
- persist raw chunks durably before deep parsing
- return `AckContract` or `ErrorContract`

This service should remain lightweight. It should not compute derived features or perform full analytics during initial ingestion.
