# Wearable Time Alignment

## Purpose

This document defines the time-alignment model for the wearable pipeline.

The goal is to preserve raw truth while producing one canonical analytical timestamp for downstream processing.

---

## Core Rules

- raw timestamps are always preserved
- `ts_utc` is the canonical analytical timestamp
- timestamp alignment happens only in the normalizer
- the normalizer expands batch payloads into sample-level rows
- the normalizer does not aggregate
- `sample_rate_hz` is metadata only and is not an authoritative timing source

This means ingestion stores raw transport truth, while normalization creates analytical time alignment.

---

## Why This Matters

The pipeline must support multiple collection patterns:
- live mode
- offline mode
- imported or expanded batch data

These modes can differ in:
- when the sample was measured
- when the collector received it
- when the collector uploaded it
- when the server accepted it

Because of that, the system must never assume collector receipt time equals real sample time.

---

## Canonical Timestamp Model

### Raw Layer

The raw layer keeps all available source timestamps, such as:
- source sample timestamp if available
- device time reference if available
- `received_at_collector`
- `uploaded_at_collector`
- `received_at_server`

No canonical analytical timestamp is imposed at raw-ingestion time.

### Clean Time-Series Layer

The clean layer introduces:
- `ts_utc` as the canonical timestamp for downstream use

This layer is responsible for:
- choosing the best available timestamp basis
- expanding batches into sample rows
- recording alignment confidence
- preserving traceability to raw origin

### Stream-Specific Priority

The normalizer must choose timing basis per stream type:
- `acc`, `gyro`, `mag`, `ppg`: prefer L0 recording metadata (`recording_start_utc`/`recording_end_utc`) when valid
- `ppi`: prefer sample timestamps when valid; zero/invalid timestamps trigger fallback + confidence degradation.
  For Verity Sense offline PPI, canonical timeline fallback is interval-based (`ppInMs` cumulative), not nominal fixed-rate cadence.
- `hr`: prefer sample/event timestamps if present; otherwise reconstruct from cadence within resolved session window

Collector/server timestamps are fallback only (L4).

---

## Supported Modes

### 1. Live Mode

Expected characteristics:
- streaming or near-streaming samples
- lower uncertainty
- collector and sample time are usually close, but not assumed identical

Typical alignment basis:
- source-provided sample time when available
- otherwise collector/device-derived reference with documented confidence

### 2. Offline Mode

Expected characteristics:
- data may be stored on device first
- upload can happen much later
- collector receipt and upload times may be far from real sample time

Typical alignment basis:
- source session timing and per-sample offsets
- device-export timing if provided
- for Polar Verity Sense offline ACC/PPG/MAG/GYRO/PPI payloads, use payload `samples[].timeStamp` as the strongest source time signal

### 3. Batch Expansion

Expected characteristics:
- one payload can represent multiple samples
- samples may need to be reconstructed from a start time and cadence

Rule:
- expand the batch into individual samples
- assign one `ts_utc` per sample
- do not aggregate during normalization
- do not assume offset-based batching when explicit `device_time_ns` exists

---

## Alignment Process

The normalizer should follow this order of intent:

1. Preserve raw timestamp fields untouched.
2. Determine the strongest available time reference.
   - first try L0 session/file metadata
   - then L1 sample timestamps with validated mapping
   - then L2 cross-stream anchoring
   - then L3 cadence reconstruction
   - use L4 collector/server only as last resort
3. Expand any batch payload to sample-level records.
4. Assign `ts_utc` to each sample.
5. Record alignment confidence and reasoning.
6. Emit a time-alignment artifact for inspection.

This keeps alignment explicit, reproducible, and reviewable.

### Session-Level Confidence Ladder (L0-L4)

Use one deterministic policy registry for every offline session:

1. `L0` device-native recording metadata:
   - `recording_start_utc`, `recording_end_utc`
   - optional validators: `file_created_at_device`, `file_closed_at_device`
2. `L1` sample timestamps + validated clock mapping:
   - `samples[].timeStamp`
   - `clock_sync_state` must be `synced` for high confidence
   - `clock_drift_estimate` above `100 ppm` degrades confidence
3. `L2` cross-stream anchoring:
   - default anchor pool: `acc,gyro,mag,ppg`
   - anchor pool and thresholds are config-driven
4. `L3` cadence reconstruction:
   - infer from sample order + stream nominal rate
