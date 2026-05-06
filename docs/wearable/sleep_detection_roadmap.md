# Sleep Detection Roadmap

## Purpose

This document defines the sleep detection roadmap for the HomeLab wearable pipeline as a documentation checkpoint before runtime implementation.

Scope by version:
- V1 target: sleep/wake detection plus signal quality handling
- V2 target: night/session sleep summary
- V3 target: external reference comparison
- V4 target: experimental sleep stage candidates

Explicit out-of-scope:
- PSG-like clinical sleep staging is out of scope for this roadmap and for consumer-sensor-only inference.

---

## Architecture Principles

- Ingestion stays raw-first and opaque.
- Canonical `ts_utc` is assigned only in normalization.
- PPI/ACC quality must be evaluated before sleep inference.
- Sleep detection must consume deterministic window features.
- LLM/reporting remains downstream and must not perform sleep detection.
- The session-based pipeline remains primary, with night-level aggregation allowed across midnight.
- External consumer tools are comparison baselines, not clinical ground truth.

---

## Evidence and Limitations

- PPI plus ACC can support practical sleep/wake estimation.
- PPI plus ACC alone are not sufficient for clinical-grade sleep staging.
- Stage-like outputs must be labeled as candidates unless validated against stronger ground truth.
- Quality flags, contact status, blocker flags, gaps, and motion artifacts must influence confidence.
- Sleep2, Garmin, and similar consumer outputs can be useful for comparison, and disagreement must be tracked explicitly rather than hidden.

---

## Checkpoint Roadmap

### CP14 - PPI normalization

Goal:
- Add normalizer support for `polar.ppi`.
- Produce clean sample-level PPI Parquet.
- Preserve raw PPI timing and quality fields.
- Emit `time_alignment_report.json`.
- Validate monotonic timestamps, gaps, invalid ratio, and idempotent reruns.

Definition of Done:
- Expected files/artifacts:
  - clean PPI time-series artifact in processed storage (Parquet)
  - `time_alignment_report.json`
  - pipeline run state entry for CP14
- Tests or validation commands:
  - targeted pipeline normalization test for PPI
  - narrow smoke run for one known PPI session
  - raw artifact immutability check before/after rerun
- Manual validation criteria:
  - timestamps are monotonic after normalization
  - preserved raw timing/quality fields are inspectable
  - gap and invalid-ratio indicators are present and readable
- Out-of-scope:
  - any sleep inference
  - any PPI-driven feature modeling beyond normalization outputs

### CP15 - PPI quality diagnostics

Goal:
- Produce `ppi_quality_summary.json`.
- Compute valid ratio, blocker ratio, contact-loss ratio, gap ratio, and `pp_error` statistics.
- Add notebook-oriented inspection guidance.
- No sleep inference yet.

Definition of Done:
- Expected files/artifacts:
  - `ppi_quality_summary.json`
  - updated notebook guidance for PPI quality inspection
- Tests or validation commands:
  - targeted unit/step tests for quality metric computation
  - schema/shape check for `ppi_quality_summary.json`
- Manual validation criteria:
  - summary clearly separates valid, blocked, contact-loss, and gap behavior
  - at least one real/sanitized session can be inspected end-to-end in notebook flow
- Out-of-scope:
  - sleep/wake classification
  - stage candidate outputs

### CP16 - Sleep feature windows

Goal:
- Build 30s, 60s, and 5m sleep-oriented feature windows.
- Include HR/PPI-derived features where data is sufficient:
  - mean HR
  - median PPI
  - SDNN
  - RMSSD
  - pNN50
- Include PPI quality features.
- Include ACC-derived motion features.
- Output deterministic feature artifacts.

Definition of Done:
- Expected files/artifacts:
  - deterministic sleep feature window artifacts (Parquet or equivalent pipeline-standard format)
  - artifact metadata tied to session and stream lineage
- Tests or validation commands:
  - deterministic feature calculation tests
  - rerun idempotence checks for feature artifacts
- Manual validation criteria:
  - features are inspectable by window size (30s, 60s, 5m)
  - missing-data handling is explicit and consistent
- Out-of-scope:
  - ML models
  - final sleep stage labeling

### CP17 - Sleep/wake baseline

Goal:
- Implement deterministic rule-based sleep/wake classifier.
- Output epoch-level `sleep_probability` and state.
- Keep rules inspectable and configurable.
- No ML yet.

Definition of Done:
- Expected files/artifacts:
  - epoch-level sleep/wake output artifact
  - config document or config artifact for rule thresholds
- Tests or validation commands:
  - deterministic classifier rule tests
  - consistency checks across reruns on the same inputs
- Manual validation criteria:
  - operator can inspect which rule paths contributed to state decisions
  - confidence behavior reflects data-quality and motion conditions
- Out-of-scope:
  - deep-learning or opaque models
  - clinical staging claims

### CP18 - Night/session sleep summary

Goal:
- Build `sleep_summary.json` or `night_summary.json`.
- Include:
  - estimated sleep start/end
  - wake time
  - sleep duration
  - wake-after-sleep-onset proxy
  - number of awakenings
  - sleep efficiency proxy
  - lowest HR
  - HRV summary
  - data quality section
  - confidence
- Support cross-midnight sessions.

Definition of Done:
- Expected files/artifacts:
  - `sleep_summary.json` or `night_summary.json`
  - cross-midnight-safe session linkage metadata
- Tests or validation commands:
  - summary schema/shape tests
  - cross-midnight session regression test
