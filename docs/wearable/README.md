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
