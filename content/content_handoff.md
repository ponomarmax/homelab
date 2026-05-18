# Content Handoff

Date: 2026-05-18
Scope: Polar Verity Sense offline PPI timestamp semantics, normalization strategy, validation status, and notebook tooling handoff.

## What Changed
- Normalization policy for offline PPI was aligned to cumulative reconstruction from `ppInMs` when raw timestamp basis is low-confidence.
- Added quality-oriented PPI labels and provenance fields in normalized output:
  - `pp_error_band`
  - `sample_quality_tier`
  - blocker/contact quality flags
  - timestamp-origin markers
- Added configurable startup delay controls for PPI reconstruction:
  - env toggles
  - per-session/per-chunk overrides
- Updated docs to reflect cumulative PPI reconstruction constraints and quality thresholds.
- Added stream-specific tests for Verity Sense offline PPI edge cases.

## Deployment + Session Validation
- Updated `wearable-pipeline-api` was deployed.
- Target session rerun completed: `a3b4f7a4-c810-4e7a-8152-e9a05dd32b1e`.
- Latest server-side alignment report indicates:
  - `alignment_basis_level = L2`
  - `alignment_basis = ppi_cumulative_reconstruction`
  - session window reconstructed across the full expected duration.

## Notebook Deliverables
- Main analysis notebook retained and hardened:
  - `notebooks/ppi_time_alignment_strategies.ipynb`
- Interactive Plotly version added:
  - `notebooks/ppi_time_alignment_strategies_plotly.ipynb`
- Plot behavior safeguards:
  - canonical chart now warns/blocks when local normalized cache is stale or incompatible with L2 cumulative basis.
  - anchors on canonical plot are tied to the exact basis used by normalization report.

## Known Caveat
- Local cached artifacts may lag server reruns. If canonical plot guard triggers, refresh local `data.parquet` and `time_alignment_report.json` from the latest server output before interpretation.

## Next Suggested Actions
1. Keep canonical validation tied to report-derived anchors only (single time-domain).
2. Use interactive Plotly notebook for detailed zoom/pan QA on outliers and quality tiers.
3. Add a small cache-refresh helper cell/script to reduce manual sync friction before notebook reviews.
