# Data Strategy

## Data Sources

Planned sources:
- Home Assistant sensors
- Garmin data if accessible
- sleep-related external app data if accessible
- Polar Verity Sense wearable collection
- future Muse Athena wearable collection

---

## Data Categories

Environmental:
- temperature
- humidity
- air quality
- noise
- light

Sleep / physiology:
- sleep duration
- sleep stages
- heart rate
- HRV
- PPI / RR-like intervals where available
- accelerometer-based movement
- future EEG / PPG exploration
- related derived metrics

Current strict wearable MVP:
- HR only
- Polar Verity Sense
- session-based collection
- raw JSONL first, then normalized and aggregated layers

---

## Main Goals

- collect data over time
- build structured historical datasets
- analyze relationships between sleep and environment
- keep deterministic artifacts before any interpretive layer

---

## Analysis Goals

Target analyses:
- sleep vs temperature
- sleep vs humidity
- sleep vs air quality
- sleep vs light/noise where data exists

---

## Future ML Direction

Potential future tasks:
- sleep quality prediction
- anomaly detection
- personalized pattern discovery

---

## Principles

- start simple
- validate each data source first
- avoid overengineering
- keep data pipelines understandable
- prefer reliable small datasets over noisy large ones
- retain raw wearable uploads before parsing or normalization
- keep ingestion separate from sensor-specific parsing
- keep canonical analytical time assignment in normalization, not ingestion
- keep pipeline steps independently verifiable

---

## Risks

- limited API availability
- missing data
- noisy data
- inconsistent timestamps across sources

---

## Wearable Data Layers

The wearable pipeline should follow these layers:

1. Raw (`JSONL`)
   - append-only
   - preserves all timestamps
   - full truth

2. Clean time series (`Parquet`)
   - sample-level rows
   - canonical `ts_utc`
   - no aggregation

3. Window features (`Parquet`)
   - first aggregation layer
   - target windows include `30s`, `1m`, and `5m`

4. Nightly summary (`JSON`)
   - deterministic
   - non-LLM

5. Report (`Markdown`)
   - interpretation layer only

6. Telegram output
   - final delivery layer

---

## Time Alignment Strategy

Rules:
- preserve all raw timing fields
- do not assume collector receipt time equals sample time
- assign canonical `ts_utc` only in normalization
- expand batched inputs into sample-level rows
- emit `time_alignment_report.json` for inspection

Confidence levels:
- high
- medium
- low

---

## Environment Compatibility

Environment data should remain compatible with the same high-level raw-to-clean-to-features model.

Key differences:
- environment data is continuous
- environment data is time-partitioned, not session-based
- wearable or sleep sessions define later join windows

Do not bind environment data to sessions during ingestion.

---

## Integration Strategy

For each new source:
1. validate access method
2. inspect schema
3. define storage format
4. test small sample
5. automate only after validation

## Raw Storage Layout (Baseline V1)

All wearable raw data is stored as append-only JSONL.

### Directory structure


/data/wearable/raw/
user_id=<user_id>/
source=<vendor>_<device_model>/
date=<YYYY-MM-DD>/
session_id=<session_id>/
streams/
<stream_type>/
chunks.jsonl


### Rules

- append-only
- one upload request = one JSON line
- one `chunks.jsonl` per session per stream_type
- no mutation of existing records
- no processing state in raw layer
- raw layer is the source of truth