- Manual validation criteria:
  - summary fields are explainable from deterministic upstream artifacts
  - cross-midnight behavior is reproducible and inspectable
- Out-of-scope:
  - external comparison auto-calibration
  - interpretation/generation by LLM inside detection logic

### CP19A - Manual sleep validation notebook

Goal:
- Add manual validation workflow.
- Visualize HR, PPI, ACC, artifacts, detected sleep/wake, gaps, battery (if available).
- Support manual notes: bedtime, wake time, perceived sleep quality, awakenings.

Definition of Done:
- Expected files/artifacts:
  - notebook workflow for manual sleep validation
  - saved example notes template for manual annotation
- Tests or validation commands:
  - notebook execution check on a small known session
  - artifact load checks for expected upstream files
- Manual validation criteria:
  - workflow supports practical review of one night/session from raw context to summary
  - notes can be recorded without mutating source artifacts
- Out-of-scope:
  - automated clinical scoring
  - productionized annotation service

### CP19B - Sleep2 reference comparison

Goal:
- Add roadmap guidance for comparing HomeLab sleep outputs against Sleep2 outputs from the same Polar PPI data.
- Treat Sleep2 as the best available consumer reference, not clinical ground truth.
- Compare:
  - sleep duration
  - sleep continuity
  - sleep quality
  - sleep efficiency
  - regularity
  - wake time
  - sleep onset
  - number of awakenings
  - lowest HR
  - HR variability
  - heart rate trends
  - hypnogram-like phases such as deep, REM, and prolonged phases
- Track agreement and disagreement explicitly.
- Do not tune blindly to match Sleep2.
- Keep HomeLab outputs explainable.

Definition of Done:
- Expected files/artifacts:
  - documented comparison methodology section
  - planned comparison artifact contracts (see Future Artifacts)
- Tests or validation commands:
  - consistency checks for metric extraction and delta computation rules
  - representative manual comparison runbook check
- Manual validation criteria:
  - mismatches are visible and retained, not overwritten
  - per-metric notes explain likely definition/algorithm differences
- Out-of-scope:
  - treating Sleep2 as medical truth
  - auto-optimizing core logic to mimic Sleep2 outputs

### CP19C - Garmin / other wearable comparison

Goal:
- Add roadmap guidance for future Garmin comparison.
- Use a metric mapping layer due to potential definition differences.
- Compare only compatible definitions.
- Keep source-specific comparison notes.
- Do not merge Garmin-specific assumptions into core sleep detection logic.

Definition of Done:
- Expected files/artifacts:
  - source-aware metric mapping guidance
  - source-specific comparison notes template
- Tests or validation commands:
  - metric compatibility checks for mapping rules
  - delta computation checks on compatible metrics only
- Manual validation criteria:
  - incompatible metrics are clearly marked and excluded from direct scoring
  - comparison notes preserve source-specific caveats
- Out-of-scope:
  - hard-coding Garmin assumptions into core deterministic detection
  - cross-source metric coercion without mapping rationale

### CP20 - Experimental sleep stage candidates

Goal:
- Start only after CP17 to CP19 are stable.
- Output:
  - `light_sleep_candidate`
  - `deep_sleep_candidate`
  - `rem_candidate`
  - `wake`
- Mark low confidence unless validated.
- Do not present as medical or PSG-equivalent stages.

Definition of Done:
- Expected files/artifacts:
  - candidate stage artifact with explicit confidence fields
  - confidence and caveat documentation
- Tests or validation commands:
  - deterministic candidate labeling tests
  - confidence-behavior sanity tests under poor-quality data
- Manual validation criteria:
  - candidate labels are auditable from feature context
  - low-confidence scenarios are clearly flagged
- Out-of-scope:
  - clinical staging claims
  - replacing sleep/wake baseline with stage-first logic

### CP21 - ML baseline

Goal:
- Proceed only if enough labeled or weakly labeled data exists.
- Start with simple models, not deep learning.
- Keep deterministic features as model inputs.
- Evaluate against held-out nights, manual labels, Sleep2 comparison, Garmin comparison, or stronger future reference labels.

Definition of Done:
- Expected files/artifacts:
  - baseline model experiment artifacts
  - reproducible evaluation report with clear dataset split notes
- Tests or validation commands:
  - reproducibility checks for training/evaluation pipeline
  - held-out-night evaluation summary checks
- Manual validation criteria:
  - feature provenance remains traceable to deterministic pipeline artifacts
  - model gains are interpretable versus CP17 deterministic baseline
- Out-of-scope:
  - deep-learning-first experiments
  - deploying opaque models without baseline interpretability

---

## Comparison Principles

- Sleep2, Garmin, and similar tools are external references, not clinical ground truth.
- PSG/EEG-based scoring remains the clinical reference.
- Consumer tools may disagree due to different sensors, algorithms, metric definitions, and smoothing rules.
- HomeLab should store comparison deltas and source notes rather than overwriting its own deterministic outputs.
- The goal is to understand agreement/disagreement patterns, not to imitate another tool.
- Stage comparison is exploratory and candidate-only unless validated with stronger reference data.

---

## Expected Future Comparison Artifacts

Planned documentation and artifact contracts (not implemented by this checkpoint):
- `sleep_reference_input.json`
- `sleep_reference_comparison.json`
- `sleep_metric_mapping.md`
- `notebooks/03_sleep_validation.ipynb`
- `notebooks/04_sleep_reference_comparison.ipynb`

---

## Implementation Boundaries

This checkpoint is documentation-only:
- no runtime code changes
- no ingestion behavior changes
- no new services
- no PPI processing implementation in this step
