# iOS Collector

Placeholder for the iOS wearable collector application.

The collector direction is one app with multiple sensor adapters:

- Polar Verity Sense first
- Muse Athena later

Responsibilities:

- connect to sensors
- group samples into upload chunks
- attach shared transport metadata
- locally buffer where needed
- upload raw-first payloads to the ingestion API
- expose debug state for sessions, streams, packet counts, and upload status

The collector should not own backend parsing or analytical normalization.
