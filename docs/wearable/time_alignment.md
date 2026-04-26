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
- ACC and ECG: prefer `device_time_ns` as the strongest timestamp basis
- HR: use collector event time (`received_at_collector`) as the event timestamp basis

When both device and collector time fields are present, device time wins for timestamped signal streams.

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
   - for ACC and ECG, prefer `device_time_ns`
   - for HR event samples, use collector event time
3. Expand any batch payload to sample-level records.
4. Assign `ts_utc` to each sample.
5. Record alignment confidence and reasoning.
6. Emit a time-alignment artifact for inspection.

This keeps alignment explicit, reproducible, and reviewable.

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