5. `L4` collector/server fallback:
   - `fetch_started_at_collector` / `fetch_completed_at_collector`
   - legacy fallback: `first_sample_received_at_collector` / `uploaded_at_collector`

Quality gates:
- reject implausible absolute years outside `[2018, current_year+1]`
- reject session duration `> 48h`
- degrade confidence for mixed valid/invalid timestamps
- treat `ppi` zero timestamps as recoverable (warning + degradation), not hard fail
- for `ppi` quality annotation:
  - `ppErrorEstimate < 10ms` => high quality likelihood
  - `10ms <= ppErrorEstimate <= 30ms` => moderate quality
  - `ppErrorEstimate > 30ms` => low quality marker
  - `blockerBit=1` => low quality marker
  - `skinContactSupported=1` and `skinContactStatus=0` => contact warning marker (device dependent; do not hard-fail timeline)
- L0 cross-stream consistency (config-driven):
  - `L0_CROSS_STREAM_MAX_START_DELTA_SECONDS` (default `10`)
  - `L0_CROSS_STREAM_MAX_END_DELTA_SECONDS` (default `10`)
  - `L0_CROSS_STREAM_MIN_OVERLAP_RATIO` (default `0.5`)
  - `L0_CROSS_STREAM_MIN_ANCHOR_STREAMS` (default `2`)
  - `L0_CROSS_STREAM_ANCHOR_STREAMS` (default `acc,gyro,mag,ppg`)
- if L0 stream fails cross-stream gate: downgrade to L2 and emit warning `l0_cross_stream_inconsistent`

---

## Confidence Levels

Each normalized output should carry or be traceable to an alignment confidence level:
- `high`
- `medium`
- `low`

Suggested interpretation:

### High
- source sample timestamps are explicit and trustworthy
- or sample timing is reconstructed from strong device timing and known cadence

### Medium
- timing is reconstructed from partial metadata with reasonable assumptions
- sample order is trusted, but exact timing may include bounded uncertainty

### Low
- timing depends on weak fallback assumptions
- exact sample timing is uncertain even if ordering is preserved

Confidence does not block ingestion.
It documents analytical trust level for later use.

---

## Required Artifact

Normalization must produce:
- `time_alignment_report.json`

Purpose:
- explain how timestamps were assigned
- capture confidence level
- capture alignment method
- expose warnings or fallback paths

Suggested content:
- session id
- stream id
- source mode
- alignment basis
- confidence level
- batch expansion details if relevant
- warnings

This artifact helps verify alignment decisions without re-reading raw payloads manually.

### PPI Startup Delay (Configurable)

For Verity Sense offline PPI sessions where timestamps are mostly zero/invalid or mapped with low confidence, the normalizer may apply startup delay before interval-based reconstruction.

- Per-session toggle: `time.apply_ppi_startup_delay` (`true`/`false`)
- Per-session override: `time.ppi_startup_delay_seconds`
- Environment defaults:
  - `ENABLE_PPI_STARTUP_DELAY` (default `false`)
  - `PPI_STARTUP_DELAY_SECONDS` (default `25`)

The startup delay is intended for known Verity Sense PPI batching behavior and should be applied only for relevant sessions/modes.

---

## Traceability Rules

Normalized rows should remain traceable to raw inputs.

Traceability should support:
- linking clean rows back to raw chunk/session/stream identifiers
- understanding which alignment method was applied
- reviewing uncertainty when downstream outputs look suspicious

This is required for debugging and later multimodal extension.

---

## What the Normalizer Must Not Do

The normalizer must **not**:
- aggregate samples into windows
- compute nightly summary values
- compute report text
- overwrite or discard raw timing fields
- assume HR-specific timing rules are universal forever

Its job is only to convert raw transport data into canonical sample-level analytical rows.

---

## Environment Compatibility

Environment data will follow the same high-level rule:
- raw timestamps preserved
- canonical cleaned timestamp introduced later

But environment ingestion is continuous rather than session-based.

That means:
- environment data should remain time-partitioned
- sleep or wearable session boundaries are applied later during joins
- session logic must not leak into environment ingestion

---

## Non-Goals

This document does not define:
- final clean Parquet schema in full detail
- feature schemas
- sleep-stage alignment
- cross-source correlation logic
- ML-oriented temporal modeling

It defines only the canonical timestamp alignment principles for the MVP and near-term extension.
